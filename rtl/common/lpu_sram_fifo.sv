module lpu_sram_fifo #(
	parameter integer DATA_WIDTH = 1,
	parameter integer DEPTH = 16
) (
	input logic clk_i,
	input logic rst_ni,

	input logic enqueue_valid_i,
	output logic enqueue_ready_o,
	input logic [DATA_WIDTH-1:0] enqueue_data_i,

	output logic dequeue_valid_o,
	input logic dequeue_ready_i,
	output logic [DATA_WIDTH-1:0] dequeue_data_o,

	output logic [$clog2(DEPTH+1)-1:0] level_o
);
	localparam integer PTR_WIDTH = DEPTH <= 1 ? 1 : $clog2(DEPTH);
	localparam integer LEVEL_WIDTH = $clog2(DEPTH + 1);

	logic [PTR_WIDTH-1:0] write_ptr_q;
	logic [PTR_WIDTH-1:0] read_ptr_q;
	logic [LEVEL_WIDTH-1:0] level_q;
	logic read_pending_q;
	logic output_valid_q;
	logic [DATA_WIDTH-1:0] output_data_q;
	logic [LEVEL_WIDTH:0] reserved_count_w;
	logic unread_entry_available_w;
	logic output_slot_available_w;
	logic enqueue_fire;
	logic dequeue_fire;
	logic dequeue_request;
	logic sram_cen;
	logic sram_wen;
	logic [PTR_WIDTH-1:0] sram_address;
	logic [DATA_WIDTH-1:0] sram_wdata;
	logic sram_read_valid;
	logic [DATA_WIDTH-1:0] sram_read_data;

	initial begin
		if(DATA_WIDTH < 1 || DEPTH < 1)begin
			$error("DATA_WIDTH and DEPTH must be positive");
		end
	end

	function automatic [PTR_WIDTH-1:0] increment_ptr(input logic [PTR_WIDTH-1:0] ptr);
		if(ptr == DEPTH - 1)begin
			increment_ptr = '0;
		end
		else begin
			increment_ptr = ptr + 1'b1;
		end
	endfunction

	assign dequeue_valid_o = output_valid_q;
	assign dequeue_data_o = output_data_q;
	assign dequeue_fire = dequeue_valid_o && dequeue_ready_i;
	assign level_o = level_q;

	// Reserved entries are already in the output register or have an SRAM read in flight.
	assign reserved_count_w = {{LEVEL_WIDTH{1'b0}}, output_valid_q} +
		{{LEVEL_WIDTH{1'b0}}, read_pending_q};
	assign unread_entry_available_w = {1'b0, level_q} > reserved_count_w;
	assign output_slot_available_w = !output_valid_q || dequeue_fire;

	// A dequeue request reserves the next unread entry and advances the SRAM read pointer.
	assign dequeue_request = !read_pending_q && output_slot_available_w &&
		unread_entry_available_w;

	// The single SRAM port gives reads priority; enqueue backpressure prevents dual-port use.
	assign enqueue_ready_o = !dequeue_request && ((level_q < DEPTH) || dequeue_fire);
	assign enqueue_fire = enqueue_valid_i && enqueue_ready_o;
	assign sram_cen = dequeue_request || enqueue_fire;
	assign sram_wen = enqueue_fire;
	assign sram_address = enqueue_fire ? write_ptr_q : read_ptr_q;
	assign sram_wdata = enqueue_data_i;

	lpu_sram #(
		.DATA_WIDTH(DATA_WIDTH),
		.DEPTH(DEPTH),
		.ADDRESS_WIDTH(PTR_WIDTH)
	) u_storage (
		.clk_i,
		.rst_ni,
		.cen_i(sram_cen),
		.wen_i(sram_wen),
		.address_i(sram_address),
		.wdata_i(sram_wdata),
		.rvalid_o(sram_read_valid),
		.rdata_o(sram_read_data)
	);

	// Advance each pointer only when its corresponding SRAM operation is accepted.
	always_ff @(posedge clk_i or negedge rst_ni) begin
		if(!rst_ni)begin
			write_ptr_q <= '0;
			read_ptr_q <= '0;
		end
		else begin
			if(enqueue_fire)begin
				write_ptr_q <= increment_ptr(write_ptr_q);
			end
			if(dequeue_request)begin
				read_ptr_q <= increment_ptr(read_ptr_q);
			end
		end
	end

	// Logical occupancy changes only when the external enqueue or dequeue handshake fires.
	always_ff @(posedge clk_i or negedge rst_ni) begin
		if(!rst_ni)begin
			level_q <= '0;
		end
		else begin
			case({enqueue_fire, dequeue_fire})
				2'b10: level_q <= level_q + 1'b1;
				2'b01: level_q <= level_q - 1'b1;
				default: level_q <= level_q;
			endcase
		end
	end

	// Track the one allowed read in flight until the SRAM response is captured.
	always_ff @(posedge clk_i or negedge rst_ni) begin
		if(!rst_ni)begin
			read_pending_q <= 1'b0;
		end
		else begin
			case({dequeue_request, sram_read_valid})
				2'b10: read_pending_q <= 1'b1;
				2'b01: read_pending_q <= 1'b0;
				default: read_pending_q <= read_pending_q;
			endcase
		end
	end

	// The output register holds valid data stable until the consumer accepts it.
	always_ff @(posedge clk_i or negedge rst_ni) begin
		if(!rst_ni)begin
			output_valid_q <= 1'b0;
			output_data_q <= '0;
		end
		else begin
			if(dequeue_fire)begin
				output_valid_q <= 1'b0;
			end
			if(sram_read_valid)begin
				output_valid_q <= 1'b1;
				output_data_q <= sram_read_data;
			end
		end
	end
endmodule
