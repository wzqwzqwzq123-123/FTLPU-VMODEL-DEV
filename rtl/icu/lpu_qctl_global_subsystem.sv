module lpu_qctl_global_subsystem #(
	parameter integer POOL_DEPTH = 512,
	parameter integer QUEUE_COUNT = 220,
	parameter integer QUEUE_ENTRY_LIMIT = 16,
	parameter integer EVENT_DEPTH = 8,
	parameter integer READ_LATENCY = 2,
	parameter integer GENERATION_WIDTH = 64,
	parameter integer POOL_ADDRESS_WIDTH = POOL_DEPTH <= 1 ? 1 : $clog2(POOL_DEPTH),
	parameter integer QUEUE_ID_WIDTH = QUEUE_COUNT <= 1 ? 1 : $clog2(QUEUE_COUNT),
	parameter integer ENTRY_INDEX_WIDTH = QUEUE_ENTRY_LIMIT <= 1 ? 1 : $clog2(QUEUE_ENTRY_LIMIT),
	parameter integer ENTRY_COUNT_WIDTH = $clog2(QUEUE_ENTRY_LIMIT + 1)
) (
	input logic clk_i,
	input logic rst_ni,
	input logic clear_i,
	input logic load_mode_i,
	input logic partition_valid_i,
	output logic partition_ready_o,
	input logic [QUEUE_ID_WIDTH-1:0] partition_queue_i,
	input logic [POOL_ADDRESS_WIDTH-1:0] partition_base_i,
	input logic [ENTRY_COUNT_WIDTH-1:0] partition_count_i,
	input logic [GENERATION_WIDTH-1:0] partition_generation_i,
	input logic load_valid_i,
	output logic load_ready_o,
	input logic [POOL_ADDRESS_WIDTH-1:0] load_address_i,
	input logic [lpu_qctl_pkg::QCTL_RECORD_WIDTH-1:0] load_data_i,

	output logic [QUEUE_COUNT-1:0] endpoint_configure_valid_o,
	output logic [QUEUE_COUNT*ENTRY_COUNT_WIDTH-1:0] endpoint_configure_count_o,
	output logic [QUEUE_COUNT*GENERATION_WIDTH-1:0] endpoint_configure_generation_o,
	input logic [QUEUE_COUNT-1:0] endpoint_pool_request_valid_i,
	output logic [QUEUE_COUNT-1:0] endpoint_pool_request_ready_o,
	input logic [QUEUE_COUNT*ENTRY_INDEX_WIDTH-1:0] endpoint_pool_request_index_i,
	input logic [QUEUE_COUNT*GENERATION_WIDTH-1:0] endpoint_pool_request_generation_i,
	output logic [QUEUE_COUNT-1:0] endpoint_pool_response_valid_o,
	output logic [lpu_qctl_pkg::QCTL_RECORD_WIDTH-1:0] endpoint_pool_response_data_o,
	output logic endpoint_pool_response_error_o,

	input logic event_in_valid_i,
	output logic event_in_ready_o,
	input logic [lpu_qctl_pkg::QCTL_OPERAND_WIDTH-1:0] event_in_tag_i,
	input logic [QUEUE_COUNT-1:0] event_in_target_mask_i,
	output logic event_backpressure_o,
	input logic [QUEUE_COUNT-1:0] endpoint_event_wait_i,
	input logic [QUEUE_COUNT-1:0] endpoint_event_consume_i,
	output logic [QUEUE_COUNT-1:0] endpoint_event_valid_o,
	output logic [lpu_qctl_pkg::QCTL_OPERAND_WIDTH-1:0] endpoint_event_tag_o,

	input logic [QUEUE_COUNT-1:0] sync_participant_mask_i,
	input logic [QUEUE_COUNT-1:0] endpoint_sync_arrive_valid_i,
	input logic [QUEUE_COUNT-1:0] endpoint_notify_valid_i,
	output logic [QUEUE_COUNT-1:0] endpoint_notify_ready_o,
	output logic [QUEUE_COUNT-1:0] endpoint_sync_release_valid_o,
	input logic [QUEUE_COUNT-1:0] endpoint_mem_packet_valid_i,
	input logic [QUEUE_COUNT*lpu_qctl_pkg::QCTL_OPERAND_WIDTH-1:0] endpoint_mem_packet_ordinal_i,
	output logic [QUEUE_COUNT-1:0] mem_packet_valid_o,
	output logic [QUEUE_COUNT*lpu_qctl_pkg::QCTL_OPERAND_WIDTH-1:0] mem_packet_ordinal_o,
	input logic [QUEUE_COUNT-1:0] mem_packet_retired_i,
	output logic [QUEUE_COUNT-1:0] endpoint_mem_packet_retired_o,

	input logic [QUEUE_COUNT-1:0] endpoint_configured_i,
	input logic [QUEUE_COUNT-1:0] endpoint_primed_i,
	input logic [QUEUE_COUNT-1:0] endpoint_done_i,
	input logic [QUEUE_COUNT-1:0] endpoint_fault_i,
	input logic [QUEUE_COUNT*4-1:0] endpoint_fault_code_i,
	output logic [QUEUE_COUNT-1:0] queue_active_o,
	output logic all_primed_o,
	output logic all_done_o,
	output logic fault_o,
	output logic [7:0] fault_code_o
);
	logic partition_fire_w;
	logic partition_basic_valid_w;
	logic [QUEUE_COUNT-1:0] pool_request_valid;
	logic [QUEUE_COUNT-1:0] pool_request_ready;
	logic [QUEUE_COUNT*ENTRY_INDEX_WIDTH-1:0] pool_request_index;
	logic [QUEUE_COUNT*GENERATION_WIDTH-1:0] pool_request_generation;
	logic pool_response_valid;
	logic [QUEUE_ID_WIDTH-1:0] pool_response_queue;
	logic [lpu_qctl_pkg::QCTL_RECORD_WIDTH-1:0] pool_response_data;
	logic pool_response_error;
	logic pool_fault;
	logic [3:0] pool_fault_code;
	logic [QUEUE_COUNT-1:0] event_wait;
	logic [QUEUE_COUNT-1:0] event_consume;
	logic [QUEUE_COUNT-1:0] event_buffer_valid;
	logic [lpu_qctl_pkg::QCTL_OPERAND_WIDTH-1:0] event_buffer_tag;
	logic event_fault;
	logic [3:0] event_fault_code;
	logic fabric_fault;
	logic [3:0] fabric_fault_code;
	logic local_fault_found_w;
	logic [3:0] first_local_fault_code_w;

	assign partition_fire_w = partition_valid_i && partition_ready_o;
	assign partition_basic_valid_w = (partition_queue_i < QUEUE_COUNT) &&
		(partition_count_i <= QUEUE_ENTRY_LIMIT) && (partition_generation_i != 0) &&
		(({1'b0, partition_base_i} + partition_count_i) <= POOL_DEPTH);
	assign queue_active_o = endpoint_configured_i;
	assign all_primed_o = &(endpoint_primed_i | ~endpoint_configured_i);
	assign all_done_o = &(endpoint_done_i | ~endpoint_configured_i);
	assign fault_o = pool_fault || event_fault || fabric_fault || (|endpoint_fault_i);
	assign fault_code_o = pool_fault ? {4'h0, pool_fault_code} :
		(event_fault ? {4'h2, event_fault_code} :
		(fabric_fault ? {4'h3, fabric_fault_code} :
		(local_fault_found_w ? {4'h1, first_local_fault_code_w} : 8'h00)));

	// A legal accepted partition configures exactly one FU-local QCTL Cache.
	always_comb begin
		endpoint_configure_valid_o = '0;
		endpoint_configure_count_o = '0;
		endpoint_configure_generation_o = '0;
		if(partition_fire_w && partition_basic_valid_w)begin
			endpoint_configure_valid_o[partition_queue_i] = 1'b1;
			endpoint_configure_count_o[partition_queue_i*ENTRY_COUNT_WIDTH+:
				ENTRY_COUNT_WIDTH] = partition_count_i;
			endpoint_configure_generation_o[partition_queue_i*GENERATION_WIDTH+:
				GENERATION_WIDTH] = partition_generation_i;
		end
	end

	// Preserve the first FU-local endpoint fault for top-level diagnosis.
	always_comb begin
		local_fault_found_w = 1'b0;
		first_local_fault_code_w = '0;
		for(integer queue_index = 0; queue_index < QUEUE_COUNT; queue_index++)begin
			if(!local_fault_found_w && endpoint_fault_i[queue_index])begin
				local_fault_found_w = 1'b1;
				first_local_fault_code_w = endpoint_fault_code_i[queue_index*4+:4];
			end
		end
	end

	lpu_qctl_pool #(
		.POOL_DEPTH(POOL_DEPTH), .QUEUE_COUNT(QUEUE_COUNT),
		.QUEUE_ENTRY_LIMIT(QUEUE_ENTRY_LIMIT), .READ_LATENCY(READ_LATENCY),
		.GENERATION_WIDTH(GENERATION_WIDTH)
	) u_pool (
		.clk_i, .rst_ni, .clear_i, .load_mode_i,
		.partition_valid_i, .partition_ready_o, .partition_queue_i,
		.partition_base_i, .partition_count_i, .partition_generation_i,
		.load_valid_i, .load_ready_o, .load_address_i, .load_data_i,
		.request_valid_i(pool_request_valid), .request_ready_o(pool_request_ready),
		.request_index_i(pool_request_index), .request_generation_i(pool_request_generation),
		.response_valid_o(pool_response_valid), .response_queue_o(pool_response_queue),
		.response_data_o(pool_response_data), .response_error_o(pool_response_error),
		.fault_o(pool_fault), .fault_code_o(pool_fault_code)
	);

	lpu_qctl_event_buffer #(
		.QUEUE_COUNT(QUEUE_COUNT), .EVENT_DEPTH(EVENT_DEPTH)
	) u_event_buffer (
		.clk_i, .rst_ni, .clear_i,
		.event_in_valid_i, .event_in_ready_o, .event_in_tag_i, .event_in_target_mask_i,
		.event_wait_i(event_wait), .event_consume_i(event_consume),
		.event_valid_o(event_buffer_valid), .event_tag_o(event_buffer_tag),
		.fault_o(event_fault), .fault_code_o(event_fault_code)
	);

	lpu_qctl_fabric #(
		.QUEUE_COUNT(QUEUE_COUNT), .QUEUE_ENTRY_LIMIT(QUEUE_ENTRY_LIMIT),
		.GENERATION_WIDTH(GENERATION_WIDTH)
	) u_fabric (
		.clk_i, .rst_ni, .clear_i,
		.endpoint_pool_request_valid_i, .endpoint_pool_request_ready_o,
		.endpoint_pool_request_index_i, .endpoint_pool_request_generation_i,
		.pool_request_valid_o(pool_request_valid), .pool_request_ready_i(pool_request_ready),
		.pool_request_index_o(pool_request_index), .pool_request_generation_o(pool_request_generation),
		.pool_response_valid_i(pool_response_valid), .pool_response_queue_i(pool_response_queue),
		.pool_response_data_i(pool_response_data), .pool_response_error_i(pool_response_error),
		.endpoint_pool_response_valid_o, .endpoint_pool_response_data_o,
		.endpoint_pool_response_error_o,
		.event_in_valid_i, .event_in_ready_i(event_in_ready_o), .event_backpressure_o,
		.endpoint_event_wait_i, .endpoint_event_consume_i,
		.event_wait_o(event_wait), .event_consume_o(event_consume),
		.event_buffer_valid_i(event_buffer_valid), .event_buffer_tag_i(event_buffer_tag),
		.endpoint_event_valid_o, .endpoint_event_tag_o,
		.sync_participant_mask_i, .endpoint_sync_arrive_valid_i,
		.endpoint_notify_valid_i, .endpoint_notify_ready_o,
		.endpoint_sync_release_valid_o,
		.endpoint_mem_packet_valid_i, .endpoint_mem_packet_ordinal_i,
		.mem_packet_valid_o, .mem_packet_ordinal_o, .mem_packet_retired_i,
		.endpoint_mem_packet_retired_o,
		.fault_o(fabric_fault), .fault_code_o(fabric_fault_code)
	);
endmodule
