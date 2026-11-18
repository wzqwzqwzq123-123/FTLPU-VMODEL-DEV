module lpu_qctl_system #(
	parameter integer POOL_DEPTH = 512,
	parameter integer QUEUE_COUNT = 220,
	parameter integer QUEUE_ENTRY_LIMIT = 16,
	parameter integer CACHE_DEPTH = 4,
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
	input logic run_i,
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

	input logic [QUEUE_COUNT-1:0] sync_participant_mask_i,
	input logic event_valid_i,
	output logic event_ready_o,
	input logic [lpu_qctl_pkg::QCTL_OPERAND_WIDTH-1:0] event_tag_i,
	input logic [QUEUE_COUNT*lpu_qctl_pkg::QCTL_CYCLE_WIDTH-1:0] scheduler_cycle_i,
	output logic [QUEUE_COUNT-1:0] scheduler_counter_ce_o,
	output logic [QUEUE_COUNT-1:0] mem_packet_valid_o,
	output logic [QUEUE_COUNT*lpu_qctl_pkg::QCTL_OPERAND_WIDTH-1:0] mem_packet_ordinal_o,
	input logic [QUEUE_COUNT-1:0] mem_packet_retired_i,

	output logic [QUEUE_COUNT-1:0] queue_active_o,
	output logic [QUEUE_COUNT-1:0] wait_event_blocked_o,
	output logic [QUEUE_COUNT*lpu_qctl_pkg::QCTL_OPERAND_WIDTH-1:0] wait_event_tag_o,
	output logic [QUEUE_COUNT-1:0] primed_o,
	output logic [QUEUE_COUNT-1:0] done_o,
	output logic [QUEUE_COUNT-1:0] sync_arrive_o,
	output logic [QUEUE_COUNT-1:0] notify_pending_o,
	output logic [QUEUE_COUNT-1:0] sync_release_o,
	output logic all_primed_o,
	output logic all_done_o,
	output logic fault_o,
	output logic [7:0] fault_code_o
);
	logic partition_fire;
	logic partition_basic_valid_w;
	logic [QUEUE_COUNT-1:0] queue_active_q;
	logic [QUEUE_COUNT-1:0] configure_valid;
	logic [QUEUE_COUNT*ENTRY_COUNT_WIDTH-1:0] configure_count;
	logic [QUEUE_COUNT*GENERATION_WIDTH-1:0] configure_generation;
	logic [QUEUE_COUNT-1:0] request_valid;
	logic [QUEUE_COUNT-1:0] request_ready;
	logic [QUEUE_COUNT*ENTRY_INDEX_WIDTH-1:0] request_index;
	logic [QUEUE_COUNT*GENERATION_WIDTH-1:0] request_generation;
	logic response_valid;
	logic [QUEUE_ID_WIDTH-1:0] response_queue;
	logic [lpu_qctl_pkg::QCTL_RECORD_WIDTH-1:0] response_data;
	logic response_error;
	logic pool_fault;
	logic [3:0] pool_fault_code;
	logic [QUEUE_COUNT-1:0] cache_configured;
	logic [QUEUE_COUNT-1:0] cache_fault;
	logic [QUEUE_COUNT*4-1:0] cache_fault_code;
	logic [QUEUE_COUNT-1:0] controller_fault;
	logic [QUEUE_COUNT*4-1:0] controller_fault_code;
	logic [QUEUE_COUNT-1:0] head_valid;
	logic [QUEUE_COUNT*lpu_qctl_pkg::QCTL_RECORD_WIDTH-1:0] head_record;
	logic [QUEUE_COUNT-1:0] head_retire;
	logic [QUEUE_COUNT-1:0] notify_ready;
	logic event_broadcast_valid;
	logic [lpu_qctl_pkg::QCTL_OPERAND_WIDTH-1:0] event_broadcast_tag;
	logic barrier_fault;
	logic event_fault;
	logic local_fault_found_w;
	logic [3:0] first_local_fault_code_w;

	assign partition_fire = partition_valid_i && partition_ready_o;
	assign partition_basic_valid_w = (partition_queue_i < QUEUE_COUNT) &&
		(partition_count_i <= QUEUE_ENTRY_LIMIT) && (partition_generation_i != 0) &&
		(({1'b0, partition_base_i} + partition_count_i) <= POOL_DEPTH);
	assign queue_active_o = queue_active_q;
	assign all_primed_o = &(primed_o | ~queue_active_q);
	assign all_done_o = &(done_o | ~queue_active_q);
	assign fault_o = pool_fault || barrier_fault || event_fault ||
		(|cache_fault) || (|controller_fault);
	assign fault_code_o = pool_fault ? {4'd0, pool_fault_code} :
		(barrier_fault ? 8'h20 : (event_fault ? 8'h30 :
		(local_fault_found_w ? {4'd1, first_local_fault_code_w} : 8'd0)));

	// A legal partition configures exactly one Queue-local Cache and Controller.
	always_comb begin
		configure_valid = '0;
		configure_count = '0;
		configure_generation = '0;
		if(partition_fire && partition_basic_valid_w)begin
			configure_valid[partition_queue_i] = 1'b1;
			configure_count[partition_queue_i*ENTRY_COUNT_WIDTH+:ENTRY_COUNT_WIDTH] =
				partition_count_i;
			configure_generation[partition_queue_i*GENERATION_WIDTH+:GENERATION_WIDTH] =
				partition_generation_i;
		end
	end

	// Preserve the first Queue-local Cache or Controller fault for top-level debug.
	always_comb begin
		local_fault_found_w = 1'b0;
		first_local_fault_code_w = '0;
		for(integer queue_index = 0; queue_index < QUEUE_COUNT; queue_index++)begin
			if(!local_fault_found_w && cache_fault[queue_index])begin
				local_fault_found_w = 1'b1;
				first_local_fault_code_w = cache_fault_code[queue_index*4+:4];
			end
			else if(!local_fault_found_w && controller_fault[queue_index])begin
				local_fault_found_w = 1'b1;
				first_local_fault_code_w = controller_fault_code[queue_index*4+:4];
			end
		end
	end

	// Queue activity is program configuration state, independent of runtime waits.
	always_ff @(posedge clk_i or negedge rst_ni) begin
		if(!rst_ni)begin
			queue_active_q <= '0;
		end
		else if(clear_i)begin
			queue_active_q <= '0;
		end
		else begin
			queue_active_q <= queue_active_q | configure_valid;
		end
	end

	lpu_qctl_shared_pool #(
		.POOL_DEPTH(POOL_DEPTH),
		.QUEUE_COUNT(QUEUE_COUNT),
		.QUEUE_ENTRY_LIMIT(QUEUE_ENTRY_LIMIT),
		.READ_LATENCY(READ_LATENCY),
		.GENERATION_WIDTH(GENERATION_WIDTH)
	) u_shared_pool (
		.clk_i, .rst_ni, .clear_i, .load_mode_i,
		.partition_valid_i, .partition_ready_o, .partition_queue_i,
		.partition_base_i, .partition_count_i, .partition_generation_i,
		.load_valid_i, .load_ready_o, .load_address_i, .load_data_i,
		.request_valid_i(request_valid), .request_ready_o(request_ready),
		.request_index_i(request_index), .request_generation_i(request_generation),
		.response_valid_o(response_valid), .response_queue_o(response_queue),
		.response_data_o(response_data), .response_error_o(response_error),
		.fault_o(pool_fault), .fault_code_o(pool_fault_code)
	);

	lpu_qctl_event_buffer #(
		.QUEUE_COUNT(QUEUE_COUNT),
		.EVENT_DEPTH(EVENT_DEPTH)
	) u_event_buffer (
		.clk_i, .rst_ni, .clear_i,
		.event_valid_i, .event_ready_o, .event_tag_i,
		.waiter_valid_i(wait_event_blocked_o),
		.waiter_tag_i(wait_event_tag_o),
		.broadcast_valid_o(event_broadcast_valid),
		.broadcast_tag_o(event_broadcast_tag),
		.fault_o(event_fault)
	);

	lpu_qctl_sync_fabric #(
		.QUEUE_COUNT(QUEUE_COUNT)
	) u_sync_fabric (
		.clk_i, .rst_ni, .clear_i,
		.participant_mask_i(sync_participant_mask_i),
		.sync_arrive_valid_i(sync_arrive_o),
		.notify_valid_i(notify_pending_o),
		.notify_ready_o(notify_ready),
		.sync_release_valid_o(sync_release_o),
		.fault_o(barrier_fault)
	);

	// One independent Cache and semantic Controller is created for every formal
	// FU Queue. Only the Pool and broadcast fabrics are shared.
	generate
		for(genvar queue_index = 0; queue_index < QUEUE_COUNT; queue_index++)begin : gen_queue_endpoint
			lpu_qctl_queue_cache #(
				.QUEUE_ENTRY_LIMIT(QUEUE_ENTRY_LIMIT),
				.CACHE_DEPTH(CACHE_DEPTH),
				.GENERATION_WIDTH(GENERATION_WIDTH)
			) u_queue_cache (
				.clk_i, .rst_ni, .clear_i,
				.configure_valid_i(configure_valid[queue_index]),
				.configure_count_i(configure_count[queue_index*ENTRY_COUNT_WIDTH+:ENTRY_COUNT_WIDTH]),
				.configure_generation_i(configure_generation[queue_index*GENERATION_WIDTH+:GENERATION_WIDTH]),
				.pool_request_valid_o(request_valid[queue_index]),
				.pool_request_ready_i(request_ready[queue_index]),
				.pool_request_index_o(request_index[queue_index*ENTRY_INDEX_WIDTH+:ENTRY_INDEX_WIDTH]),
				.pool_request_generation_o(request_generation[queue_index*GENERATION_WIDTH+:GENERATION_WIDTH]),
				.pool_response_valid_i(response_valid && (response_queue == queue_index)),
				.pool_response_data_i(response_data),
				.pool_response_error_i(response_error),
				.head_valid_o(head_valid[queue_index]),
				.head_record_o(head_record[queue_index*lpu_qctl_pkg::QCTL_RECORD_WIDTH+:
					lpu_qctl_pkg::QCTL_RECORD_WIDTH]),
				.head_retire_i(head_retire[queue_index]),
				.configured_o(cache_configured[queue_index]),
				.primed_o(primed_o[queue_index]),
				.done_o(done_o[queue_index]),
				.fault_o(cache_fault[queue_index]),
				.fault_code_o(cache_fault_code[queue_index*4+:4])
			);

			lpu_qctl_controller u_controller (
				.clk_i, .rst_ni, .clear_i,
				.configure_valid_i(configure_valid[queue_index]),
				.run_i,
				.configured_i(cache_configured[queue_index]),
				.primed_i(primed_o[queue_index]),
				.done_i(done_o[queue_index]),
				.scheduler_cycle_i(scheduler_cycle_i[
					queue_index*lpu_qctl_pkg::QCTL_CYCLE_WIDTH+:
					lpu_qctl_pkg::QCTL_CYCLE_WIDTH]),
				.scheduler_counter_ce_o(scheduler_counter_ce_o[queue_index]),
				.head_valid_i(head_valid[queue_index]),
				.head_record_i(head_record[queue_index*lpu_qctl_pkg::QCTL_RECORD_WIDTH+:
					lpu_qctl_pkg::QCTL_RECORD_WIDTH]),
				.head_retire_o(head_retire[queue_index]),
				.sync_arrive_valid_o(sync_arrive_o[queue_index]),
				.sync_release_valid_i(sync_release_o[queue_index]),
				.notify_valid_o(notify_pending_o[queue_index]),
				.notify_ready_i(notify_ready[queue_index]),
				.event_valid_i(event_broadcast_valid),
				.event_tag_i(event_broadcast_tag),
				.mem_packet_valid_o(mem_packet_valid_o[queue_index]),
				.mem_packet_ordinal_o(mem_packet_ordinal_o[
					queue_index*lpu_qctl_pkg::QCTL_OPERAND_WIDTH+:
					lpu_qctl_pkg::QCTL_OPERAND_WIDTH]),
				.mem_packet_retired_i(mem_packet_retired_i[queue_index]),
				.wait_event_blocked_o(wait_event_blocked_o[queue_index]),
				.wait_event_tag_o(wait_event_tag_o[
					queue_index*lpu_qctl_pkg::QCTL_OPERAND_WIDTH+:
					lpu_qctl_pkg::QCTL_OPERAND_WIDTH]),
				.fault_o(controller_fault[queue_index]),
				.fault_code_o(controller_fault_code[queue_index*4+:4])
			);
		end
	endgenerate
endmodule
