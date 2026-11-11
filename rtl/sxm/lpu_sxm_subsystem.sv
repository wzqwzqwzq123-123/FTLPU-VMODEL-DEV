module lpu_sxm_subsystem (
	input logic clk_i,
	input logic rst_ni,
	input logic run_i,
	// The Program Load request reaches this Subsystem after the R6 Outer Local
	// boundary. The local-iMEM transport is not implemented yet, so Ready stays
	// low and no request is reported as accepted.
	input logic program_valid_i,
	output logic program_ready_o,
	input logic [lpu_program_load_pkg::PROGRAM_LOAD_CONTROL_WIDTH-1:0] program_control_i,
	input logic [lpu_program_load_pkg::PROGRAM_DESTINATION_WIDTH-1:0] program_destination_i,
	input logic [16:0] program_address_i,
	input logic [127:0] program_data_i,
	input logic [3:0] program_strb_i,
	input logic program_last_i,
	output logic program_error_o,
	input logic transpose_issue_valid_i,
	input logic [415:0] transpose_issue_instruction_i,
	input logic permute_issue_valid_i,
	input logic [415:0] permute_issue_instruction_i,
	input logic [4*32-1:0] east_inner_valid_i,
	input logic [4*32*64-1:0] east_inner_data_i,
	output logic [4*32-1:0] east_outer_valid_o,
	output logic [4*32*64-1:0] east_outer_data_o,
	input logic [4*32-1:0] west_outer_valid_i,
	input logic [4*32*64-1:0] west_outer_data_i,
	output logic [4*32-1:0] west_inner_valid_o,
	output logic [4*32*64-1:0] west_inner_data_o,
	output logic fault_o,
	output logic conflict_o
);
	assign program_ready_o = 1'b0;
	assign program_error_o = 1'b0;

	// Program Load integration remains blocked until the SXM local-iMEM transport is fixed.
	lpu_sxm_slice u_execution (
		.clk_i,
		.rst_ni,
		.run_i,
		.transpose_issue_valid_i,
		.transpose_issue_instruction_i,
		.permute_issue_valid_i,
		.permute_issue_instruction_i,
		.east_inner_valid_i,
		.east_inner_data_i,
		.east_outer_valid_o,
		.east_outer_data_o,
		.west_outer_valid_i,
		.west_outer_data_i,
		.west_inner_valid_o,
		.west_inner_data_o,
		.fault_o,
		.conflict_o
	);
endmodule
