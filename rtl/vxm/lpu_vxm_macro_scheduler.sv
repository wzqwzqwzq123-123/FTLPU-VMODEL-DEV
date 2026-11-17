// Expands one VXM RUN_2D Context into repeated launches of the unchanged
// 96-bit Compact Config. One instance belongs to one logical VXM Queue.
module lpu_vxm_macro_scheduler #(
	parameter integer LOCAL_QUEUE = 0,
	parameter integer ISSUE_FIFO_DEPTH = 4,
	parameter integer ISSUE_LOOKAHEAD = 2
) (
	input logic clk_i,
	input logic rst_ni,
	input logic run_i,
	input logic [31:0] schedule_cycle_i,

	input logic context_valid_i,
	output logic context_ready_o,
	input logic [95:0] context_instruction_i,
	input logic [31:0] context_base_cycle_i,
	input logic [31:0] context_wait_cycle_i,
	input logic [31:0] context_inner_count_i,
	input logic [31:0] context_inner_interval_i,
	input logic [31:0] context_outer_count_i,
	input logic [31:0] context_outer_interval_i,

	// Each launch is the original Compact Config. The Compact repeat_count is
	// consumed later by the VXM Stage-local Current Config, not expanded here.
	output logic issue_valid_o,
	input logic issue_ready_i,
	output logic [95:0] issue_instruction_o,
	output logic [31:0] issue_cycle_o,

	output logic [$clog2(ISSUE_FIFO_DEPTH+1)-1:0] issue_fifo_level_o,
	output logic idle_o,
	output logic fault_o,
	output logic [3:0] fault_code_o
);
	localparam logic [3:0] FAULT_NONE = 4'd0;
	localparam logic [3:0] FAULT_SCHEDULE = 4'd1;
	localparam logic [3:0] FAULT_INSTRUCTION = 4'd2;
	localparam logic [3:0] FAULT_LATE = 4'd3;
	localparam logic [3:0] FAULT_MISSED = 4'd4;
	localparam logic [3:0] FAULT_TIMED_QUEUE = 4'd6;
	localparam logic [3:0] FAULT_TIMEBASE = 4'd8;
	localparam logic [3:0] FAULT_OVERFLOW = 4'd9;

	// One ingress slot decouples the Context FIFO from Context admission.
	logic ingress_valid_q;
	logic [95:0] ingress_instruction_q;
	logic [31:0] ingress_base_cycle_q;
	logic [31:0] ingress_wait_cycle_q;
	logic [31:0] ingress_inner_count_q;
	logic [31:0] ingress_inner_interval_q;
	logic [31:0] ingress_outer_count_q;
	logic [31:0] ingress_outer_interval_q;

	// RUN_2D keeps one active Context per logical VXM Queue.
	logic active_valid_q;
	logic [95:0] active_instruction_q;
	logic [31:0] active_inner_count_q;
	logic [31:0] active_inner_remaining_q;
	logic [31:0] active_outer_remaining_q;
	logic [31:0] active_inner_interval_q;
	logic [31:0] active_outer_residual_q;
	logic [31:0] active_next_cycle_q;

	logic context_fire;
	logic ingress_admit_fire;
	logic issue_fire;
	logic [63:0] inner_steps_w;
	logic [63:0] outer_steps_w;
	logic [64:0] inner_span_w;
	logic [64:0] start_cycle_sum_w;
	logic [64:0] final_cycle_w;
	logic [31:0] start_cycle_w;
	logic [31:0] effective_inner_interval_w;
	logic [31:0] outer_residual_w;
	logic schedule_invalid_w;
	logic instruction_invalid_w;
	logic ingress_late_w;
	logic [32:0] ingress_min_start_w;

	logic [63:0] control_w;
	logic [3:0] opcode_w;
	logic [3:0] lhs_kind_w;
	logic [3:0] rhs_kind_w;
	logic [1:0] chain_depth_w;
	logic [31:0] compact_repeat_count_w;

	logic [32:0] lookahead_sum_w;
	logic [31:0] lookahead_cycle_w;
	logic selected_w;
	logic missed_generation_w;
	logic timed_queue_blocked_w;
	logic run_seen_q;
	logic [31:0] previous_cycle_q;
	logic timebase_invalid_w;
	logic dynamic_fault_w;
	logic [3:0] dynamic_fault_code_w;
	logic fault_q;
	logic [3:0] fault_code_q;

	initial begin
		if((LOCAL_QUEUE < 0) || (LOCAL_QUEUE > 7))begin
			$error("LOCAL_QUEUE must identify VXM logical Queue 0..7");
		end
		if(ISSUE_FIFO_DEPTH < 1)begin
			$error("ISSUE_FIFO_DEPTH must be at least one");
		end
		if(ISSUE_LOOKAHEAD < 2)begin
			$error("ISSUE_LOOKAHEAD must cover Timed Queue write and deadline Issue stages");
		end
	end

	assign context_fire = context_valid_i && context_ready_o;
	assign issue_instruction_o = active_instruction_q;
	assign issue_cycle_o = selected_w ? lookahead_cycle_w : '0;
	assign issue_valid_o = run_i && selected_w && !missed_generation_w && !fault_q;
	assign issue_fire = issue_valid_o && issue_ready_i && !dynamic_fault_w;
	assign issue_fifo_level_o = '0;
	assign timed_queue_blocked_w = issue_valid_o && !issue_ready_i;
	assign idle_o = !ingress_valid_q && !active_valid_q;

	// Encoded wait_cycle is relative to the descriptor base. The two RUN_2D
	// intervals are launch-point strides, not delays added after each loop.
	always_comb begin
		inner_steps_w = ingress_inner_count_q == 0 ? 64'd0 :
			({32'd0, ingress_inner_count_q} - 64'd1);
		outer_steps_w = ingress_outer_count_q == 0 ? 64'd0 :
			({32'd0, ingress_outer_count_q} - 64'd1);
		effective_inner_interval_w = ingress_inner_count_q == 1 ? 32'd1 :
			ingress_inner_interval_q;
		inner_span_w = {1'b0, inner_steps_w} *
			{33'd0, effective_inner_interval_w};
		start_cycle_sum_w = {33'd0, ingress_base_cycle_q} +
			{33'd0, ingress_wait_cycle_q};
		start_cycle_w = start_cycle_sum_w[31:0];
		final_cycle_w = start_cycle_sum_w + inner_span_w +
			({1'b0, outer_steps_w} * {33'd0, ingress_outer_interval_q});
		outer_residual_w = ingress_outer_count_q == 1 ? 32'd1 :
			ingress_outer_interval_q - inner_span_w[31:0];
	end

	// Decoder already performs Stage-specific semantic validation. These checks
	// protect direct Scheduler users and ensure the Compact packet is current-v1.
	always_comb begin
		control_w = ingress_instruction_q[63:0];
		opcode_w = control_w[3:0];
		lhs_kind_w = {control_w[52], control_w[6:4]};
		rhs_kind_w = {control_w[53], control_w[9:7]};
		chain_depth_w = control_w[18:17];
		compact_repeat_count_w = control_w[50:19];
		instruction_invalid_w = (opcode_w > 9) || (lhs_kind_w > 8) ||
			(rhs_kind_w > 8) || (chain_depth_w > 2) ||
			(compact_repeat_count_w == 0) || (|control_w[63:54]);
		schedule_invalid_w = (ingress_inner_count_q == 0) ||
			(ingress_outer_count_q == 0) || (ingress_inner_interval_q == 0) ||
			(ingress_outer_interval_q == 0) ||
			((ingress_outer_count_q > 1) &&
			 ({33'd0, ingress_outer_interval_q} <= inner_span_w)) ||
			(start_cycle_sum_w[64:32] != 0) || (final_cycle_w[64:32] != 0);
		ingress_min_start_w = {1'b0, schedule_cycle_i} + ISSUE_LOOKAHEAD + 1;
		ingress_late_w = run_i && (ingress_min_start_w[32] ||
			({1'b0, start_cycle_w} < ingress_min_start_w));
	end

	// The Scheduler generates the launch early enough to enter the Timed Queue.
	always_comb begin
		lookahead_sum_w = {1'b0, schedule_cycle_i} + ISSUE_LOOKAHEAD;
		lookahead_cycle_w = lookahead_sum_w[31:0];
		selected_w = active_valid_q && (active_next_cycle_q == lookahead_cycle_w);
		missed_generation_w = active_valid_q &&
			(active_next_cycle_q < lookahead_cycle_w);
	end

	assign ingress_admit_fire = ingress_valid_q && !active_valid_q &&
		!schedule_invalid_w && !instruction_invalid_w && !ingress_late_w &&
		!fault_q && !dynamic_fault_w;
	assign timebase_invalid_w = run_i && run_seen_q &&
		((previous_cycle_q == 32'hffff_ffff) ||
		 (schedule_cycle_i != previous_cycle_q + 1'b1));

	// Absolute Schedule faults are terminal. Blocking the Timed Queue may not
	// reschedule the Compact Config or advance the Context silently.
	always_comb begin
		dynamic_fault_w = 1'b0;
		dynamic_fault_code_w = FAULT_NONE;
		if(timebase_invalid_w)begin
			dynamic_fault_w = 1'b1;
			dynamic_fault_code_w = FAULT_TIMEBASE;
		end
		else if(run_i && lookahead_sum_w[32])begin
			dynamic_fault_w = 1'b1;
			dynamic_fault_code_w = FAULT_OVERFLOW;
		end
		else if(timed_queue_blocked_w)begin
			dynamic_fault_w = 1'b1;
			dynamic_fault_code_w = FAULT_TIMED_QUEUE;
		end
		else if(run_i && missed_generation_w)begin
			dynamic_fault_w = 1'b1;
			dynamic_fault_code_w = FAULT_MISSED;
		end
		else if(ingress_valid_q && !active_valid_q && schedule_invalid_w)begin
			dynamic_fault_w = 1'b1;
			dynamic_fault_code_w = FAULT_SCHEDULE;
		end
		else if(ingress_valid_q && !active_valid_q && instruction_invalid_w)begin
			dynamic_fault_w = 1'b1;
			dynamic_fault_code_w = FAULT_INSTRUCTION;
		end
		else if(ingress_valid_q && !active_valid_q && ingress_late_w)begin
			dynamic_fault_w = 1'b1;
			dynamic_fault_code_w = FAULT_LATE;
		end
	end

	assign context_ready_o = !ingress_valid_q && !fault_q && !dynamic_fault_w;
	assign fault_o = fault_q || dynamic_fault_w;
	assign fault_code_o = fault_q ? fault_code_q : dynamic_fault_code_w;

	// Context data remains owned by the ingress slot until it becomes active.
	always_ff @(posedge clk_i or negedge rst_ni) begin
		if(!rst_ni)begin
			ingress_valid_q <= 1'b0;
		end
		else begin
			if(ingress_admit_fire)begin
				ingress_valid_q <= 1'b0;
			end
			else if(context_fire)begin
				ingress_valid_q <= 1'b1;
				ingress_instruction_q <= context_instruction_i;
				ingress_base_cycle_q <= context_base_cycle_i;
				ingress_wait_cycle_q <= context_wait_cycle_i;
				ingress_inner_count_q <= context_inner_count_i;
				ingress_inner_interval_q <= context_inner_interval_i;
				ingress_outer_count_q <= context_outer_count_i;
				ingress_outer_interval_q <= context_outer_interval_i;
			end
		end
	end

	// One accepted Timed Queue write represents one CModel launch point. The
	// 96-bit packet, including its datapath repeat_count, is never modified.
	always_ff @(posedge clk_i or negedge rst_ni) begin
		if(!rst_ni)begin
			active_valid_q <= 1'b0;
		end
		else begin
			if(issue_fire)begin
				if(active_inner_remaining_q > 1)begin
					active_inner_remaining_q <= active_inner_remaining_q - 1'b1;
					active_next_cycle_q <= active_next_cycle_q + active_inner_interval_q;
				end
				else if(active_outer_remaining_q > 1)begin
					active_inner_remaining_q <= active_inner_count_q;
					active_outer_remaining_q <= active_outer_remaining_q - 1'b1;
					active_next_cycle_q <= active_next_cycle_q + active_outer_residual_q;
				end
				else begin
					active_valid_q <= 1'b0;
				end
			end
			if(ingress_admit_fire)begin
				active_valid_q <= 1'b1;
				active_instruction_q <= ingress_instruction_q;
				active_inner_count_q <= ingress_inner_count_q;
				active_inner_remaining_q <= ingress_inner_count_q;
				active_outer_remaining_q <= ingress_outer_count_q;
				active_inner_interval_q <= effective_inner_interval_w;
				active_outer_residual_q <= outer_residual_w;
				active_next_cycle_q <= start_cycle_w;
			end
		end
	end

	// Track consecutive RUN cycles for absolute Schedule timebase validation.
	always_ff @(posedge clk_i or negedge rst_ni) begin
		if(!rst_ni)begin
			run_seen_q <= 1'b0;
			previous_cycle_q <= '0;
		end
		else if(run_i)begin
			run_seen_q <= 1'b1;
			previous_cycle_q <= schedule_cycle_i;
		end
		else begin
			run_seen_q <= 1'b0;
		end
	end

	// Retain the first timing, queue or Context validation fault until reset.
	always_ff @(posedge clk_i or negedge rst_ni) begin
		if(!rst_ni)begin
			fault_q <= 1'b0;
			fault_code_q <= FAULT_NONE;
		end
		else if(!fault_q && dynamic_fault_w)begin
			fault_q <= 1'b1;
			fault_code_q <= dynamic_fault_code_w;
		end
	end
endmodule
