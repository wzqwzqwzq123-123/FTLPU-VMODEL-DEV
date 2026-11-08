module lpu_sxm_transpose_macro_frontend #(
	parameter integer WORD_FIFO_DEPTH = 4,
	parameter integer CONTEXT_FIFO_DEPTH = 2,
	parameter integer ISSUE_FIFO_DEPTH = 4
) (
	input logic clk_i,
	input logic rst_ni,
	input logic run_i,
	input logic [31:0] schedule_cycle_i,
	input  logic        descriptor_valid_i,
	output logic        descriptor_ready_o,
	input  logic [31:0] descriptor_base_cycle_i,
	input  logic        word_valid_i,
	output logic        word_ready_o,
	input  logic [95:0] word_i,
	input  logic        word_last_i,
	output logic         issue_valid_o,
	input  logic         issue_ready_i,
	output logic [415:0] issue_instruction_o,
	output logic [31:0]  issue_cycle_o,
	output logic decoder_done_o,
	output logic [$clog2(WORD_FIFO_DEPTH+1)-1:0] word_fifo_level_o,
	output logic [$clog2(CONTEXT_FIFO_DEPTH+1)-1:0] context_fifo_level_o,
	output logic [$clog2(ISSUE_FIFO_DEPTH+1)-1:0] issue_fifo_level_o,
	output logic idle_o,
	output logic fault_o,
	output logic [4:0] fault_code_o
);
	localparam integer CONTEXT_WIDTH = 608;

	logic descriptor_valid_q;
	logic [31:0] descriptor_base_cycle_q;
	logic descriptor_fire;
	logic word_fifo_enqueue_ready;
	logic word_fifo_valid;
	logic word_fifo_ready;
	logic [96:0] word_fifo_data;
	logic decoder_context_valid;
	logic decoder_context_ready;
	logic [415:0] decoder_instruction;
	logic [31:0] decoder_wait_cycle;
	logic [31:0] decoder_inner_count;
	logic [31:0] decoder_inner_interval;
	logic [31:0] decoder_outer_count;
	logic [31:0] decoder_outer_interval;
	logic decoder_fault;
	logic [3:0] decoder_fault_code;
	logic context_fifo_enqueue_ready;
	logic context_fifo_valid;
	logic context_fifo_ready;
	logic [CONTEXT_WIDTH-1:0] context_fifo_input_data;
	logic [CONTEXT_WIDTH-1:0] context_fifo_output_data;
	logic [415:0] scheduler_instruction;
	logic [31:0] scheduler_base_cycle;
	logic [31:0] scheduler_wait_cycle;
	logic [31:0] scheduler_inner_count;
	logic [31:0] scheduler_inner_interval;
	logic [31:0] scheduler_outer_count;
	logic [31:0] scheduler_outer_interval;
	logic scheduler_idle;
	logic scheduler_fault;
	logic [3:0] scheduler_fault_code;
	logic scheduler_issue_valid;
	logic scheduler_issue_ready;
	logic [415:0] scheduler_issue_instruction;
	logic [31:0] scheduler_issue_cycle;
	logic issue_queue_fault;

	assign fault_o = decoder_fault || scheduler_fault || issue_queue_fault;
	assign fault_code_o = decoder_fault ? {1'b0, decoder_fault_code} :
		scheduler_fault ? {1'b1, scheduler_fault_code} : 5'h1f;
	assign descriptor_ready_o = !descriptor_valid_q && !decoder_done_o && !fault_o;
	assign descriptor_fire = descriptor_valid_i && descriptor_ready_o;
	assign word_ready_o = descriptor_valid_q && word_fifo_enqueue_ready && !fault_o;
	assign idle_o = !descriptor_valid_q && (word_fifo_level_o == '0) &&
		(context_fifo_level_o == '0) && scheduler_idle && (issue_fifo_level_o == '0);

	// Descriptor base cycle remains paired with the single decoded RUN_2D Context.
	always_ff @(posedge clk_i or negedge rst_ni) begin
		if(!rst_ni)begin
			descriptor_valid_q <= 1'b0;
			descriptor_base_cycle_q <= '0;
		end
		else begin
			if(descriptor_fire)begin
				descriptor_valid_q <= 1'b1;
				descriptor_base_cycle_q <= descriptor_base_cycle_i;
			end
			if(decoder_done_o)begin
				descriptor_valid_q <= 1'b0;
			end
		end
	end

	lpu_queue_fifo #(
		.DATA_WIDTH(97),
		.DEPTH(WORD_FIFO_DEPTH)
	) u_word_fifo (
		.clk_i,
		.rst_ni,
		.enqueue_valid_i(word_valid_i && word_ready_o),
		.enqueue_ready_o(word_fifo_enqueue_ready),
		.enqueue_data_i({word_last_i, word_i}),
		.dequeue_valid_o(word_fifo_valid),
		.dequeue_ready_i(word_fifo_ready),
		.dequeue_data_o(word_fifo_data),
		.level_o(word_fifo_level_o)
	);

	lpu_sxm_transpose_macro_decoder u_decoder (
		.clk_i,
		.rst_ni,
		.word_valid_i(word_fifo_valid),
		.word_ready_o(word_fifo_ready),
		.word_i(word_fifo_data[95:0]),
		.word_last_i(word_fifo_data[96]),
		.context_valid_o(decoder_context_valid),
		.context_ready_i(decoder_context_ready),
		.context_instruction_o(decoder_instruction),
		.context_wait_cycle_o(decoder_wait_cycle),
		.context_inner_count_o(decoder_inner_count),
		.context_inner_interval_o(decoder_inner_interval),
		.context_outer_count_o(decoder_outer_count),
		.context_outer_interval_o(decoder_outer_interval),
		.done_o(decoder_done_o),
		.fault_o(decoder_fault),
		.fault_code_o(decoder_fault_code)
	);

	assign context_fifo_input_data = {descriptor_base_cycle_q, decoder_wait_cycle,
		decoder_inner_count, decoder_inner_interval, decoder_outer_count,
		decoder_outer_interval, decoder_instruction};
	assign {scheduler_base_cycle, scheduler_wait_cycle, scheduler_inner_count,
		scheduler_inner_interval, scheduler_outer_count, scheduler_outer_interval,
		scheduler_instruction} = context_fifo_output_data;
	assign decoder_context_ready = context_fifo_enqueue_ready && !fault_o;

	lpu_queue_fifo #(
		.DATA_WIDTH(CONTEXT_WIDTH),
		.DEPTH(CONTEXT_FIFO_DEPTH)
	) u_context_fifo (
		.clk_i,
		.rst_ni,
		.enqueue_valid_i(decoder_context_valid && !fault_o),
		.enqueue_ready_o(context_fifo_enqueue_ready),
		.enqueue_data_i(context_fifo_input_data),
		.dequeue_valid_o(context_fifo_valid),
		.dequeue_ready_i(context_fifo_ready),
		.dequeue_data_o(context_fifo_output_data),
		.level_o(context_fifo_level_o)
	);

	lpu_sxm_transpose_macro_scheduler #(
		.ISSUE_FIFO_DEPTH(ISSUE_FIFO_DEPTH),
		.ISSUE_LOOKAHEAD(2)
	) u_scheduler (
		.clk_i,
		.rst_ni,
		.run_i,
		.schedule_cycle_i,
		.context_valid_i(context_fifo_valid),
		.context_ready_o(context_fifo_ready),
		.context_instruction_i(scheduler_instruction),
		.context_base_cycle_i(scheduler_base_cycle),
		.context_wait_cycle_i(scheduler_wait_cycle),
		.context_inner_count_i(scheduler_inner_count),
		.context_inner_interval_i(scheduler_inner_interval),
		.context_outer_count_i(scheduler_outer_count),
		.context_outer_interval_i(scheduler_outer_interval),
		.issue_valid_o(scheduler_issue_valid),
		.issue_ready_i(scheduler_issue_ready),
		.issue_instruction_o(scheduler_issue_instruction),
		.issue_cycle_o(scheduler_issue_cycle),
		.issue_fifo_level_o(),
		.idle_o(scheduler_idle),
		.fault_o(scheduler_fault),
		.fault_code_o(scheduler_fault_code)
	);

	// The FU-local Timed Queue stores decoded base instructions and owns the final deadline.
	lpu_sxm_issue_queue #(
		.INSTRUCTION_WIDTH(416),
		.DEPTH(ISSUE_FIFO_DEPTH)
	) u_issue_queue (
		.clk_i,
		.rst_ni,
		.run_i,
		.schedule_cycle_i,
		.enqueue_valid_i(scheduler_issue_valid),
		.enqueue_ready_o(scheduler_issue_ready),
		.enqueue_instruction_i(scheduler_issue_instruction),
		.enqueue_cycle_i(scheduler_issue_cycle),
		.issue_valid_o,
		.issue_ready_i,
		.issue_instruction_o,
		.issue_cycle_o,
		.level_o(issue_fifo_level_o),
		.fault_o(issue_queue_fault)
	);
endmodule
