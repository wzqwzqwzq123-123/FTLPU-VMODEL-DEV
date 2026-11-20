// Buffers VXM Compact Config launches until their absolute Schedule deadline.
// Entries are never retried or shifted after a missed deadline.
module lpu_vxm_timed_issue_queue #(
	parameter integer DEPTH = 4
) (
	input logic clk_i,
	input logic rst_ni,
	input logic run_i,
	input logic [31:0] schedule_cycle_i,

	input logic enqueue_valid_i,
	output logic enqueue_ready_o,
	input logic [95:0] enqueue_instruction_i,
	input logic [31:0] enqueue_cycle_i,

	output logic issue_valid_o,
	input logic issue_ready_i,
	output logic [95:0] issue_instruction_o,
	output logic [31:0] issue_cycle_o,

	output logic [$clog2(DEPTH+1)-1:0] level_o,
	output logic fault_o
);
	localparam integer ENTRY_WIDTH = 128;

	logic fifo_enqueue_valid;
	logic fifo_enqueue_ready;
	logic fifo_dequeue_valid;
	logic fifo_dequeue_ready;
	logic [ENTRY_WIDTH-1:0] fifo_dequeue_data;
	logic [95:0] fifo_dequeue_instruction;
	logic [31:0] fifo_dequeue_cycle;
	logic enqueue_fire;
	logic issue_fire;
	logic enqueue_deadline_fault_w;
	logic late_fault_w;
	logic deadline_fault_w;
	logic fault_q;

	assign fifo_dequeue_instruction = fifo_dequeue_data[95:0];
	assign fifo_dequeue_cycle = fifo_dequeue_data[127:96];

	assign enqueue_ready_o = fifo_enqueue_ready && !fault_q;
	assign enqueue_fire = enqueue_valid_i && enqueue_ready_o;
	assign fifo_enqueue_valid = enqueue_valid_i && !fault_q;

	assign issue_valid_o = run_i && fifo_dequeue_valid &&
		(fifo_dequeue_cycle == schedule_cycle_i) && !fault_q;
	assign issue_instruction_o = fifo_dequeue_instruction;
	assign issue_cycle_o = fifo_dequeue_cycle;
	assign issue_fire = issue_valid_o && issue_ready_i;
	assign fifo_dequeue_ready = issue_fire;

	// A launch must be buffered before its deadline. Deadline backpressure is a
	// static-schedule fault and must not turn into a delayed retry.
	assign enqueue_deadline_fault_w = enqueue_fire && run_i &&
		(enqueue_cycle_i <= schedule_cycle_i);
	assign late_fault_w = run_i && fifo_dequeue_valid &&
		(fifo_dequeue_cycle < schedule_cycle_i);
	assign deadline_fault_w = run_i && fifo_dequeue_valid &&
		(fifo_dequeue_cycle == schedule_cycle_i) && !issue_ready_i;
	assign fault_o = fault_q || enqueue_deadline_fault_w || late_fault_w ||
		deadline_fault_w;

	lpu_fifo #(
		.DATA_WIDTH(ENTRY_WIDTH),
		.DEPTH(DEPTH)
	) u_fifo (
		.clk_i,
		.rst_ni,
		.enqueue_valid_i(fifo_enqueue_valid),
		.enqueue_ready_o(fifo_enqueue_ready),
		.enqueue_data_i({enqueue_cycle_i, enqueue_instruction_i}),
		.dequeue_valid_o(fifo_dequeue_valid),
		.dequeue_ready_i(fifo_dequeue_ready),
		.dequeue_data_o(fifo_dequeue_data),
		.level_o
	);

	// Fault status is sticky so the owning VXM queue cannot silently continue
	// after losing an absolute launch point.
	always_ff @(posedge clk_i or negedge rst_ni) begin
		if(!rst_ni)begin
			fault_q <= 1'b0;
		end
		else if(!fault_q && (enqueue_deadline_fault_w || late_fault_w ||
			deadline_fault_w))begin
			fault_q <= 1'b1;
		end
	end

	initial begin
		if(DEPTH < 1)begin
			$error("VXM timed Issue Queue DEPTH must be at least one");
		end
	end
endmodule
