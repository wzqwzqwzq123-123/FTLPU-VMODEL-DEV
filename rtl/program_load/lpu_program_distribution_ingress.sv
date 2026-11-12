// Program Distribution ingress gives deferred PRIME records priority over
// Program Words, then applies the existing East/West distributor and its
// internal elastic stage. It does not own the physical Relay network.
module lpu_program_distribution_ingress (
	input logic clk_i,
	input logic rst_ni,
	input logic clear_i,

	input logic word_valid_i,
	output logic word_ready_o,
	input logic [127:0] word_data_i,
	input logic [3:0] word_strb_i,
	input logic [1:0] word_scope_i,
	input logic [11:0] word_destination_i,
	input logic [16:0] word_imem_address_i,
	input logic word_last_i,

	input logic prime_valid_i,
	output logic prime_ready_o,
	input logic [1:0] prime_scope_i,
	input logic [11:0] prime_destination_i,

	output logic west_valid_o,
	input logic west_ready_i,
	output logic [lpu_program_load_pkg::PROGRAM_LOAD_CONTROL_WIDTH-1:0] west_control_o,
	output logic [127:0] west_data_o,
	output logic [3:0] west_strb_o,
	output logic [11:0] west_destination_o,
	output logic [16:0] west_imem_address_o,
	output logic west_last_o,

	output logic east_valid_o,
	input logic east_ready_i,
	output logic [lpu_program_load_pkg::PROGRAM_LOAD_CONTROL_WIDTH-1:0] east_control_o,
	output logic [127:0] east_data_o,
	output logic [3:0] east_strb_o,
	output logic [11:0] east_destination_o,
	output logic [16:0] east_imem_address_o,
	output logic east_last_o,

	output logic idle_o,
	output logic fault_o,
	output logic [5:0] fault_code_o
);
	import lpu_program_load_pkg::*;

	logic internal_rst_ni;
	logic input_valid;
	logic input_ready;
	logic [PROGRAM_LOAD_CONTROL_WIDTH-1:0] input_control;
	logic [127:0] input_data;
	logic [3:0] input_strb;
	logic [1:0] input_scope;
	logic [11:0] input_destination;
	logic [16:0] input_imem_address;
	logic input_last;

	assign internal_rst_ni = rst_ni && !clear_i;
	assign input_valid = prime_valid_i ? prime_valid_i : word_valid_i;
	assign input_control = prime_valid_i ? PROGRAM_LOAD_PRIME : PROGRAM_LOAD_WRITE;
	assign input_data = prime_valid_i ? '0 : word_data_i;
	assign input_strb = prime_valid_i ? '0 : word_strb_i;
	assign input_scope = prime_valid_i ? prime_scope_i : word_scope_i;
	assign input_destination = prime_valid_i ? prime_destination_i : word_destination_i;
	assign input_imem_address = prime_valid_i ? '0 : word_imem_address_i;
	assign input_last = prime_valid_i ? 1'b1 : word_last_i;
	assign prime_ready_o = prime_valid_i && input_ready;
	assign word_ready_o = !prime_valid_i && input_ready;

	lpu_program_load_distributor u_distributor (
		.clk_i,
		.rst_ni(internal_rst_ni),
		.input_valid_i(input_valid),
		.input_ready_o(input_ready),
		.input_control_i(input_control),
		.input_data_i(input_data),
		.input_strb_i(input_strb),
		.input_scope_i(input_scope),
		.input_destination_i(input_destination),
		.input_imem_address_i(input_imem_address),
		.input_last_i(input_last),
		.west_valid_o,
		.west_ready_i,
		.west_control_o,
		.west_data_o,
		.west_strb_o,
		.west_destination_o,
		.west_imem_address_o,
		.west_last_o,
		.east_valid_o,
		.east_ready_i,
		.east_control_o,
		.east_data_o,
		.east_strb_o,
		.east_destination_o,
		.east_imem_address_o,
		.east_last_o,
		.idle_o,
		.fault_o,
		.fault_code_o
	);
endmodule
