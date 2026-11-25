`timescale 1ns/1ps
// Schedule native WriteTap commands from Triangle blocks; SRF retains the payload storage.
module lpu_sxm_triangle_mem_adapter #(
	parameter integer T = 4,
	parameter integer H = 2,
	parameter integer DEPTH = 4096,
	localparam integer TW = $clog2(T)
) (
	input wire clk_i,
	input wire rst_ni,

	// Admission requires an idle writer, available resources and a legal address/map profile.
	input wire job_valid_i,
	input wire fp32_i,
	input wire resources_ready_i,
	input wire [15:0] matrices_i,
	input wire [14:0] base_i,
	input wire [T*TW-1:0] tile_map_i,
	output wire job_ready_o,

	// Triangle blocks must arrive at the fixed age and carry the expected matrix/column tags.
	input wire [T-1:0] block_valid_i,
	input wire [T-1:0] block_fp32_i,
	input wire [T*2048-1:0] block_data_i,
	input wire [T*16-1:0] block_matrix_i,
	input wire [T*TW-1:0] block_column_i,
	output reg [T-1:0] block_ready_o,

	// Byte streams feed SRF; commands and target taps account for its fixed transport delay.
	output reg [T*32-1:0] stream_valid_o,
	output reg [T*2048-1:0] stream_data_o,
	output reg [31:0] mem_issue_valid_o,
	output reg [1023:0] mem_issue_o,
	output reg [4*T-1:0] target_tap_o,
	output reg [4*T*15-1:0] target_address_o,
	output wire busy_o,
	output wire fault_o
);
	// Immutable job configuration and cycles elapsed since the accepted start edge.
	reg active_q, bad_q, fp32_q;
	reg [15:0] matrices_q;
	reg [14:0] base_q;
	reg [31:0] age_q;
	reg [T*TW-1:0] inverse_q;
	reg [T*TW-1:0] inverse_now;
	reg legal_map;
	integer ma, mb;

	// Invert the Tile permutation and reject duplicate or out-of-range destinations.
	always @* begin
		inverse_now = 0;
		legal_map = 1;
		for(ma = 0; ma < T; ma = ma + 1)begin
			if(int'(tile_map_i[ma*TW+:TW]) >= T)begin
				legal_map = 0;
			end
			else begin
				inverse_now[int'(tile_map_i[ma*TW+:TW])*TW+:TW] = TW'(ma);
			end
			for(mb = 0; mb < ma; mb = mb + 1)begin
				if(tile_map_i[ma*TW+:TW] == tile_map_i[mb*TW+:TW])begin
					legal_map = 0;
				end
			end
		end
	end

	wire legal_job = legal_map && matrices_i != 0 && 32'(base_i)+32'(matrices_i)*T <= DEPTH && 32'(base_i)+32'(matrices_i)*T <= 32768;
	assign busy_o = active_q;
	assign fault_o = bad_q;
	assign job_ready_o = !active_q && !bad_q && resources_ready_i && legal_job;

	// A malformed block suppresses every block acceptance and Stream valid in this cycle.
	reg bad_now;
	// Match incoming blocks to their statically scheduled age, format and matrix/column tags.
	always @* begin
		integer d, k, n;
		reg expected_block;
		block_ready_o = 0;
		bad_now = 0;
		k = 0;
		n = 0;
		expected_block = 0;
		for(d = 0; d < T; d = d + 1)begin
			expected_block = 0;
			if(active_q && age_q >= 8 && age_q[2:0] == 0)begin
				k = int'(age_q >> 3) - 1;
				n = k - int'(inverse_q[d*TW+:TW]);
				expected_block = n >= 0 && n < int'(matrices_q)*T;
				if(expected_block)begin
					if(!block_valid_i[d] || block_fp32_i[d] != fp32_q || int'(block_matrix_i[d*16+:16]) != n/T || int'(block_column_i[d*TW+:TW]) != n%T)begin
						bad_now = 1;
					end
				end
			end
			if(block_valid_i[d] && !expected_block)begin
				bad_now = 1;
			end
			block_ready_o[d] = expected_block && !bad_q;
		end
		if(bad_now)begin
			block_ready_o = 0;
		end
	end

	// Pack each block into fixed byte destinations; FP32 uses 32 Streams and BF16 uses 16.
	always @* begin
		integer d, st, l;
		stream_valid_o = 0;
		stream_data_o = 0;
		for(d = 0; d < T; d = d + 1)begin
			for(st = 0; st < 32; st = st + 1)begin
				stream_valid_o[d*32+st] = block_valid_i[d] && block_ready_o[d] && (fp32_q || st < 16);
				for(l = 0; l < 8; l = l + 1)begin
					if(fp32_q)begin
						stream_data_o[(d*32+st)*64+l*8+:8] = block_data_i[d*2048+((st/4)*8+l)*32+(st%4)*8+:8];
					end
					else if(st < 16)begin
						stream_data_o[(d*32+st)*64+l*8+:8] = block_data_i[d*2048+((st/2)*8+l)*32+(st%2)*8+:8];
					end
				end
			end
		end
		if(bad_now)begin
			stream_valid_o = 0;
		end
	end

	// Offset each group's command launch by its native MEM hop to align with arriving SRF data.
	always @* begin
		integer g, d, b, delta, k, n, bytes_per_element;
		mem_issue_valid_o = 0;
		mem_issue_o = 0;
		delta = 0;
		k = 0;
		n = 0;
		bytes_per_element = fp32_q ? 4 : 2;
		for(g = 0; g < 4; g = g + 1)begin
			if(g < bytes_per_element && active_q && !bad_q)begin
				for(d = 0; d < T; d = d + 1)begin
					delta = int'(age_q) - (8+H+g-d);
					if(delta >= 0 && delta%8 == 0)begin
						k = delta/8;
						n = k - int'(inverse_q[d*TW+:TW]);
						if(n >= 0 && n < int'(matrices_q)*T)begin
							for(b = 0; b < 8; b = b + 1)begin
								mem_issue_valid_o[g*8+b] = 1;
								mem_issue_o[(g*8+b)*32+:32] = 32'h80000101 | (32'(g*8+b) << 3) | ((32'(base_q)+32'(n)) << 15);
							end
						end
					end
				end
			end
		end
	end

	// Predict the target tap/address at the shared observation age, without the command hop offset.
	always @* begin
		integer g, d, delta, k, n, bytes_per_element;
		target_tap_o = 0;
		target_address_o = 0;
		delta = 0;
		k = 0;
		n = 0;
		bytes_per_element = fp32_q ? 4 : 2;
		for(g = 0; g < 4; g = g + 1)begin
			if(g < bytes_per_element && active_q && !bad_q)begin
				for(d = 0; d < T; d = d + 1)begin
					delta = int'(age_q) - (8+H+g);
					if(delta >= 0 && delta%8 == 0)begin
						k = delta/8;
						n = k - int'(inverse_q[d*TW+:TW]);
						if(n >= 0 && n < int'(matrices_q)*T)begin
							target_tap_o[g*T+d] = 1;
							target_address_o[(g*T+d)*15+:15] = base_q + 15'(n);
						end
					end
				end
			end
		end
	end

	// Maintain job age, resident format/map and sticky admission/block faults at the same edge.
	always @(posedge clk_i) begin
		if(!rst_ni)begin
			active_q <= 0;
			bad_q <= 0;
			fp32_q <= 0;
			matrices_q <= 0;
			base_q <= 0;
			age_q <= 0;
			inverse_q <= 0;
		end
		else begin
			if(bad_now)begin
				bad_q <= 1;
			end
			// The tail bound includes SRF transport, byte groups and the final Tile hop.
			if(active_q)begin
				age_q <= age_q + 1;
				if(age_q == 8+8*(32'(matrices_q)*T+T-2)+H+32'(fp32_q ? 3 : 1)+T)begin
					active_q <= 0;
				end
			end
			// Admission retains its original priority over same-edge age/active updates.
			if(job_valid_i)begin
				if(!job_ready_o)begin
					bad_q <= 1;
				end
				else begin
					active_q <= 1;
					fp32_q <= fp32_i;
					matrices_q <= matrices_i;
					base_q <= base_i;
					age_q <= 0;
					inverse_q <= inverse_now;
				end
			end
		end
	end

`ifndef SYNTHESIS
	// Native WriteTap addresses are 15 bits and the supported Tile profiles are fixed.
	initial begin
		if((T != 2 && T != 4 && T != 8) || H < 1 || DEPTH > 32768)begin
			$fatal(1, "WriteTap profile");
		end
	end
`endif
endmodule
