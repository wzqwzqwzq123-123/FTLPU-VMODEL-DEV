`timescale 1ns/1ps

module lpu_qctl_fabric_tb;
	localparam integer QUEUE_COUNT = 4;
	localparam integer POOL_DEPTH = 32;
	localparam integer QUEUE_ENTRY_LIMIT = 16;
	localparam integer QUEUE_ID_WIDTH = 2;
	localparam integer POOL_ADDRESS_WIDTH = 5;
	localparam integer ENTRY_COUNT_WIDTH = 5;

	logic clk;
	logic rst_n;
	logic clear;
	logic run;
	logic load_mode;
	logic partition_valid;
	logic partition_ready;
	logic [QUEUE_ID_WIDTH-1:0] partition_queue;
	logic [POOL_ADDRESS_WIDTH-1:0] partition_base;
	logic [ENTRY_COUNT_WIDTH-1:0] partition_count;
	logic [63:0] partition_generation;
	logic load_valid;
	logic load_ready;
	logic [POOL_ADDRESS_WIDTH-1:0] load_address;
	logic [95:0] load_data;
	logic [QUEUE_COUNT-1:0] event_valid;
	logic [QUEUE_COUNT-1:0] event_ready;
	logic [QUEUE_COUNT*32-1:0] event_tag;
	logic [QUEUE_COUNT-1:0] sync_valid;
	logic [QUEUE_COUNT-1:0] sync_ready;
	logic [QUEUE_COUNT-1:0] notify_valid;
	logic [QUEUE_COUNT-1:0] notify_ready;
	logic [QUEUE_COUNT-1:0] mem_packet_valid;
	logic [QUEUE_COUNT*32-1:0] mem_packet_ordinal;
	logic [QUEUE_COUNT-1:0] mem_packet_retired;
	logic [QUEUE_COUNT-1:0] queue_active;
	logic [QUEUE_COUNT-1:0] scheduler_enable;
	logic [QUEUE_COUNT*32-1:0] queue_cycle;
	logic [QUEUE_COUNT-1:0] wait_event_blocked;
	logic [QUEUE_COUNT*32-1:0] wait_event_tag;
	logic [QUEUE_COUNT-1:0] primed;
	logic [QUEUE_COUNT-1:0] done;
	logic all_primed;
	logic all_done;
	logic fault;
	logic [7:0] fault_code;

	lpu_qctl_fabric #(
		.POOL_DEPTH(POOL_DEPTH),
		.QUEUE_COUNT(QUEUE_COUNT),
		.QUEUE_ENTRY_LIMIT(QUEUE_ENTRY_LIMIT),
		.CACHE_DEPTH(4),
		.EVENT_TOKEN_DEPTH(4),
		.SYNC_TOKEN_DEPTH(4)
	) dut (
		.clk_i(clk), .rst_ni(rst_n), .clear_i(clear), .run_i(run),
		.load_mode_i(load_mode), .partition_valid_i(partition_valid),
		.partition_ready_o(partition_ready), .partition_queue_i(partition_queue),
		.partition_base_i(partition_base), .partition_count_i(partition_count),
		.partition_generation_i(partition_generation), .load_valid_i(load_valid),
		.load_ready_o(load_ready), .load_address_i(load_address), .load_data_i(load_data),
		.event_valid_i(event_valid), .event_ready_o(event_ready), .event_tag_i(event_tag),
		.sync_valid_i(sync_valid), .sync_ready_o(sync_ready),
		.notify_valid_o(notify_valid), .notify_ready_i(notify_ready),
		.mem_packet_valid_o(mem_packet_valid), .mem_packet_ordinal_o(mem_packet_ordinal),
		.mem_packet_retired_i(mem_packet_retired), .queue_active_o(queue_active),
		.scheduler_enable_o(scheduler_enable), .queue_cycle_o(queue_cycle),
		.wait_event_blocked_o(wait_event_blocked), .wait_event_tag_o(wait_event_tag),
		.primed_o(primed), .done_o(done), .all_primed_o(all_primed),
		.all_done_o(all_done), .fault_o(fault), .fault_code_o(fault_code)
	);

	always #5 clk = ~clk;

	task automatic write_record(input logic [POOL_ADDRESS_WIDTH-1:0] address,
		input logic [95:0] data);
		begin
			@(negedge clk);
			load_valid = 1'b1;
			load_address = address;
			load_data = data;
			@(posedge clk);
			if(!load_ready) $fatal(1, "QCTL Fabric load was not accepted");
			@(negedge clk);
			load_valid = 1'b0;
		end
	endtask

	task automatic configure_queue(input logic [QUEUE_ID_WIDTH-1:0] queue_id,
		input logic [POOL_ADDRESS_WIDTH-1:0] base,
		input logic [ENTRY_COUNT_WIDTH-1:0] count,
		input logic [63:0] generation);
		begin
			@(negedge clk);
			partition_valid = 1'b1;
			partition_queue = queue_id;
			partition_base = base;
			partition_count = count;
			partition_generation = generation;
			@(posedge clk);
			if(!partition_ready) $fatal(1, "QCTL Fabric partition was not accepted");
			@(negedge clk);
			partition_valid = 1'b0;
		end
	endtask

	initial begin
		clk = 1'b0;
		rst_n = 1'b0;
		clear = 1'b0;
		run = 1'b0;
		load_mode = 1'b1;
		partition_valid = 1'b0;
		partition_queue = '0;
		partition_base = '0;
		partition_count = '0;
		partition_generation = '0;
		load_valid = 1'b0;
		load_address = '0;
		load_data = '0;
		event_valid = '0;
		event_tag = '0;
		sync_valid = '0;
		notify_ready = '1;
		mem_packet_retired = '1;

		repeat(4) @(posedge clk);
		rst_n = 1'b1;
		write_record(0, lpu_qctl_pkg::qctl_pack_record(32'd2,
			lpu_qctl_pkg::QCTL_OPCODE_WAIT_EVENT, 32'h55));
		configure_queue(2'd1, 0, 1, 64'd1);
		configure_queue(2'd2, 1, 0, 64'd2);
		@(negedge clk);
		load_mode = 1'b0;

		wait(all_primed);
		if(queue_active != 4'b0110) $fatal(1, "Unexpected active Queue map %b", queue_active);
		run = 1'b1;
		wait(wait_event_blocked[1]);
		if(queue_cycle[1*32+:32] != 2) $fatal(1, "WAIT boundary moved from cycle 2");
		repeat(3) @(posedge clk);
		if(queue_cycle[1*32+:32] != 2) $fatal(1, "Blocked Queue-local cycle did not freeze");
		if(queue_cycle[2*32+:32] <= 2) $fatal(1, "Independent Queue stopped with blocked Queue");

		@(negedge clk);
		event_valid[1] = 1'b1;
		event_tag[1*32+:32] = 32'h55;
		@(posedge clk);
		if(!event_ready[1]) $fatal(1, "WAIT event was not accepted");
		@(negedge clk);
		event_valid[1] = 1'b0;
		wait(queue_cycle[1*32+:32] > 2);
		if(fault) $fatal(1, "Unexpected QCTL Fabric fault code=%0h", fault_code);
		if(!done[1]) $fatal(1, "QCTL record did not retire after matching event");
		$display("LPU_QCTL_FABRIC_TB_PASS q1_cycle=%0d q2_cycle=%0d",
			queue_cycle[1*32+:32], queue_cycle[2*32+:32]);
		$finish;
	end

	initial begin
		repeat(400) @(posedge clk);
		$fatal(1, "QCTL Fabric test timed out");
	end
endmodule
