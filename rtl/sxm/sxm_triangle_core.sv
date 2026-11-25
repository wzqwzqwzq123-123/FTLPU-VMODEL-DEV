`timescale 1ns/1ps
// Batch transform interface: matrix rows become BLOCK8 outputs; vector rows retain row layout.
// Mode 0/1 selects matrix/vector, dtype 0/1 selects BF16/FP32; each source captures the low 256 bits.
module sxm_triangle_core #(
	parameter integer T = 4,
	parameter integer TIMER_BITS = 16,
	localparam integer TW = $clog2(T)
) (
	input wire clk_i,
	input wire rst_ni,

	// A job samples its format and maps only while all sources are idle and fault-free.
	input wire job_valid_i,
	output wire job_ready_o,
	input wire [1:0] mode_i,
	input wire [1:0] dtype_i,
	input wire [15:0] count_i,
	input wire [T*24-1:0] lane_map_i,
	input wire [T*TW-1:0] tile_map_i,

	// Each accepted source beat contains eight 32-bit lane containers.
	input wire [T-1:0] cap_valid_i,
	input wire [T*8-1:0] cap_lane_valid_i,
	input wire [T*2048-1:0] cap_data_i,
	output wire [T-1:0] cap_accept_o,

	// Outputs are due-cycle transactions; an unaccepted due block sets a sticky fault.
	input wire [T-1:0] block_ready_i,
	output reg [T-1:0] block_valid_o,
	output reg [T-1:0] block_fp32_o,
	output reg [T-1:0] block_vector_o,
	output reg [T*2048-1:0] block_data_o,
	output reg [T*16-1:0] block_matrix_o,
	output reg [T*TW-1:0] block_column_o,
	output wire busy_o,
	output wire fault_o
);
	// Resident job configuration and the count of accepted output blocks.
	reg active_q, fault_q, fp32_q;
	reg [1:0] mode_q;
	reg [15:0] count_q;
	reg [T*24-1:0] lane_q;
	reg [T*TW-1:0] tile_q;
	reg [TIMER_BITS-1:0] timer_q;
	reg [31:0] sent_q;

	// Source-local storage exports one due block and its destination metadata.
	wire [T-1:0] source_valid, source_fp32, source_vector, source_fault, source_busy;
	wire [T*TW-1:0] source_dest, source_column;
	wire [T*16-1:0] source_matrix;
	wire [T*2048-1:0] source_data;
	reg config_ok, collision_now;
	integer i, j, nfire, ci, cj;

	assign fault_o = fault_q || (|source_fault) || collision_now;
	assign busy_o = active_q || (|source_busy);
	assign job_ready_o = !busy_o && !fault_o;

	// Detect simultaneous source blocks targeting the same destination Tile.
	always @* begin
		collision_now = 0;
		for(ci = 0; ci < T; ci = ci + 1)begin
			for(cj = ci + 1; cj < T; cj = cj + 1)begin
				if(source_valid[ci] && source_valid[cj] && source_dest[ci*TW+:TW] == source_dest[cj*TW+:TW])begin
					collision_now = 1;
				end
			end
		end
	end

	// Accept only supported formats, nonempty jobs and a bijective Tile map.
	always @* begin
		config_ok = (mode_i <= 1 && dtype_i <= 1 && count_i != 0);
		for(i = 0; i < T; i = i + 1)begin
			if(int'(tile_map_i[i*TW+:TW]) >= T)begin
				config_ok = 0;
			end
			for(j = 0; j < i; j = j + 1)begin
				if(tile_map_i[i*TW+:TW] == tile_map_i[j*TW+:TW])begin
					config_ok = 0;
				end
			end
		end
	end

	// Count only output blocks accepted at this edge; rejected due blocks do not retire.
	always @* begin
		nfire = 0;
		for(integer fire_index = 0; fire_index < T; fire_index = fire_index + 1)begin
			if(block_valid_o[fire_index] && block_ready_i[fire_index])begin
				nfire = nfire + 1;
			end
		end
	end

	// The free-running timestamp is shared by all source-local due-cycle comparisons.
	always @(posedge clk_i) begin
		if(!rst_ni)begin
			timer_q <= 0;
		end
		else begin
			timer_q <= timer_q + 1'b1;
		end
	end

	// Keep admission, its sticky fault and output retirement ordered within the shared job state.
	always @(posedge clk_i) begin
		if(!rst_ni)begin
			active_q <= 0;
			fault_q <= 0;
			fp32_q <= 0;
			mode_q <= 0;
			count_q <= 0;
			lane_q <= 0;
			tile_q <= 0;
			sent_q <= 0;
		end
		else begin
			if(collision_now)begin
				fault_q <= 1;
			end
			// Admission captures immutable job parameters and restarts output accounting.
			if(job_valid_i)begin
				if(!job_ready_o || !config_ok)begin
					fault_q <= 1;
				end
				else begin
					active_q <= 1;
					fp32_q <= dtype_i[0];
					mode_q <= mode_i;
					count_q <= count_i;
					lane_q <= lane_map_i;
					tile_q <= tile_map_i;
					sent_q <= 0;
				end
			end

			// Retirement reads the pre-edge job state and has the original same-edge priority.
			if(active_q && nfire != 0)begin
				sent_q <= sent_q + 32'(nfire);
				if(sent_q + 32'(nfire) == ((mode_q == 0) ? 32'(count_q)*(T*T) : 32'(count_q)*T))begin
					active_q <= 0;
				end
			end
		end
	end

	// Source s owns s+1 slots; the staggered due time forms the triangular storage geometry.
	for(genvar source_index = 0; source_index < T; source_index = source_index + 1)begin : g_source
		localparam integer D = source_index + 1, PW = (D < 2) ? 1 : $clog2(D);
		// Payload arrays remain unreset; occupancy and completion bits guard their use.
		reg [31:0] data_q[0:D-1][0:7][0:7]; // [slot][input row][lane]
		reg [D-1:0] occupied_q, complete_q;
		reg [TIMER_BITS-1:0] due_q[0:D-1];
		reg [TW-1:0] dest_q[0:D-1];
		reg [15:0] matrix_q[0:D-1];
		reg [PW-1:0] wr_q, rd_q;
		reg [31:0] received_q;
		reg bad_q;

		// Derive the source row, logical destination and matrix index from accepted captures.
		wire [2:0] row_now = (mode_q == 0) ? received_q[2:0] : 3'd0;
		wire [TW-1:0] a_now = (mode_q == 0) ? TW'(received_q >> 3) : TW'(source_index);
		wire [15:0] matrix_now = (mode_q == 0) ? 16'(received_q/(8*T)) : 16'(received_q);
		wire [TW-1:0] dest_now = tile_q[int'(a_now)*TW+:TW];

		// fire marks the exact due cycle; take additionally requires a fault-free destination handshake.
		wire fire = active_q && complete_q[rd_q] && due_q[rd_q] == timer_q;
		wire take = fire && !fault_o && block_ready_i[dest_q[rd_q]];
		// A first row may reuse a slot retired on this edge; later rows must extend an incomplete slot.
		wire legal_cap = active_q && !fault_o && cap_lane_valid_i[source_index*8+:8] == 8'hff && received_q < ((mode_q == 0) ? 32'(count_q)*(8*T) : 32'(count_q)) && ((row_now == 0) ? (!occupied_q[wr_q] || (take && rd_q == wr_q)) : (occupied_q[wr_q] && !complete_q[wr_q]));
		assign cap_accept_o[source_index] = cap_valid_i[source_index] && legal_cap;

		assign source_valid[source_index] = fire;
		assign source_fp32[source_index] = fp32_q;
		assign source_vector[source_index] = (mode_q == 1);
		assign source_dest[source_index*TW+:TW] = dest_q[rd_q];
		assign source_column[source_index*TW+:TW] = TW'(source_index);
		assign source_matrix[source_index*16+:16] = matrix_q[rd_q];
		assign source_fault[source_index] = bad_q;
		assign source_busy[source_index] = |occupied_q;

		// Matrix mode transposes stored rows; vector mode emits row zero with destination lane permutation.
		for(genvar q = 0; q < 8; q = q + 1)begin : g_row
			for(genvar l = 0; l < 8; l = l + 1)begin : g_lane
				wire [2:0] g = lane_q[int'(dest_q[rd_q])*24+l*3+:3];
				assign source_data[source_index*2048+(q*8+l)*32+:32] = (mode_q == 1) ? ((q == 0) ? data_q[rd_q][0][g] : 32'b0) : data_q[rd_q][g][q];
			end
		end

		integer k, r, l;
		reg [31:0] word_in;
		// Retire before capture so a same-edge capture can repopulate the just-released slot.
		always @(posedge clk_i) begin
			if(!rst_ni)begin
				occupied_q <= 0;
				complete_q <= 0;
				wr_q <= 0;
				rd_q <= 0;
				received_q <= 0;
				bad_q <= 0;
				for(k = 0; k < D; k = k + 1)begin
					due_q[k] <= 0;
					dest_q[k] <= 0;
					matrix_q[k] <= 0;
				end
			end
			else begin
				// Job admission restarts source indices without clearing the payload array.
				if(job_valid_i && job_ready_o && config_ok)begin
					wr_q <= 0;
					rd_q <= 0;
					received_q <= 0;
				end
				if(cap_valid_i[source_index] && !legal_cap)begin
					bad_q <= 1;
				end
				if(fire && !take)begin
					bad_q <= 1;
				end

				// A due block retires once; a missed deadline is not retried on later cycles.
				if(take)begin
					occupied_q[rd_q] <= 0;
					complete_q[rd_q] <= 0;
					rd_q <= (int'(rd_q) == D-1) ? PW'(0) : rd_q + PW'(1);
				end

				// Capture one row and mark the slot complete after its final required row.
				if(cap_accept_o[source_index])begin
					received_q <= received_q + 1;
					if(row_now == 0)begin
						occupied_q[wr_q] <= 1;
						dest_q[wr_q] <= dest_now;
						matrix_q[wr_q] <= matrix_now;
					end
					for(r = 0; r < 8; r = r + 1)begin
						if(r == int'(row_now))begin
							for(l = 0; l < 8; l = l + 1)begin
								word_in = cap_data_i[source_index*2048+l*32+:32];
								data_q[wr_q][r][l] <= fp32_q ? word_in : {16'b0, word_in[15:0]};
							end
						end
					end
					if(mode_q != 0 || row_now == 7)begin
						complete_q[wr_q] <= 1;
						due_q[wr_q] <= timer_q + TIMER_BITS'(1+((mode_q == 0) ? 7*source_index : 0));
						wr_q <= (int'(wr_q) == D-1) ? PW'(0) : wr_q + PW'(1);
					end
				end
			end
		end
	end

	integer d, s;
	// Route fault-free due blocks to destination Tiles; collision detection suppresses all outputs.
	always @* begin
		block_valid_o = 0;
		block_fp32_o = 0;
		block_vector_o = 0;
		block_data_o = 0;
		block_matrix_o = 0;
		block_column_o = 0;
		for(d = 0; d < T; d = d + 1)begin
			for(s = 0; s < T; s = s + 1)begin
				if(!fault_o && source_valid[s] && source_dest[s*TW+:TW] == TW'(d))begin
					block_valid_o[d] = 1;
					block_fp32_o[d] = source_fp32[s];
					block_vector_o[d] = source_vector[s];
					block_data_o[d*2048+:2048] = source_data[s*2048+:2048];
					block_matrix_o[d*16+:16] = source_matrix[s*16+:16];
					block_column_o[d*TW+:TW] = source_column[s*TW+:TW];
				end
			end
		end
	end

`ifndef SYNTHESIS
	// Reject unsupported elaboration profiles before accepting jobs.
	initial begin
		if((T != 2 && T != 4 && T != 8) || TIMER_BITS < 8)begin
			$fatal(1, "triangle profile");
		end
	end
`endif
endmodule
