`timescale 1ns/1ps

module lpu_mxm_macro_schedulers_tb;
	localparam integer SCHEDULER_COUNT = 9;
	localparam integer CONFLICT_INDEX = 5;
	localparam integer DEADLINE_INDEX = 6;
	localparam integer MISSED_INDEX = 7;
	localparam integer PAUSE_INDEX = 8;

	logic clk;
	logic rst_n;
	logic run_enable [0:SCHEDULER_COUNT-1];
	logic [31:0] schedule_cycle [0:SCHEDULER_COUNT-1];
	logic context_valid [0:SCHEDULER_COUNT-1];
	logic context_ready [0:SCHEDULER_COUNT-1];
	logic [48:0] context_instruction [0:SCHEDULER_COUNT-1];
	logic [31:0] context_start [0:SCHEDULER_COUNT-1];
	logic [31:0] context_inner_count [0:SCHEDULER_COUNT-1];
	logic [31:0] context_inner_interval [0:SCHEDULER_COUNT-1];
	logic signed [31:0] context_inner_stride [0:SCHEDULER_COUNT-1];
	logic [31:0] context_outer_count [0:SCHEDULER_COUNT-1];
	logic [31:0] context_outer_interval [0:SCHEDULER_COUNT-1];
	logic signed [31:0] context_outer_stride [0:SCHEDULER_COUNT-1];
	logic [1:0] context_target [0:SCHEDULER_COUNT-1];
	logic [12:0] context_operand [0:SCHEDULER_COUNT-1];
	logic issue_valid [0:SCHEDULER_COUNT-1];
	logic issue_ready [0:SCHEDULER_COUNT-1];
	logic [48:0] issue_instruction [0:SCHEDULER_COUNT-1];
	logic [31:0] issue_cycle [0:SCHEDULER_COUNT-1];
	logic conflict [0:SCHEDULER_COUNT-1];
	logic fault [0:SCHEDULER_COUNT-1];
	logic [3:0] fault_code [0:SCHEDULER_COUNT-1];
	logic [2:0] active_count [0:SCHEDULER_COUNT-1];
	integer issue_count [0:4];
	integer fail_count;
	integer init_index;

	genvar scheduler_index;
	generate
		for(scheduler_index = 0; scheduler_index < SCHEDULER_COUNT; scheduler_index = scheduler_index + 1)begin: gen_scheduler
			localparam integer KIND = scheduler_index < 5 ? scheduler_index : lpu_mxm_isa_pkg::MXM_QUEUE_COMPUTE;
			lpu_mxm_macro_scheduler_core #(
				.QUEUE_KIND(KIND),
				.ACTIVE_CONTEXTS(4)
			) u_scheduler (
				.clk_i(clk),
				.rst_ni(rst_n),
				.run_i(run_enable[scheduler_index]),
				.schedule_cycle_i(schedule_cycle[scheduler_index]),
				.context_valid_i(context_valid[scheduler_index]),
				.context_ready_o(context_ready[scheduler_index]),
				.context_instruction_i(context_instruction[scheduler_index]),
				.context_start_cycle_i(context_start[scheduler_index]),
				.context_inner_count_i(context_inner_count[scheduler_index]),
				.context_inner_interval_i(context_inner_interval[scheduler_index]),
				.context_inner_stride_i(context_inner_stride[scheduler_index]),
				.context_outer_count_i(context_outer_count[scheduler_index]),
				.context_outer_interval_i(context_outer_interval[scheduler_index]),
				.context_outer_stride_i(context_outer_stride[scheduler_index]),
				.context_induction_target_i(context_target[scheduler_index]),
				.context_operand_i(context_operand[scheduler_index]),
				.issue_valid_o(issue_valid[scheduler_index]),
				.issue_ready_i(issue_ready[scheduler_index]),
				.issue_instruction_o(issue_instruction[scheduler_index]),
				.issue_cycle_o(issue_cycle[scheduler_index]),
				.conflict_o(conflict[scheduler_index]),
				.fault_o(fault[scheduler_index]),
				.fault_code_o(fault_code[scheduler_index]),
				.active_count_o(active_count[scheduler_index])
			);
		end
	endgenerate

	always #5 clk = ~clk;

	task automatic admit_context(
		input integer index,
		input logic [48:0] instruction,
		input logic [31:0] start_cycle,
		input logic [31:0] inner_count,
		input logic [31:0] inner_interval,
		input logic signed [31:0] inner_stride,
		input logic [12:0] operand,
		input logic [1:0] target
	);
		begin
			@(negedge clk);
			context_instruction[index] = instruction;
			context_start[index] = start_cycle;
			context_inner_count[index] = inner_count;
			context_inner_interval[index] = inner_interval;
			context_inner_stride[index] = inner_stride;
			context_outer_count[index] = 32'd1;
			context_outer_interval[index] = 32'd1;
			context_outer_stride[index] = 32'sd0;
			context_operand[index] = operand;
			context_target[index] = target;
			context_valid[index] = 1'b1;
			do @(posedge clk); while(!context_ready[index]);
			@(negedge clk);
			context_valid[index] = 1'b0;
		end
	endtask

	task automatic check_cycle(input integer cycle_value);
		integer stream_index;
		logic expected_valid;
		logic [48:0] expected_instruction;
		begin
			@(negedge clk);
			for(stream_index = 0; stream_index < 5; stream_index = stream_index + 1)begin
				schedule_cycle[stream_index] = cycle_value;
				run_enable[stream_index] = 1'b1;
			end
			#1;
			for(stream_index = 0; stream_index < 5; stream_index = stream_index + 1)begin
				expected_valid = (cycle_value == 3) || (cycle_value == 5) ||
					((stream_index == lpu_mxm_isa_pkg::MXM_QUEUE_COMPUTE) && (cycle_value == 7));
				case(stream_index)
					lpu_mxm_isa_pkg::MXM_QUEUE_LOAD: expected_instruction = cycle_value == 3 ? 49'h0 : 49'h2;
					lpu_mxm_isa_pkg::MXM_QUEUE_COMPUTE: expected_instruction = cycle_value == 3 ? 49'h3 :
						(cycle_value == 5 ? 49'h5 : 49'h7);
					lpu_mxm_isa_pkg::MXM_QUEUE_DEQUANT,
					lpu_mxm_isa_pkg::MXM_QUEUE_PARAM_LOAD: expected_instruction = cycle_value == 3 ? 49'h0 : 49'h1;
					default: expected_instruction = cycle_value == 3 ? 49'h10 : 49'h14;
				endcase
				if(issue_valid[stream_index] !== expected_valid)begin
					$display("FAIL stream %0d cycle %0d valid=%0b expected=%0b", stream_index, cycle_value,
						issue_valid[stream_index], expected_valid);
					fail_count = fail_count + 1;
				end
				if(expected_valid)begin
					issue_count[stream_index] = issue_count[stream_index] + 1;
					if(issue_cycle[stream_index] != cycle_value || issue_instruction[stream_index] != expected_instruction)begin
						$display("FAIL stream %0d cycle %0d instruction=%h expected=%h", stream_index, cycle_value,
							issue_instruction[stream_index], expected_instruction);
						fail_count = fail_count + 1;
					end
				end
			end
			@(posedge clk);
		end
	endtask

	initial begin
		clk = 1'b0;
		rst_n = 1'b0;
		fail_count = 0;
		for(init_index = 0; init_index < SCHEDULER_COUNT; init_index = init_index + 1)begin
			run_enable[init_index] = 1'b0;
			schedule_cycle[init_index] = '0;
			context_valid[init_index] = 1'b0;
			context_instruction[init_index] = '0;
			context_start[init_index] = '0;
			context_inner_count[init_index] = 32'd1;
			context_inner_interval[init_index] = 32'd1;
			context_inner_stride[init_index] = '0;
			context_outer_count[init_index] = 32'd1;
			context_outer_interval[init_index] = 32'd1;
			context_outer_stride[init_index] = '0;
			context_target[init_index] = '0;
			context_operand[init_index] = '0;
			issue_ready[init_index] = 1'b1;
		end
		for(init_index = 0; init_index < 5; init_index = init_index + 1) issue_count[init_index] = 0;
		repeat(3) @(posedge clk);
		rst_n = 1'b1;

		admit_context(lpu_mxm_isa_pkg::MXM_QUEUE_LOAD, 49'h0, 3, 2, 2, 1, 0,
			lpu_mxm_isa_pkg::MXM_INDUCTION_OPERAND0);
		admit_context(lpu_mxm_isa_pkg::MXM_QUEUE_COMPUTE, 49'h1, 3, 3, 2, 1, 1,
			lpu_mxm_isa_pkg::MXM_INDUCTION_OPERAND0);
		admit_context(lpu_mxm_isa_pkg::MXM_QUEUE_DEQUANT, 49'h0, 3, 2, 2, 1, 0,
			lpu_mxm_isa_pkg::MXM_INDUCTION_OPERAND0);
		admit_context(lpu_mxm_isa_pkg::MXM_QUEUE_PARAM_LOAD, 49'h0, 3, 2, 2, 1, 0,
			lpu_mxm_isa_pkg::MXM_INDUCTION_OPERAND0);
		admit_context(lpu_mxm_isa_pkg::MXM_QUEUE_BACKEND, 49'h0, 3, 2, 2, 1, 4,
			lpu_mxm_isa_pkg::MXM_INDUCTION_OPERAND0);

		for(init_index = 0; init_index <= 7; init_index = init_index + 1) check_cycle(init_index);
		@(negedge clk);
		for(init_index = 0; init_index < 5; init_index = init_index + 1) run_enable[init_index] = 1'b0;
		if(issue_count[0] != 2 || issue_count[1] != 3 || issue_count[2] != 2 || issue_count[3] != 2 || issue_count[4] != 2)begin
			$display("FAIL issue counts %0d %0d %0d %0d %0d", issue_count[0], issue_count[1], issue_count[2],
				issue_count[3], issue_count[4]);
			fail_count = fail_count + 1;
		end

		// A QCTL-style pause holds the local Schedule Cycle and does not create a missed deadline.
		admit_context(PAUSE_INDEX, 49'h1, 1, 2, 1, 1, 1, lpu_mxm_isa_pkg::MXM_INDUCTION_OPERAND0);
		@(negedge clk);
		run_enable[PAUSE_INDEX] = 1'b1;
		schedule_cycle[PAUSE_INDEX] = 0;
		@(posedge clk);
		repeat(2)begin
			@(negedge clk);
			run_enable[PAUSE_INDEX] = 1'b0;
			schedule_cycle[PAUSE_INDEX] = 0;
			@(posedge clk);
		end
		@(negedge clk);
		run_enable[PAUSE_INDEX] = 1'b1;
		schedule_cycle[PAUSE_INDEX] = 1;
		#1;
		if(!issue_valid[PAUSE_INDEX] || issue_instruction[PAUSE_INDEX] != 49'h3) fail_count = fail_count + 1;
		@(posedge clk);
		@(negedge clk);
		schedule_cycle[PAUSE_INDEX] = 2;
		#1;
		if(!issue_valid[PAUSE_INDEX] || issue_instruction[PAUSE_INDEX] != 49'h5) fail_count = fail_count + 1;
		@(posedge clk);
		@(negedge clk);
		run_enable[PAUSE_INDEX] = 1'b0;
		if(fault[PAUSE_INDEX]) fail_count = fail_count + 1;

		admit_context(CONFLICT_INDEX, 49'h1, 10, 1, 1, 0, 1, lpu_mxm_isa_pkg::MXM_INDUCTION_OPERAND0);
		admit_context(CONFLICT_INDEX, 49'h1, 10, 1, 1, 0, 2, lpu_mxm_isa_pkg::MXM_INDUCTION_OPERAND0);
		admit_context(DEADLINE_INDEX, 49'h1, 10, 1, 1, 0, 1, lpu_mxm_isa_pkg::MXM_INDUCTION_OPERAND0);
		admit_context(MISSED_INDEX, 49'h1, 9, 1, 1, 0, 1, lpu_mxm_isa_pkg::MXM_INDUCTION_OPERAND0);
		@(negedge clk);
		schedule_cycle[CONFLICT_INDEX] = 10;
		schedule_cycle[DEADLINE_INDEX] = 10;
		schedule_cycle[MISSED_INDEX] = 10;
		run_enable[CONFLICT_INDEX] = 1'b1;
		run_enable[DEADLINE_INDEX] = 1'b1;
		run_enable[MISSED_INDEX] = 1'b1;
		issue_ready[DEADLINE_INDEX] = 1'b0;
		#1;
		if(!conflict[CONFLICT_INDEX])begin
			$display("FAIL conflict not reported on due cycle");
			fail_count = fail_count + 1;
		end
		if(!issue_valid[DEADLINE_INDEX])begin
			$display("FAIL deadline instruction was not presented");
			fail_count = fail_count + 1;
		end
		@(posedge clk);
		#1;
		if(!fault[CONFLICT_INDEX] || fault_code[CONFLICT_INDEX] != 4'd2) fail_count = fail_count + 1;
		if(!fault[DEADLINE_INDEX] || fault_code[DEADLINE_INDEX] != 4'd4) fail_count = fail_count + 1;
		if(!fault[MISSED_INDEX] || fault_code[MISSED_INDEX] != 4'd3) fail_count = fail_count + 1;

		if(fail_count == 0) $display("MXM_MACRO_SCHEDULERS_TB PASS");
		else $fatal(1, "MXM_MACRO_SCHEDULERS_TB FAIL count=%0d", fail_count);
		$finish;
	end
endmodule
