`timescale 1ns/1ps

module lpu_qctl_queue_controller_tb;
	localparam integer QUEUE_COUNT = 2;
	localparam integer POOL_DEPTH = 32;
	localparam integer QUEUE_ENTRY_LIMIT = 16;
	localparam integer CACHE_DEPTH = 4;
	localparam integer GENERATION_WIDTH = 64;
	localparam integer QUEUE_ID_WIDTH = 1;
	localparam integer POOL_ADDRESS_WIDTH = 5;
	localparam integer ENTRY_INDEX_WIDTH = 4;
	localparam integer ENTRY_COUNT_WIDTH = 5;

	logic clk;
	logic rst_n;
	logic clear;
	logic load_mode;
	logic partition_valid;
	logic partition_ready;
	logic [QUEUE_ID_WIDTH-1:0] partition_queue;
	logic [POOL_ADDRESS_WIDTH-1:0] partition_base;
	logic [ENTRY_COUNT_WIDTH-1:0] partition_count;
	logic [GENERATION_WIDTH-1:0] partition_generation;
	logic load_valid;
	logic load_ready;
	logic [POOL_ADDRESS_WIDTH-1:0] load_address;
	logic [lpu_qctl_pkg::QCTL_RECORD_WIDTH-1:0] load_data;
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

	logic [QUEUE_COUNT-1:0] configure_valid;
	logic [QUEUE_COUNT*ENTRY_COUNT_WIDTH-1:0] configure_count;
	logic [QUEUE_COUNT*GENERATION_WIDTH-1:0] configure_generation;
	logic [QUEUE_COUNT-1:0] event_valid;
	logic [QUEUE_COUNT-1:0] event_ready;
	logic [QUEUE_COUNT*lpu_qctl_pkg::QCTL_OPERAND_WIDTH-1:0] event_tag;
	logic [QUEUE_COUNT-1:0] sync_valid;
	logic [QUEUE_COUNT-1:0] sync_ready;
	logic [QUEUE_COUNT-1:0] notify_valid;
	logic [QUEUE_COUNT-1:0] notify_ready;
	logic [QUEUE_COUNT-1:0] mem_packet_valid;
	logic [QUEUE_COUNT*lpu_qctl_pkg::QCTL_OPERAND_WIDTH-1:0] mem_packet_ordinal;
	logic [QUEUE_COUNT-1:0] mem_packet_retired;
	logic [QUEUE_COUNT-1:0] run;
	logic [QUEUE_COUNT-1:0] scheduler_enable;
	logic [QUEUE_COUNT*lpu_qctl_pkg::QCTL_CYCLE_WIDTH-1:0] queue_cycle;
	logic [QUEUE_COUNT-1:0] wait_event_blocked;
	logic [QUEUE_COUNT*lpu_qctl_pkg::QCTL_OPERAND_WIDTH-1:0] wait_event_tag;
	logic [QUEUE_COUNT-1:0] primed;
	logic [QUEUE_COUNT-1:0] done;
	logic [QUEUE_COUNT-1:0] controller_fault;
	logic [QUEUE_COUNT*4-1:0] controller_fault_code;

	integer notify_count;
	integer mem_packet_cycles;
	logic [31:0] previous_queue_0_cycle;
	logic previous_queue_0_blocked;

	lpu_qctl_shared_pool #(
		.POOL_DEPTH(POOL_DEPTH),
		.QUEUE_COUNT(QUEUE_COUNT),
		.QUEUE_ENTRY_LIMIT(QUEUE_ENTRY_LIMIT),
		.READ_LATENCY(2),
		.GENERATION_WIDTH(GENERATION_WIDTH)
	) dut_pool (
		.clk_i(clk),
		.rst_ni(rst_n),
		.clear_i(clear),
		.load_mode_i(load_mode),
		.partition_valid_i(partition_valid),
		.partition_ready_o(partition_ready),
		.partition_queue_i(partition_queue),
		.partition_base_i(partition_base),
		.partition_count_i(partition_count),
		.partition_generation_i(partition_generation),
		.load_valid_i(load_valid),
		.load_ready_o(load_ready),
		.load_address_i(load_address),
		.load_data_i(load_data),
		.request_valid_i(request_valid),
		.request_ready_o(request_ready),
		.request_index_i(request_index),
		.request_generation_i(request_generation),
		.response_valid_o(response_valid),
		.response_queue_o(response_queue),
		.response_data_o(response_data),
		.response_error_o(response_error),
		.fault_o(pool_fault),
		.fault_code_o(pool_fault_code)
	);

	generate
		for(genvar queue_index = 0; queue_index < QUEUE_COUNT; queue_index++)begin : gen_controllers
			lpu_qctl_queue_controller #(
				.QUEUE_ENTRY_LIMIT(QUEUE_ENTRY_LIMIT),
				.CACHE_DEPTH(CACHE_DEPTH),
				.EVENT_TOKEN_DEPTH(4),
				.SYNC_TOKEN_DEPTH(4),
				.GENERATION_WIDTH(GENERATION_WIDTH)
			) dut_controller (
				.clk_i(clk),
				.rst_ni(rst_n),
				.clear_i(clear),
				.configure_valid_i(configure_valid[queue_index]),
				.configure_count_i(configure_count[queue_index*ENTRY_COUNT_WIDTH+:ENTRY_COUNT_WIDTH]),
				.configure_generation_i(configure_generation[queue_index*GENERATION_WIDTH+:GENERATION_WIDTH]),
				.pool_request_valid_o(request_valid[queue_index]),
				.pool_request_ready_i(request_ready[queue_index]),
				.pool_request_index_o(request_index[queue_index*ENTRY_INDEX_WIDTH+:ENTRY_INDEX_WIDTH]),
				.pool_request_generation_o(request_generation[queue_index*GENERATION_WIDTH+:GENERATION_WIDTH]),
				.pool_response_valid_i(response_valid && response_queue == queue_index),
				.pool_response_data_i(response_data),
				.pool_response_error_i(response_error),
				.event_valid_i(event_valid[queue_index]),
				.event_ready_o(event_ready[queue_index]),
				.event_tag_i(event_tag[queue_index*lpu_qctl_pkg::QCTL_OPERAND_WIDTH+:lpu_qctl_pkg::QCTL_OPERAND_WIDTH]),
				.sync_valid_i(sync_valid[queue_index]),
				.sync_ready_o(sync_ready[queue_index]),
				.notify_valid_o(notify_valid[queue_index]),
				.notify_ready_i(notify_ready[queue_index]),
				.mem_packet_valid_o(mem_packet_valid[queue_index]),
				.mem_packet_ordinal_o(mem_packet_ordinal[queue_index*lpu_qctl_pkg::QCTL_OPERAND_WIDTH+:lpu_qctl_pkg::QCTL_OPERAND_WIDTH]),
				.mem_packet_retired_i(mem_packet_retired[queue_index]),
				.run_i(run[queue_index]),
				.scheduler_enable_o(scheduler_enable[queue_index]),
				.queue_cycle_o(queue_cycle[queue_index*lpu_qctl_pkg::QCTL_CYCLE_WIDTH+:lpu_qctl_pkg::QCTL_CYCLE_WIDTH]),
				.wait_event_blocked_o(wait_event_blocked[queue_index]),
				.wait_event_tag_o(wait_event_tag[queue_index*lpu_qctl_pkg::QCTL_OPERAND_WIDTH+:lpu_qctl_pkg::QCTL_OPERAND_WIDTH]),
				.primed_o(primed[queue_index]),
				.done_o(done[queue_index]),
				.fault_o(controller_fault[queue_index]),
				.fault_code_o(controller_fault_code[queue_index*4+:4])
			);
		end
	endgenerate

	always #5 clk = ~clk;

	task automatic write_record(
		input logic [POOL_ADDRESS_WIDTH-1:0] address,
		input logic [lpu_qctl_pkg::QCTL_RECORD_WIDTH-1:0] data
	);
		begin
			@(negedge clk);
			load_address = address;
			load_data = data;
			load_valid = 1'b1;
			@(posedge clk);
			if(!load_ready) $fatal(1, "QCTL Pool rejected a valid load");
			@(negedge clk);
			load_valid = 1'b0;
		end
	endtask

	task automatic configure_partition(
		input logic [QUEUE_ID_WIDTH-1:0] queue_id,
		input logic [POOL_ADDRESS_WIDTH-1:0] base,
		input logic [ENTRY_COUNT_WIDTH-1:0] count,
		input logic [GENERATION_WIDTH-1:0] generation
	);
		begin
			@(negedge clk);
			partition_queue = queue_id;
			partition_base = base;
			partition_count = count;
			partition_generation = generation;
			partition_valid = 1'b1;
			@(posedge clk);
			if(!partition_ready) $fatal(1, "QCTL Pool rejected a valid partition");
			@(negedge clk);
			partition_valid = 1'b0;
		end
	endtask

	task automatic send_event(input integer queue_id, input logic [31:0] tag);
		begin
			@(negedge clk);
			event_tag[queue_id*32+:32] = tag;
			event_valid[queue_id] = 1'b1;
			while(!event_ready[queue_id]) @(negedge clk);
			@(posedge clk);
			@(negedge clk);
			event_valid[queue_id] = 1'b0;
		end
	endtask

	always_ff @(posedge clk or negedge rst_n) begin
		if(!rst_n)begin
			notify_count <= 0;
			mem_packet_cycles <= 0;
			previous_queue_0_cycle <= 0;
			previous_queue_0_blocked <= 1'b0;
		end
		else begin
			if(notify_valid[0] && notify_ready[0])begin
				notify_count <= notify_count + 1;
			end
			if(mem_packet_valid[0])begin
				mem_packet_cycles <= mem_packet_cycles + 1;
			end
			if(previous_queue_0_blocked && queue_cycle[31:0] != previous_queue_0_cycle)begin
				$fatal(1, "WAIT_EVENT advanced Queue-local cycle while blocked");
			end
			previous_queue_0_cycle <= queue_cycle[31:0];
			previous_queue_0_blocked <= wait_event_blocked[0];
		end
	end

	initial begin
		clk = 1'b0;
		rst_n = 1'b0;
		clear = 1'b0;
		load_mode = 1'b1;
		partition_valid = 1'b0;
		partition_queue = '0;
		partition_base = '0;
		partition_count = '0;
		partition_generation = '0;
		load_valid = 1'b0;
		load_address = '0;
		load_data = '0;
		configure_valid = '0;
		configure_count = '0;
		configure_generation = '0;
		event_valid = '0;
		event_tag = '0;
		sync_valid = '0;
		notify_ready = '1;
		mem_packet_retired = '0;
		run = '0;

		repeat(4) @(posedge clk);
		rst_n = 1'b1;

		configure_partition(0, 0, 5, 64'd11);
		configure_partition(1, 16, 1, 64'd11);
		write_record(0, lpu_qctl_pkg::qctl_pack_record(2, lpu_qctl_pkg::QCTL_OPCODE_WAIT_EVENT, 7));
		write_record(1, lpu_qctl_pkg::qctl_pack_record(2, lpu_qctl_pkg::QCTL_OPCODE_WAIT_EVENT, 8));
		write_record(2, lpu_qctl_pkg::qctl_pack_record(4, lpu_qctl_pkg::QCTL_OPCODE_NOTIFY, 0));
		write_record(3, lpu_qctl_pkg::qctl_pack_record(6, lpu_qctl_pkg::QCTL_OPCODE_MEM_PACKET, 3));
		write_record(4, lpu_qctl_pkg::qctl_pack_record(8, lpu_qctl_pkg::QCTL_OPCODE_WAIT_EVENT, 10));
		write_record(16, lpu_qctl_pkg::qctl_pack_record(3, lpu_qctl_pkg::QCTL_OPCODE_WAIT_EVENT, 9));

		@(negedge clk);
		load_mode = 1'b0;
		configure_count[0*ENTRY_COUNT_WIDTH+:ENTRY_COUNT_WIDTH] = 5;
		configure_count[1*ENTRY_COUNT_WIDTH+:ENTRY_COUNT_WIDTH] = 1;
		configure_generation[0*GENERATION_WIDTH+:GENERATION_WIDTH] = 64'd11;
		configure_generation[1*GENERATION_WIDTH+:GENERATION_WIDTH] = 64'd11;
		configure_valid = '1;
		@(posedge clk);
		@(negedge clk);
		configure_valid = '0;

		wait(&primed);
		fork
			send_event(1, 9);
			send_event(0, 10);
		join
		@(negedge clk);
		run = '1;

		wait(wait_event_blocked[0] && wait_event_tag[31:0] == 7);
		send_event(0, 7);
		wait(wait_event_blocked[0] && wait_event_tag[31:0] == 8);
		send_event(0, 8);

		wait(mem_packet_valid[0]);
		repeat(2) @(posedge clk);
		if(mem_packet_ordinal[31:0] != 3) $fatal(1, "Wrong MEM_PACKET ordinal");
		@(negedge clk);
		mem_packet_retired[0] = 1'b1;
		@(posedge clk);
		@(negedge clk);
		mem_packet_retired[0] = 1'b0;

		wait(done[0] && done[1]);
		repeat(3) @(posedge clk);
		if(pool_fault || |controller_fault)begin
			$fatal(1, "Unexpected QCTL fault pool=%0d:%0d controller=%b:%h",
				pool_fault, pool_fault_code, controller_fault, controller_fault_code);
		end
		if(notify_count != 1) $fatal(1, "NOTIFY count mismatch: %0d", notify_count);
		if(mem_packet_cycles < 2) $fatal(1, "MEM_PACKET did not retain the boundary");
		if(queue_cycle[63:32] <= queue_cycle[31:0])begin
			$fatal(1, "Independent Queue did not advance while Queue 0 waited");
		end
		$display("LPU_QCTL_QUEUE_CONTROLLER_TB_PASS q0_cycle=%0d q1_cycle=%0d notify=%0d mem_cycles=%0d",
			queue_cycle[31:0], queue_cycle[63:32], notify_count, mem_packet_cycles);
		$finish;
	end

	initial begin
		repeat(500) @(posedge clk);
		$fatal(1, "QCTL Queue Controller test timed out");
	end
endmodule
