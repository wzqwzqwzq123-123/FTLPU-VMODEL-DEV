module lpu_program_load_elastic_stage #(
	parameter integer DEPTH = 2
) (
	input logic clk_i,
	input logic rst_ni,

	input logic input_valid_i,
	output logic input_ready_o,
	input logic [2:0] input_command_i,
	input logic [127:0] input_data_i,
	input logic [15:0] input_strb_i,
	input logic [1:0] input_hemisphere_i,
	input logic [3:0] input_target_kind_i,
	input logic [7:0] input_queue_id_i,
	input logic [16:0] input_imem_address_i,
	input logic input_last_i,
	input logic [15:0] input_sequence_id_i,

	output logic output_valid_o,
	input logic output_ready_i,
	output logic [2:0] output_command_o,
	output logic [127:0] output_data_o,
	output logic [15:0] output_strb_o,
	output logic [1:0] output_hemisphere_o,
	output logic [3:0] output_target_kind_o,
	output logic [7:0] output_queue_id_o,
	output logic [16:0] output_imem_address_o,
	output logic output_last_o,
	output logic [15:0] output_sequence_id_o,

	output logic [$clog2(DEPTH+1)-1:0] level_o,
	output logic idle_o
);
	logic empty_w;
	logic full_w;

	// A two-entry FIFO breaks the long data path and absorbs one cycle of local target backpressure.
	lpu_program_word_fifo #(
		.DEPTH(DEPTH)
	) u_elastic_fifo (
		.clk_i,
		.rst_ni,
		.enqueue_valid_i(input_valid_i),
		.enqueue_ready_o(input_ready_o),
		.enqueue_command_i(input_command_i),
		.enqueue_data_i(input_data_i),
		.enqueue_strb_i(input_strb_i),
		.enqueue_hemisphere_i(input_hemisphere_i),
		.enqueue_target_kind_i(input_target_kind_i),
		.enqueue_queue_id_i(input_queue_id_i),
		.enqueue_imem_address_i(input_imem_address_i),
		.enqueue_last_i(input_last_i),
		.enqueue_sequence_id_i(input_sequence_id_i),
		.dequeue_valid_o(output_valid_o),
		.dequeue_ready_i(output_ready_i),
		.dequeue_command_o(output_command_o),
		.dequeue_data_o(output_data_o),
		.dequeue_strb_o(output_strb_o),
		.dequeue_hemisphere_o(output_hemisphere_o),
		.dequeue_target_kind_o(output_target_kind_o),
		.dequeue_queue_id_o(output_queue_id_o),
		.dequeue_imem_address_o(output_imem_address_o),
		.dequeue_last_o(output_last_o),
		.dequeue_sequence_id_o(output_sequence_id_o),
		.level_o,
		.empty_o(empty_w),
		.full_o(full_w)
	);

	assign idle_o = empty_w;
endmodule
