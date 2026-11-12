`timescale 1ns/1ps

module lpu_program_load_control_tb;
	import lpu_program_load_pkg::*;

	logic clk_i;
	logic rst_ni;
	logic program_valid_i;
	logic program_ready_o;
	logic [PROGRAM_LOAD_CONTROL_WIDTH-1:0] program_control_i;
	logic [PROGRAM_DESTINATION_WIDTH-1:0] program_destination_i;
	logic [16:0] program_address_i;
	logic [127:0] program_data_i;
	logic [3:0] program_strb_i;
	logic program_last_i;
	logic program_error_o;
	integer checks;

	always #5 clk_i = ~clk_i;

	task automatic check(input logic condition, input string label);
		begin
			if(!condition)begin
				$fatal(1, "FAIL %s", label);
			end
			checks = checks + 1;
		end
	endtask

	task automatic send_control(
		input logic [PROGRAM_LOAD_CONTROL_WIDTH-1:0] control,
		input logic [16:0] address,
		input logic [127:0] data,
		input logic [3:0] strb,
		input logic expected_error
	);
		begin
			@(negedge clk_i);
			program_control_i = control;
			program_address_i = address;
			program_data_i = data;
			program_strb_i = strb;
			program_valid_i = 1'b1;
			#1;
			check(program_ready_o, "Program Load control accepted");
			check(program_error_o == expected_error, "Program Load control error status");
			@(posedge clk_i);
			@(negedge clk_i);
			program_valid_i = 1'b0;
		end
	endtask

	lpu_mem_subsystem #(
		.IMEM_DEPTH(4),
		.ACTIVE_CONTEXTS(1),
		.FU_QUEUE_DEPTH(2),
		.DEPTH_ROWS(256),
		.ACTIVE_COLUMNS(1),
		.USE_SRAM_MACRO(1'b0)
	) dut (
		.clk_i,
		.rst_ni,
		.program_reset_i(1'b0),
		.local_frontend_enable_i(1'b1),
		.run_i(1'b0),
		.schedule_cycle_i('0),
		.qctl_active_i('0),
		.qctl_scheduler_enable_i('0),
		.qctl_schedule_cycle_i('0),
		.program_valid_i,
		.program_ready_o,
		.program_control_i,
		.program_destination_i,
		.program_address_i,
		.program_data_i,
		.program_strb_i,
		.program_last_i,
		.program_error_o,
		.external_issue_valid_i('0),
		.external_issue_instruction_i('0),
		.local_issue_valid_o(),
		.local_issue_instruction_o(),
		.local_issue_cycle_o(),
		.frontends_ready_o(),
		.frontends_idle_o(),
		.frontend_fault_o(),
		.frontend_fault_code_o(),
		.east_edge_valid_i('0),
		.east_edge_data_i('0),
		.east_edge_valid_o(),
		.east_edge_data_o(),
		.west_edge_valid_i('0),
		.west_edge_data_i('0),
		.west_edge_valid_o(),
		.west_edge_data_o(),
		.mem_fault_o(),
		.conflict_o()
	);

	initial begin
		clk_i = 1'b0;
		rst_ni = 1'b0;
		program_valid_i = 1'b0;
		program_control_i = PROGRAM_LOAD_WRITE;
		program_destination_i = program_destination_pack(
			PROGRAM_HEMISPHERE_EAST, PROGRAM_TARGET_MEM, 8'd0);
		program_address_i = '0;
		program_data_i = '0;
		program_strb_i = '0;
		program_last_i = 1'b0;
		checks = 0;
		repeat(2) @(posedge clk_i);
		@(negedge clk_i);
		rst_ni = 1'b1;

		send_control(PROGRAM_LOAD_WRITE, 17'd0,
			128'hffff_ffff_0123_4567_89ab_cdef_0123_4567, 4'b0111, 1'b0);
		check(dut.gen_bank_frontend[0].u_frontend.u_imem.data_mem_q[0] ==
			96'h0123_4567_89ab_cdef_0123_4567, "96-bit WRITE stores only three 32-bit segments");

		send_control(PROGRAM_LOAD_WRITE, 17'd1,
			128'h0000_0000_1111_2222_3333_4444_5555_6666, 4'b0111, 1'b0);
		check(dut.gen_bank_frontend[0].u_frontend.u_imem.data_mem_q[1] ==
			96'h1111_2222_3333_4444_5555_6666, "legal MEM write initializes comparison entry");
		send_control(PROGRAM_LOAD_WRITE, 17'd1,
			128'hffff_eeee_dddd_cccc_bbbb_aaaa_9999_8888, 4'b1111, 1'b1);
		check(dut.gen_bank_frontend[0].u_frontend.u_imem.data_mem_q[1] ==
			96'h1111_2222_3333_4444_5555_6666,
			"illegal MEM strobe does not write local iMEM");

		send_control(PROGRAM_LOAD_WRITE, 17'd2,
			128'h0000_0000_aaaa_bbbb_cccc_dddd_eeee_ffff, 4'b0111, 1'b0);
		program_last_i = 1'b1;
		send_control(PROGRAM_LOAD_WRITE, 17'd3,
			128'h0000_0000_1234_5678_9abc_def0_1357_2468, 4'b0111, 1'b0);

		send_control(PROGRAM_LOAD_PRIME, 17'd0, '0, '0, 1'b0);
		check(dut.gen_bank_frontend[0].u_frontend.u_imem.data_mem_q[0] ==
			96'h0123_4567_89ab_cdef_0123_4567, "PRIME does not write local iMEM");
		program_destination_i = program_destination_pack(
			PROGRAM_HEMISPHERE_EAST, PROGRAM_TARGET_MEM, 8'd104);
		send_control(PROGRAM_LOAD_WRITE, 17'd0, '0, 4'b0111, 1'b1);
		program_destination_i = program_destination_pack(
			PROGRAM_HEMISPHERE_EAST, PROGRAM_TARGET_MEM, 8'd0);

		$display("LPU_PROGRAM_LOAD_CONTROL PASS checks=%0d", checks);
		$finish;
	end
endmodule
