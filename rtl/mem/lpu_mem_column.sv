module lpu_mem_column #(
	parameter integer DEPTH_ROWS = 65536,
	parameter bit USE_SRAM_MACRO = 1'b0
) (
	input logic clk_i,
	input logic rst_ni,
	input logic [1:0] issue_valid_i,
	input logic [2*47-1:0] issue_instruction_i,

	input logic [4*64-1:0] tile_rx_valid_i,
	input logic [4*64*64-1:0] tile_rx_data_i,
	output logic [2*4*64-1:0] tile_rx_consume_o,
	output logic [2*4-1:0] tile_tx_valid_o,
	output logic [2*4*6-1:0] tile_tx_stream_o,
	output logic [2*4*64-1:0] tile_tx_data_o,
	output logic [2*4-1:0] tile_tx_last_o,
	output logic [2*4-1:0] tile_fault_o,

	input logic host_write_valid_i,
	input logic host_bank_i,
	input logic [1:0] host_tile_i,
	input logic [15:0] host_address_i,
	input logic [63:0] host_write_data_i,
	output logic [63:0] host_read_data_o
);
	logic [2*4-1:0] instruction_valid;
	logic [2*4*47-1:0] instruction_payload;
	logic [2*4*64-1:0] host_read_data;
	logic host_bank_select;

	// Unconnected legacy top-level instances retain the historical Bank0 host view.
	always_comb begin
		host_bank_select = 1'b0;
		if(host_bank_i)begin
			host_bank_select = 1'b1;
		end
	end

	generate
		for(genvar bank_control_gen = 0; bank_control_gen < 2; bank_control_gen++) begin : gen_bank_control
			localparam integer BANK_INDEX = bank_control_gen;
			lpu_control_pipeline #(.WIDTH(47), .ROWS(4)) u_control (
				.clk_i, .rst_ni,
				.issue_valid_i(issue_valid_i[BANK_INDEX]),
				.issue_payload_i(issue_instruction_i[BANK_INDEX*47+:47]),
				.row_valid_o(instruction_valid[BANK_INDEX*4+:4]),
				.row_payload_o(instruction_payload[BANK_INDEX*4*47+:4*47])
			);
		end
	endgenerate

	generate
		for(genvar bank_gen = 0; bank_gen < 2; bank_gen++) begin : gen_bank
		for(genvar tile_gen = 0; tile_gen < 4; tile_gen++) begin : gen_tile
			localparam integer BANK_INDEX = bank_gen;
			localparam integer TILE_INDEX = tile_gen;
			localparam integer ENTRY_INDEX = BANK_INDEX*4 + TILE_INDEX;
			logic [63:0] rx_consume;
			logic tx_valid;
			logic [5:0] tx_stream;
			logic [63:0] tx_data;
			logic tx_last;
			logic fault;
			logic [63:0] host_read;

			lpu_mem_tile_slice #(
				.DEPTH_ROWS(DEPTH_ROWS),
				.USE_SRAM_MACRO(USE_SRAM_MACRO)
			) u_tile (
				.clk_i,
				.rst_ni,
				.instruction_valid_i(instruction_valid[ENTRY_INDEX]),
				.instruction_i(instruction_payload[ENTRY_INDEX*47+:47]),
				.rx_valid_i(tile_rx_valid_i[TILE_INDEX*64+:64]),
				.rx_data_i(tile_rx_data_i[TILE_INDEX*64*64+:64*64]),
				.rx_consume_o(rx_consume),
				.tx_valid_o(tx_valid),
				.tx_stream_o(tx_stream),
				.tx_data_o(tx_data),
				.tx_last_o(tx_last),
				.fault_o(fault),
				.host_write_valid_i(host_write_valid_i && (host_bank_select == BANK_INDEX) &&
					(host_tile_i == TILE_INDEX)),
				.host_address_i,
				.host_write_data_i,
				.host_read_data_o(host_read)
			);

			assign tile_rx_consume_o[ENTRY_INDEX*64+:64] = rx_consume;
			assign tile_tx_valid_o[ENTRY_INDEX] = tx_valid;
			assign tile_tx_stream_o[ENTRY_INDEX*6+:6] = tx_stream;
			assign tile_tx_data_o[ENTRY_INDEX*64+:64] = tx_data;
			assign tile_tx_last_o[ENTRY_INDEX] = tx_last;
			assign tile_fault_o[ENTRY_INDEX] = fault;
			assign host_read_data[ENTRY_INDEX*64+:64] = host_read;
		end
		end
	endgenerate

	always_comb host_read_data_o = host_read_data[(host_bank_select*4+host_tile_i)*64+:64];
endmodule
