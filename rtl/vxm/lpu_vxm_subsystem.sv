module lpu_vxm_subsystem (
	input logic clk_i,
	input logic rst_ni,
	input logic run_i,
	// VXM is a central target reached directly from the Distributor. The
	// resident-config/Execute Program endpoint is not implemented yet, so the
	// request remains visible at this boundary without being acknowledged.
	input logic program_valid_i,
	output logic program_ready_o,
	input logic [lpu_program_load_pkg::PROGRAM_LOAD_CONTROL_WIDTH-1:0] program_control_i,
	input logic [lpu_program_load_pkg::PROGRAM_DESTINATION_WIDTH-1:0] program_destination_i,
	input logic [16:0] program_address_i,
	input logic [127:0] program_data_i,
	input logic [3:0] program_strb_i,
	input logic program_last_i,
	output logic program_error_o,
	input logic [7:0] local_issue_valid_i,
	input logic [8*lpu_pkg::VXM_LOCAL_MAX_INSTRUCTION_WIDTH-1:0] local_issue_instruction_i,
	input logic global_issue_valid_i,
	input logic [lpu_pkg::VXM_GLOBAL_CONFIG_WIDTH-1:0] global_issue_instruction_i,
	input logic [2*4*32-1:0] west_from_mem_valid_i,
	input logic [2*4*32*64-1:0] west_from_mem_data_i,
	input logic [2*4*32-1:0] external_east_valid_i,
	input logic [2*4*32*64-1:0] external_east_data_i,
	output logic [2*4*32-1:0] east_to_mem_valid_o,
	output logic [2*4*32*64-1:0] east_to_mem_data_o,
	output logic fault_o,
	output logic conflict_o
);
	assign program_ready_o = 1'b0;
	assign program_error_o = 1'b0;

	// Program Load integration remains blocked until the resident-config/Execute adapter is fixed.
	lpu_vxm_slice u_execution (
		.clk_i,
		.rst_ni,
		.run_i,
		.local_issue_valid_i,
		.local_issue_instruction_i,
		.global_issue_valid_i,
		.global_issue_instruction_i,
		.lut_config_valid_i(1'b0),
		.lut_config_bank_i('0),
		.lut_config_input_min_i('0),
		.lut_config_segment_width_i('0),
		.lut_write_valid_i(1'b0),
		.lut_write_bank_i('0),
		.lut_write_address_i('0),
		.lut_write_k_i('0),
		.lut_write_b_i('0),
		.lut_write_log_i('0),
		.west_from_mem_valid_i,
		.west_from_mem_data_i,
		.external_east_valid_i,
		.external_east_data_i,
		.east_to_mem_valid_o,
		.east_to_mem_data_o,
		.fault_o,
		.conflict_o
	);
endmodule
