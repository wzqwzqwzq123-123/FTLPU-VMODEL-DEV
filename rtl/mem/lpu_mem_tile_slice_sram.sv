module lpu_mem_tile_slice_sram #(
	parameter integer DEPTH_ROWS = lpu_pkg::SRAM_DEPTH_ROWS,
	parameter integer LANES = 8
) (
	input logic clk_i,
	input logic rst_ni,
	input logic instruction_valid_i,
	input logic [lpu_pkg::MEM_INSTRUCTION_WIDTH-1:0] instruction_i,
	input logic [63:0] rx_valid_i,
	input logic [64*LANES*8-1:0] rx_data_i,
	output logic [63:0] rx_consume_o,
	output logic tx_valid_o,
	output logic [5:0] tx_stream_o,
	output logic [LANES*8-1:0] tx_data_o,
	output logic tx_last_o,
	output logic fault_o
);
	localparam integer WORD_WIDTH = LANES * 8;

	logic [2:0] opcode;
	logic [5:0] stream;
	logic [5:0] map_stream;
	logic [lpu_pkg::MEM_ADDRESS_WIDTH-1:0] address;
	logic preserve_stream;
	logic instruction_legal;
	logic instruction_implemented;
	logic memory_req_valid;
	logic memory_write;
	logic [lpu_pkg::MEM_ADDRESS_WIDTH-1:0] memory_address;
	logic [WORD_WIDTH-1:0] memory_write_data;
	logic [WORD_WIDTH-1:0] memory_read_data;
	logic memory_read_valid;
	logic response_is_instruction_q;
	logic [5:0] response_stream_q;

	lpu_mem_instruction_decode u_decode (
		.instruction_i,
		.opcode_o(opcode),
		.stream_o(stream),
		.map_stream_o(map_stream),
		.address_o(address),
		.preserve_stream_o(preserve_stream),
		.legal_o(instruction_legal),
		.implemented_o(instruction_implemented)
	);

	lpu_sram_1rw_banked #(
		.WIDTH(WORD_WIDTH),
		.DEPTH(DEPTH_ROWS),
		.ADDR_WIDTH(lpu_pkg::MEM_ADDRESS_WIDTH)
	) u_memory (
		.clk_i,
		.rst_ni,
		.req_valid_i(memory_req_valid),
		.write_i(memory_write),
		.address_i(memory_address),
		.write_data_i(memory_write_data),
		.write_mask_i({WORD_WIDTH{1'b1}}),
		.read_valid_o(memory_read_valid),
		.read_data_o(memory_read_data)
	);

	// The single SRAM port is owned exclusively by one legal implemented MEM
	// instruction. WriteTap writes without consuming the observed stream.
	always_comb begin
		memory_req_valid = 1'b0;
		memory_write = 1'b0;
		memory_address = address;
		memory_write_data = '0;
		rx_consume_o = '0;
		if(instruction_valid_i && instruction_legal && instruction_implemented)begin
			case(opcode)
				lpu_pkg::MEM_READ: memory_req_valid = 1'b1;
				lpu_pkg::MEM_WRITE: begin
					memory_req_valid = rx_valid_i[stream];
					memory_write = 1'b1;
					memory_write_data = rx_data_i[stream*WORD_WIDTH+:WORD_WIDTH];
					if(!preserve_stream)begin
						rx_consume_o[stream] = rx_valid_i[stream];
					end
				end
				default: memory_req_valid = 1'b0;
			endcase
		end
	end

	assign tx_valid_o = memory_read_valid && response_is_instruction_q;
	assign tx_stream_o = response_stream_q;
	assign tx_data_o = memory_read_data;
	assign tx_last_o = tx_valid_o;

	always_ff @(posedge clk_i or negedge rst_ni) begin
		if(!rst_ni)begin
			response_is_instruction_q <= 1'b0;
			response_stream_q <= '0;
			fault_o <= 1'b0;
		end
		else begin
			response_is_instruction_q <= memory_req_valid && !memory_write;
			if(memory_req_valid && !memory_write)begin
				response_stream_q <= stream;
			end
			if(instruction_valid_i &&
				(!instruction_legal || !instruction_implemented ||
				 (address >= DEPTH_ROWS) ||
				 ((opcode == lpu_pkg::MEM_WRITE) && !preserve_stream && !rx_valid_i[stream])))begin
				fault_o <= 1'b1;
			end
		end
	end
endmodule
