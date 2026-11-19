// FU-local QCTL endpoint. The wrapper is instantiated inside an FU Subsystem;
// storage and semantic control remain separate Cache and Controller modules.
module lpu_qctl_endpoint #(
	parameter integer QUEUE_ENTRY_LIMIT = 16,
	parameter integer CACHE_DEPTH = 4,
	parameter integer GENERATION_WIDTH = 64,
	parameter integer ENTRY_INDEX_WIDTH = QUEUE_ENTRY_LIMIT <= 1 ? 1 : $clog2(QUEUE_ENTRY_LIMIT),
	parameter integer ENTRY_COUNT_WIDTH = $clog2(QUEUE_ENTRY_LIMIT + 1)
) (
	input logic clk_i,
	input logic rst_ni,
	input logic clear_i,
	input logic run_i,
	input logic configure_valid_i,
	input logic [ENTRY_COUNT_WIDTH-1:0] configure_count_i,
	input logic [GENERATION_WIDTH-1:0] configure_generation_i,
	output logic pool_request_valid_o,
	input logic pool_request_ready_i,
	output logic [ENTRY_INDEX_WIDTH-1:0] pool_request_index_o,
	output logic [GENERATION_WIDTH-1:0] pool_request_generation_o,
	input logic pool_response_valid_i,
	input logic [lpu_qctl_pkg::QCTL_RECORD_WIDTH-1:0] pool_response_data_i,
	input logic pool_response_error_i,
	input logic [lpu_qctl_pkg::QCTL_CYCLE_WIDTH-1:0] scheduler_cycle_i,
	output logic scheduler_counter_ce_o,
	input logic event_valid_i,
	input logic [lpu_qctl_pkg::QCTL_OPERAND_WIDTH-1:0] event_tag_i,
	output logic event_wait_o,
	output logic event_consume_o,
	output logic sync_arrive_valid_o,
	input logic sync_release_valid_i,
	output logic notify_valid_o,
	input logic notify_ready_i,
	output logic mem_packet_valid_o,
	output logic [lpu_qctl_pkg::QCTL_OPERAND_WIDTH-1:0] mem_packet_ordinal_o,
	input logic mem_packet_retired_i,
	output logic configured_o,
	output logic primed_o,
	output logic done_o,
	output logic fault_o,
	output logic [3:0] fault_code_o
);
	logic head_valid;
	logic [lpu_qctl_pkg::QCTL_RECORD_WIDTH-1:0] head_record;
	logic head_retire;
	logic cache_fault;
	logic [3:0] cache_fault_code;
	logic controller_fault;
	logic [3:0] controller_fault_code;

	assign fault_o = cache_fault || controller_fault;
	assign fault_code_o = cache_fault ? cache_fault_code : controller_fault_code;

	lpu_qctl_cache #(
		.QUEUE_ENTRY_LIMIT(QUEUE_ENTRY_LIMIT),
		.CACHE_DEPTH(CACHE_DEPTH),
		.GENERATION_WIDTH(GENERATION_WIDTH)
	) u_cache (
		.clk_i, .rst_ni, .clear_i,
		.configure_valid_i, .configure_count_i, .configure_generation_i,
		.pool_request_valid_o, .pool_request_ready_i,
		.pool_request_index_o, .pool_request_generation_o,
		.pool_response_valid_i, .pool_response_data_i, .pool_response_error_i,
		.head_valid_o(head_valid), .head_record_o(head_record), .head_retire_i(head_retire),
		.configured_o, .primed_o, .done_o,
		.fault_o(cache_fault), .fault_code_o(cache_fault_code)
	);

	lpu_qctl_controller u_controller (
		.clk_i, .rst_ni, .clear_i, .configure_valid_i, .run_i,
		.configured_i(configured_o), .primed_i(primed_o), .done_i(done_o),
		.scheduler_cycle_i, .scheduler_counter_ce_o,
		.head_valid_i(head_valid), .head_record_i(head_record), .head_retire_o(head_retire),
		.sync_arrive_valid_o, .sync_release_valid_i,
		.notify_valid_o, .notify_ready_i,
		.event_valid_i, .event_tag_i, .event_wait_o, .event_consume_o,
		.mem_packet_valid_o, .mem_packet_ordinal_o, .mem_packet_retired_i,
		.fault_o(controller_fault), .fault_code_o(controller_fault_code)
	);
endmodule
