module lpu_mem_tile_slice_behavior #(
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
	localparam integer TILE_WORD_WIDTH = LANES * 8;

	logic [TILE_WORD_WIDTH-1:0] sram [0:DEPTH_ROWS-1];
	logic [2:0] opcode;
	logic [5:0] stream;
	logic [5:0] map_stream;
	logic [lpu_pkg::MEM_ADDRESS_WIDTH-1:0] address;
	logic preserve_stream;
	logic instruction_legal;
	logic instruction_implemented;

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

	// Read data is combinational in the behavioral compatibility model.
	// WriteTap observes the stream without consuming passive forwarding.
	always_comb begin
		rx_consume_o = '0;
		tx_valid_o = 1'b0;
		tx_stream_o = stream;
		tx_data_o = '0;
		tx_last_o = 1'b0;

		if(instruction_valid_i && instruction_legal && instruction_implemented)begin
			if((opcode == lpu_pkg::MEM_WRITE) && !preserve_stream)begin
				rx_consume_o[stream] = rx_valid_i[stream];
			end
			if((opcode == lpu_pkg::MEM_READ) && (address < DEPTH_ROWS))begin
				tx_valid_o = 1'b1;
				tx_data_o = sram[address];
				tx_last_o = 1'b1;
			end
		end
	end

	// Gather and Scatter are legal formal opcodes but remain explicit
	// unsupported faults until the corresponding Legacy datapath exists.
	always_ff @(posedge clk_i or negedge rst_ni) begin
		if(!rst_ni)begin
			fault_o <= 1'b0;
		end
		else if(instruction_valid_i)begin
			if(!instruction_legal || !instruction_implemented || (address >= DEPTH_ROWS))begin
				fault_o <= 1'b1;
			end
			else if(opcode == lpu_pkg::MEM_WRITE)begin
				if(rx_valid_i[stream])begin
					sram[address] <= rx_data_i[stream*TILE_WORD_WIDTH+:TILE_WORD_WIDTH];
				end
				else if(!preserve_stream)begin
					fault_o <= 1'b1;
				end
			end
		end
	end
endmodule
