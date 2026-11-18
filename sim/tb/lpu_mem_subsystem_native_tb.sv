`timescale 1ns/1ps

module lpu_mem_subsystem_native_tb;
	localparam integer PROGRAM_PORT_COUNT = lpu_program_load_pkg::PROGRAM_RELAY_COUNT;
	localparam integer PROGRAM_BANKS_PER_PORT =
		lpu_program_load_pkg::PROGRAM_RELAY_BANKS_PER_STAGE;
	logic clk_i;
	logic rst_ni;
	logic program_reset_i;
	logic local_frontend_enable_i;
	logic run_i;
	logic [31:0] schedule_cycle_i;
	logic [103:0] qctl_active_i;
	logic [103:0] qctl_scheduler_counter_ce_i;
	logic [104*32-1:0] qctl_scheduler_cycle_o;
	logic [PROGRAM_PORT_COUNT-1:0] program_valid_i;
	logic [PROGRAM_PORT_COUNT-1:0] program_ready_o;
	logic [PROGRAM_PORT_COUNT*lpu_program_load_pkg::PROGRAM_LOAD_CONTROL_WIDTH-1:0]
		program_control_i;
	logic [PROGRAM_PORT_COUNT*lpu_program_load_pkg::PROGRAM_DESTINATION_WIDTH-1:0]
		program_destination_i;
	logic [PROGRAM_PORT_COUNT*17-1:0] program_imem_address_i;
	logic [PROGRAM_PORT_COUNT*128-1:0] program_data_i;
	logic [PROGRAM_PORT_COUNT*4-1:0] program_strb_i;
	logic [PROGRAM_PORT_COUNT-1:0] program_last_i;
	logic [PROGRAM_PORT_COUNT-1:0] program_error_o;
	logic [103:0] external_issue_valid_i;
	logic [103:0] external_issue_ready_o;
	logic [104*lpu_pkg::MEM_INSTRUCTION_WIDTH-1:0] external_issue_instruction_i;
	logic [103:0] local_issue_valid_o;
	logic [104*lpu_pkg::MEM_INSTRUCTION_WIDTH-1:0] local_issue_instruction_o;
	logic [104*32-1:0] local_issue_cycle_o;
	logic frontends_ready_o;
	logic frontends_idle_o;
	logic frontend_fault_o;
	logic [5:0] frontend_fault_code_o;
	logic [4*32-1:0] east_edge_valid_i;
	logic [4*32*64-1:0] east_edge_data_i;
	logic [4*32-1:0] east_edge_valid_o;
	logic [4*32*64-1:0] east_edge_data_o;
	logic [4*32-1:0] west_edge_valid_i;
	logic [4*32*64-1:0] west_edge_data_i;
	logic [4*32-1:0] west_edge_valid_o;
	logic [4*32*64-1:0] west_edge_data_o;
	logic [103:0] mem_fault_o;
	logic conflict_o;
	integer errors;

	lpu_mem_subsystem #(
		.IMEM_DEPTH(4), .ACTIVE_CONTEXTS(1),
		.DEPTH_ROWS(16), .ACTIVE_COLUMNS(1), .USE_NATIVE_MEM(1'b1)
	) dut (.*);

	always #5 clk_i = ~clk_i;

	function automatic logic [63:0] mem_read(
		input logic [12:0] row,
		input logic [5:0] stream
	);
		mem_read = '0;
		mem_read[2:0] = lpu_pkg::MEM_READ;
		mem_read[8:3] = stream;
		mem_read[27:15] = row;
	endfunction

	task automatic check(input logic condition, input string message);
		begin
			if(!condition)begin
				$display("ERROR %s", message);
				errors = errors + 1;
			end
		end
	endtask

	task automatic load_word(
		input logic [7:0] queue_id,
		input logic [95:0] word
	);
		integer port_index;
		begin
			port_index = queue_id / PROGRAM_BANKS_PER_PORT;
			@(negedge clk_i);
			program_valid_i[port_index] = 1'b1;
			program_control_i[port_index*lpu_program_load_pkg::PROGRAM_LOAD_CONTROL_WIDTH+:
				lpu_program_load_pkg::PROGRAM_LOAD_CONTROL_WIDTH] =
				lpu_program_load_pkg::PROGRAM_LOAD_WRITE;
			program_destination_i[
				port_index*lpu_program_load_pkg::PROGRAM_DESTINATION_WIDTH+:
				lpu_program_load_pkg::PROGRAM_DESTINATION_WIDTH] =
				lpu_program_load_pkg::program_destination_pack(
				lpu_program_load_pkg::PROGRAM_HEMISPHERE_EAST,
				lpu_program_load_pkg::PROGRAM_TARGET_MEM, queue_id);
			program_imem_address_i[port_index*17+:17] = '0;
			program_data_i[port_index*128+:128] = {32'd0, word};
			program_strb_i[port_index*4+:4] = 4'b0111;
			program_last_i[port_index] = 1'b1;
			#1;
			check(program_ready_o[port_index], "selected Bank load ready");
			@(posedge clk_i);
			@(negedge clk_i);
			program_valid_i[port_index] = 1'b0;
		end
	endtask

	initial begin
		clk_i = 1'b0;
		rst_ni = 1'b0;
		program_reset_i = 1'b0;
		local_frontend_enable_i = 1'b0;
		run_i = 1'b0;
		schedule_cycle_i = '0;
		qctl_active_i = '0;
		qctl_scheduler_counter_ce_i = '0;
		program_valid_i = 1'b0;
		program_control_i = '0;
		program_destination_i = '0;
		program_destination_i[0+:lpu_program_load_pkg::PROGRAM_DESTINATION_WIDTH] =
			lpu_program_load_pkg::program_destination_pack(
			lpu_program_load_pkg::PROGRAM_HEMISPHERE_EAST,
			lpu_program_load_pkg::PROGRAM_TARGET_MEM, 8'd0);
		program_imem_address_i = '0;
		program_data_i = '0;
		program_strb_i = '0;
		program_last_i = '0;
		external_issue_valid_i = '0;
		external_issue_instruction_i = '0;
		east_edge_valid_i = '0;
		east_edge_data_i = '0;
		west_edge_valid_i = '0;
		west_edge_data_i = '0;
		errors = 0;
		repeat(2) @(posedge clk_i);
		rst_ni = 1'b1;

		load_word(8'd0, 96'h0000_0000_0000_0000_0000_00a1);
		load_word(8'd1, 96'h0000_0000_0000_0000_0000_00b2);
		#1;
		check(dut.gen_bank_frontend[0].u_frontend.u_imem.data_mem_q[0] ==
			96'h0000_0000_0000_0000_0000_00a1, "Slice0 Bank0 owns independent iMEM");
		check(dut.gen_bank_frontend[1].u_frontend.u_imem.data_mem_q[0] ==
			96'h0000_0000_0000_0000_0000_00b2, "Slice0 Bank1 owns independent iMEM");
		$display("MEM_BANK_FRONTEND_INDEPENDENT PASS");

		@(negedge clk_i);
		program_valid_i[PROGRAM_PORT_COUNT-1] = 1'b1;
		program_control_i[(PROGRAM_PORT_COUNT-1)*lpu_program_load_pkg::PROGRAM_LOAD_CONTROL_WIDTH+:
			lpu_program_load_pkg::PROGRAM_LOAD_CONTROL_WIDTH] =
			lpu_program_load_pkg::PROGRAM_LOAD_WRITE;
		program_destination_i[
			(PROGRAM_PORT_COUNT-1)*lpu_program_load_pkg::PROGRAM_DESTINATION_WIDTH+:
			lpu_program_load_pkg::PROGRAM_DESTINATION_WIDTH] =
			lpu_program_load_pkg::program_destination_pack(
			lpu_program_load_pkg::PROGRAM_HEMISPHERE_EAST,
			lpu_program_load_pkg::PROGRAM_TARGET_MEM, 8'd104);
		program_strb_i[(PROGRAM_PORT_COUNT-1)*4+:4] = 4'b0111;
		#1;
		check(program_ready_o[PROGRAM_PORT_COUNT-1] &&
			program_error_o[PROGRAM_PORT_COUNT-1], "Queue ID 104 explicit route error");
		program_valid_i[PROGRAM_PORT_COUNT-1] = 1'b0;
		$display("MEM_BANK_ROUTE_FAULT PASS");

		local_frontend_enable_i = 1'b1;
		run_i = 1'b1;
		qctl_active_i[0] = 1'b1;
		qctl_active_i[1] = 1'b1;
		qctl_scheduler_counter_ce_i[0] = 1'b0;
		qctl_scheduler_counter_ce_i[1] = 1'b1;
		#1;
		check(!dut.gen_bank_frontend[0].frontend_run &&
			dut.gen_bank_frontend[1].frontend_run, "QCTL controls adjacent Banks independently");
		$display("MEM_BANK_QCTL_INDEPENDENT PASS");

		local_frontend_enable_i = 1'b0;
		@(negedge clk_i);
		external_issue_valid_i[0] = 1'b1;
		external_issue_valid_i[1] = 1'b1;
		external_issue_instruction_i[0*lpu_pkg::MEM_INSTRUCTION_WIDTH+:
			lpu_pkg::MEM_INSTRUCTION_WIDTH] = mem_read(13'd3, 6'd1);
		external_issue_instruction_i[1*lpu_pkg::MEM_INSTRUCTION_WIDTH+:
			lpu_pkg::MEM_INSTRUCTION_WIDTH] = mem_read(13'd5, 6'd2);
		#1;
		check(external_issue_ready_o[0] && external_issue_ready_o[1],
			"same-Slice dual Bank issue ready");
		check(dut.gen_native_execution.native_issue_valid[0] &&
			dut.gen_native_execution.native_issue_valid[1],
			"same-Slice dual Bank Native issue valid");
		check(dut.gen_native_execution.native_command[0*32+15+:13] == 13'd3 &&
			dut.gen_native_execution.native_command[1*32+15+:13] == 13'd5,
			"same-Slice dual Bank commands remain independent");
		@(posedge clk_i);
		@(negedge clk_i);
		external_issue_valid_i = '0;
		check(mem_fault_o == '0, "legal dual Bank issue has no fault");
		$display("MEM_NATIVE_DUAL_BANK_ISSUE PASS");

		if(errors == 0)begin
			$display("LPU_MEM_SUBSYSTEM_NATIVE TEST_PASS");
		end
		else begin
			$display("LPU_MEM_SUBSYSTEM_NATIVE TEST_FAIL errors=%0d", errors);
		end
		$finish;
	end
endmodule
