`timescale 1ns/1ps

module lpu_qctl_distributed_trace_tb;
	localparam integer QUEUE_COUNT = 228;
	localparam integer QUEUE_ID = 16;
	localparam integer TOTAL_CAPACITY = 512;
	localparam integer ENTRY_INDEX_WIDTH = 4;
	localparam integer ENTRY_COUNT_WIDTH = 5;
	localparam integer GENERATION_WIDTH = 64;
	localparam integer ADDRESS_WIDTH = 9;

	logic clk_i;
	logic rst_ni;
	logic clear_i;
	logic load_mode_i;
	logic partition_valid_i;
	logic partition_ready_o;
	logic [7:0] partition_queue_i;
	logic [ADDRESS_WIDTH-1:0] partition_base_i;
	logic [ENTRY_COUNT_WIDTH-1:0] partition_count_i;
	logic [GENERATION_WIDTH-1:0] partition_generation_i;
	logic load_valid_i;
	logic load_ready_o;
	logic [ADDRESS_WIDTH-1:0] load_address_i;
	logic [95:0] load_data_i;

	logic [QUEUE_COUNT-1:0] endpoint_configure_valid_o;
	logic [QUEUE_COUNT*ENTRY_COUNT_WIDTH-1:0] endpoint_configure_count_o;
	logic [QUEUE_COUNT*GENERATION_WIDTH-1:0] endpoint_configure_generation_o;
	logic [QUEUE_COUNT*ENTRY_INDEX_WIDTH-1:0] endpoint_head_index_i;
	logic [QUEUE_COUNT*GENERATION_WIDTH-1:0] endpoint_head_generation_i;
	logic [QUEUE_COUNT-1:0] endpoint_store_loaded_o;
	logic [QUEUE_COUNT-1:0] endpoint_head_valid_o;
	logic [QUEUE_COUNT*96-1:0] endpoint_head_record_o;
	logic [QUEUE_COUNT-1:0] endpoint_head_error_o;

	logic [QUEUE_COUNT-1:0] endpoint_configured_i;
	logic [QUEUE_COUNT-1:0] endpoint_primed_i;
	logic [QUEUE_COUNT-1:0] endpoint_done_i;
	logic [QUEUE_COUNT-1:0] endpoint_fault_i;
	logic [QUEUE_COUNT*4-1:0] endpoint_fault_code_i;
	logic [QUEUE_COUNT-1:0] queue_active_o;
	logic load_complete_o;
	logic all_primed_o;
	logic all_done_o;
	logic fault_o;
	logic [7:0] fault_code_o;

	logic [ENTRY_INDEX_WIDTH-1:0] ep_head_index;
	logic [GENERATION_WIDTH-1:0] ep_head_generation;
	logic ep_scheduler_ce;
	logic ep_event_wait;
	logic ep_event_consume;
	logic ep_sync_arrive;
	logic ep_notify_valid;
	logic ep_mem_packet_valid;
	logic [31:0] ep_mem_packet_ordinal;
	logic ep_configured;
	logic ep_primed;
	logic ep_done;
	logic ep_fault;
	logic [3:0] ep_fault_code;

	logic [QUEUE_COUNT-1:0] zeros;
	logic [QUEUE_COUNT*32-1:0] zero_ordinals;
	logic [31:0] event_tag;
	integer trace_fd;
	integer action_index;
	integer cycle;
	logic accepted;
	string trace_path;

	assign zeros = '0;
	assign zero_ordinals = '0;
	assign event_tag = '0;

	always_comb begin
		endpoint_head_index_i = '0;
		endpoint_head_generation_i = '0;
		endpoint_head_index_i[QUEUE_ID*ENTRY_INDEX_WIDTH+:ENTRY_INDEX_WIDTH] = ep_head_index;
		endpoint_head_generation_i[QUEUE_ID*GENERATION_WIDTH+:GENERATION_WIDTH] =
			ep_head_generation;
		endpoint_configured_i = '0;
		endpoint_primed_i = '0;
		endpoint_done_i = '0;
		endpoint_fault_i = '0;
		endpoint_fault_code_i = '0;
		endpoint_configured_i[QUEUE_ID] = ep_configured;
		endpoint_primed_i[QUEUE_ID] = ep_primed;
		endpoint_done_i[QUEUE_ID] = ep_done;
		endpoint_fault_i[QUEUE_ID] = ep_fault;
		endpoint_fault_code_i[QUEUE_ID*4+:4] = ep_fault_code;
	end

	lpu_qctl_global_subsystem #(
		.TOTAL_CAPACITY(TOTAL_CAPACITY), .QUEUE_COUNT(QUEUE_COUNT),
		.QUEUE_ENTRY_LIMIT(16), .EVENT_DEPTH(8), .REGION_DEPTH(64),
		.RELAY_BUFFER_DEPTH(2), .GENERATION_WIDTH(GENERATION_WIDTH)
	) dut (
		.clk_i, .rst_ni, .clear_i, .load_mode_i,
		.partition_valid_i, .partition_ready_o, .partition_queue_i,
		.partition_base_i, .partition_count_i, .partition_generation_i,
		.load_valid_i, .load_ready_o, .load_address_i, .load_data_i,
		.endpoint_configure_valid_o, .endpoint_configure_count_o,
		.endpoint_configure_generation_o, .endpoint_head_index_i,
		.endpoint_head_generation_i, .endpoint_store_loaded_o,
		.endpoint_head_valid_o, .endpoint_head_record_o, .endpoint_head_error_o,
		.event_in_valid_i(1'b0), .event_in_ready_o(), .event_in_tag_i(event_tag),
		.event_in_target_mask_i(zeros), .event_backpressure_o(),
		.endpoint_event_wait_i(zeros), .endpoint_event_consume_i(zeros),
		.endpoint_event_valid_o(), .endpoint_event_tag_o(),
		.sync_participant_mask_i(zeros), .endpoint_sync_arrive_valid_i(zeros),
		.endpoint_notify_valid_i(zeros), .endpoint_notify_ready_o(),
		.endpoint_sync_release_valid_o(), .endpoint_mem_packet_valid_i(zeros),
		.endpoint_mem_packet_ordinal_i(zero_ordinals), .mem_packet_valid_o(),
		.mem_packet_ordinal_o(), .mem_packet_retired_i(zeros),
		.endpoint_mem_packet_retired_o(), .endpoint_configured_i,
		.endpoint_primed_i, .endpoint_done_i, .endpoint_fault_i,
		.endpoint_fault_code_i, .queue_active_o, .load_complete_o,
		.all_primed_o, .all_done_o, .fault_o, .fault_code_o
	);

	lpu_qctl_endpoint #(
		.QUEUE_ENTRY_LIMIT(16), .GENERATION_WIDTH(GENERATION_WIDTH)
	) endpoint (
		.clk_i, .rst_ni, .clear_i, .run_i(1'b0),
		.configure_valid_i(endpoint_configure_valid_o[QUEUE_ID]),
		.configure_count_i(endpoint_configure_count_o[
			QUEUE_ID*ENTRY_COUNT_WIDTH+:ENTRY_COUNT_WIDTH]),
		.configure_generation_i(endpoint_configure_generation_o[
			QUEUE_ID*GENERATION_WIDTH+:GENERATION_WIDTH]),
		.store_head_index_o(ep_head_index),
		.store_head_generation_o(ep_head_generation),
		.store_loaded_i(endpoint_store_loaded_o[QUEUE_ID]),
		.store_head_valid_i(endpoint_head_valid_o[QUEUE_ID]),
		.store_head_record_i(endpoint_head_record_o[QUEUE_ID*96+:96]),
		.store_head_error_i(endpoint_head_error_o[QUEUE_ID]),
		.scheduler_cycle_i('0), .scheduler_counter_ce_o(ep_scheduler_ce),
		.event_valid_i(1'b0), .event_tag_i('0), .event_wait_o(ep_event_wait),
		.event_consume_o(ep_event_consume), .sync_arrive_valid_o(ep_sync_arrive),
		.sync_release_valid_i(1'b0), .notify_valid_o(ep_notify_valid),
		.notify_ready_i(1'b0), .mem_packet_valid_o(ep_mem_packet_valid),
		.mem_packet_ordinal_o(ep_mem_packet_ordinal), .mem_packet_retired_i(1'b0),
		.configured_o(ep_configured), .primed_o(ep_primed), .done_o(ep_done),
		.fault_o(ep_fault), .fault_code_o(ep_fault_code)
	);

	always #5 clk_i = ~clk_i;

	task automatic drive_action(input integer index);
		begin
			partition_valid_i = 1'b0;
			load_valid_i = 1'b0;
			partition_queue_i = '0;
			partition_base_i = '0;
			partition_count_i = '0;
			partition_generation_i = '0;
			load_address_i = '0;
			load_data_i = '0;
			load_mode_i = index < 3;
			case(index)
				0: begin
					partition_valid_i = 1'b1;
					partition_queue_i = QUEUE_ID;
					partition_count_i = 2;
					partition_generation_i = 1;
				end
				1: begin
					load_valid_i = 1'b1;
					load_address_i = 0;
					load_data_i = lpu_qctl_pkg::qctl_pack_record(3,
						lpu_qctl_pkg::QCTL_OPCODE_WAIT_EVENT, 32'h16);
				end
				2: begin
					load_valid_i = 1'b1;
					load_address_i = 1;
					load_data_i = lpu_qctl_pkg::qctl_pack_record(5,
						lpu_qctl_pkg::QCTL_OPCODE_MEM_PACKET, 32'h103);
				end
				default: begin end
			endcase
		end
	endtask

	initial begin
		clk_i = 1'b0;
		rst_ni = 1'b0;
		clear_i = 1'b0;
		load_mode_i = 1'b0;
		partition_valid_i = 1'b0;
		load_valid_i = 1'b0;
		partition_queue_i = '0;
		partition_base_i = '0;
		partition_count_i = '0;
		partition_generation_i = '0;
		load_address_i = '0;
		load_data_i = '0;
		action_index = 0;
		trace_path = "phase3_r5_qctl_distributed_rtl_trace.csv";
		void'($value$plusargs("TRACE_PATH=%s", trace_path));
		trace_fd = $fopen(trace_path, "w");
		if(trace_fd == 0) $fatal(1, "cannot open QCTL distributed Trace");
		$fdisplay(trace_fd,
			"cycle,phase,load_mode,partition_valid,partition_ready,partition_fire,partition_queue,partition_base,partition_count,partition_generation,load_valid,load_ready,load_fire,load_address,load_data,relay_packet_valid,relay_packet_ready,relay_packet_kind,relay_packet_queue,relay_packet_offset,east_r0_input_fire,east_r0_local_fire,east_r0_output_valid,east_r0_output_ready,east_r0_fifo_level,east_r1_input_fire,east_r1_local_fire,east_r1_fifo_level,endpoint_configure_valid,endpoint_store_loaded,endpoint_head_valid,endpoint_head_error,endpoint_configured,endpoint_primed,queue_active,load_complete,all_primed,fault,fault_code");

		repeat(3) @(posedge clk_i);
		@(negedge clk_i);
		rst_ni = 1'b1;
		for(cycle = 0; cycle < 12; cycle = cycle + 1)begin
			clear_i = cycle == 0;
			if(cycle == 0) drive_action(3);
			else drive_action(action_index);
			#1;
			accepted = (partition_valid_i && partition_ready_o)
				|| (load_valid_i && load_ready_o);
			$fdisplay(trace_fd,
				"%0d,PRE_POSEDGE,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%024h,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d",
				cycle, load_mode_i, partition_valid_i, partition_ready_o,
				partition_valid_i && partition_ready_o, partition_queue_i,
				partition_base_i, partition_count_i, partition_generation_i,
				load_valid_i, load_ready_o, load_valid_i && load_ready_o,
				load_address_i, load_data_i, dut.relay_packet_valid,
				dut.relay_packet_ready, dut.relay_packet_kind, dut.relay_packet_queue,
				dut.relay_packet_offset,
				dut.u_east_relay_chain.gen_relay[0].u_relay.input_fire_w,
				dut.u_east_relay_chain.gen_relay[0].u_relay.local_fire_w,
				dut.u_east_relay_chain.gen_relay[0].u_relay.next_packet_valid_o,
				dut.u_east_relay_chain.gen_relay[0].u_relay.next_packet_ready_i,
				dut.u_east_relay_chain.gen_relay[0].u_relay.fifo_level_q,
				dut.u_east_relay_chain.gen_relay[1].u_relay.input_fire_w,
				dut.u_east_relay_chain.gen_relay[1].u_relay.local_fire_w,
				dut.u_east_relay_chain.gen_relay[1].u_relay.fifo_level_q,
				endpoint_configure_valid_o[QUEUE_ID], endpoint_store_loaded_o[QUEUE_ID],
				endpoint_head_valid_o[QUEUE_ID], endpoint_head_error_o[QUEUE_ID],
				ep_configured, ep_primed, queue_active_o[QUEUE_ID], load_complete_o,
				all_primed_o, fault_o, fault_code_o);
			@(posedge clk_i);
			#1;
			if(accepted) action_index = action_index + 1;
			@(negedge clk_i);
		end
		$fclose(trace_fd);
		if(action_index != 3 || !ep_primed || !load_complete_o || !all_primed_o
			|| fault_o)begin
			$fatal(1, "QCTL_DISTRIBUTED_TRACE_TB FAIL action=%0d primed=%0d complete=%0d all_primed=%0d fault=%0d code=%0h",
				action_index, ep_primed, load_complete_o, all_primed_o, fault_o,
				fault_code_o);
		end
		$display("QCTL_DISTRIBUTED_TRACE_TB PASS rows=12");
		$finish;
	end
endmodule
