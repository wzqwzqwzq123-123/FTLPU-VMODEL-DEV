`timescale 1ns/1ps

module lpu_qctl_shared_pool_tb;
	timeunit 1ns;
	timeprecision 1ps;

	localparam integer POOL_DEPTH = 8;
	localparam integer QUEUE_COUNT = 3;
	localparam integer QUEUE_ENTRY_LIMIT = 3;
	localparam integer READ_LATENCY = 2;
	localparam integer GENERATION_WIDTH = 8;
	localparam integer POOL_ADDRESS_WIDTH = $clog2(POOL_DEPTH);
	localparam integer QUEUE_ID_WIDTH = $clog2(QUEUE_COUNT);
	localparam integer ENTRY_INDEX_WIDTH = $clog2(QUEUE_ENTRY_LIMIT);
	localparam integer ENTRY_COUNT_WIDTH = $clog2(QUEUE_ENTRY_LIMIT + 1);

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
	logic fault;
	logic [3:0] fault_code;

	logic [lpu_qctl_pkg::QCTL_RECORD_WIDTH-1:0] record_0;
	logic [lpu_qctl_pkg::QCTL_RECORD_WIDTH-1:0] record_1;
	logic [lpu_qctl_pkg::QCTL_RECORD_WIDTH-1:0] record_2;

	lpu_qctl_shared_pool #(
		.POOL_DEPTH(POOL_DEPTH),
		.QUEUE_COUNT(QUEUE_COUNT),
		.QUEUE_ENTRY_LIMIT(QUEUE_ENTRY_LIMIT),
		.READ_LATENCY(READ_LATENCY),
		.GENERATION_WIDTH(GENERATION_WIDTH)
	) u_dut (
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
		.fault_o(fault),
		.fault_code_o(fault_code)
	);

	task automatic write_record(
		input logic [POOL_ADDRESS_WIDTH-1:0] address,
		input logic [lpu_qctl_pkg::QCTL_RECORD_WIDTH-1:0] data
	);
		begin
			@(negedge clk);
			load_valid = 1'b1;
			load_address = address;
			load_data = data;
			@(posedge clk);
			#1ns;
			if(!load_ready)begin
				$fatal(1, "QCTL load was not accepted");
			end
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
			partition_valid = 1'b1;
			partition_queue = queue_id;
			partition_base = base;
			partition_count = count;
			partition_generation = generation;
			@(posedge clk);
			#1ns;
			if(!partition_ready)begin
				$fatal(1, "QCTL partition was not accepted");
			end
			@(negedge clk);
			partition_valid = 1'b0;
		end
	endtask

	initial begin
		clk = 1'b0;
		forever #5ns clk = ~clk;
	end

	initial begin
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
		request_valid = '0;
		request_index = '0;
		request_generation = '0;
		record_0 = lpu_qctl_pkg::qctl_pack_record(32'd3, lpu_qctl_pkg::QCTL_OPCODE_WAIT_EVENT, 32'd10);
		record_1 = lpu_qctl_pkg::qctl_pack_record(32'd5, lpu_qctl_pkg::QCTL_OPCODE_NOTIFY, 32'd0);
		record_2 = lpu_qctl_pkg::qctl_pack_record(32'd7, lpu_qctl_pkg::QCTL_OPCODE_MEM_PACKET, 32'd21);

		repeat (3) @(posedge clk);
		@(negedge clk);
		rst_n = 1'b1;

		write_record(0, record_0);
		write_record(1, record_1);
		write_record(2, record_2);
		configure_partition(0, 0, 2, 8'd1);
		configure_partition(1, 2, 1, 8'd1);
		if(fault)begin
			$fatal(1, "valid QCTL load/configuration faulted code=%0d", fault_code);
		end

		@(negedge clk);
		load_mode = 1'b0;
		request_valid[0] = 1'b1;
		request_valid[1] = 1'b1;
		request_index[0*ENTRY_INDEX_WIDTH+:ENTRY_INDEX_WIDTH] = 0;
		request_index[1*ENTRY_INDEX_WIDTH+:ENTRY_INDEX_WIDTH] = 0;
		request_generation[0*GENERATION_WIDTH+:GENERATION_WIDTH] = 8'd1;
		request_generation[1*GENERATION_WIDTH+:GENERATION_WIDTH] = 8'd1;
		#1ns;
		if(request_ready != 3'b001)begin
			$fatal(1, "round-robin did not first grant Queue 0: %b", request_ready);
		end
		@(posedge clk);
		#1ns;
		if(response_valid)begin
			$fatal(1, "Queue 0 response arrived before the configured latency");
		end

		@(negedge clk);
		request_valid[0] = 1'b0;
		#1ns;
		if(request_ready != 3'b010)begin
			$fatal(1, "round-robin did not next grant Queue 1: %b", request_ready);
		end
		@(posedge clk);
		#1ns;
		if(response_valid)begin
			$fatal(1, "Queue 0 response arrived after only one cycle");
		end

		@(negedge clk);
		request_valid[1] = 1'b0;
		@(posedge clk);
		#1ns;
		if(!response_valid || response_queue != 0 || response_error || response_data != record_0)begin
			$fatal(1, "Queue 0 two-cycle response mismatch");
		end
		@(posedge clk);
		#1ns;
		if(!response_valid || response_queue != 1 || response_error || response_data != record_2)begin
			$fatal(1, "Queue 1 arbitrated response mismatch");
		end
		@(posedge clk);
		#1ns;
		if(response_valid)begin
			$fatal(1, "QCTL response repeated");
		end

		// A stale task generation is accepted by the arbiter but returns an explicit error and sticky fault.
		@(negedge clk);
		request_valid[0] = 1'b1;
		request_index[0*ENTRY_INDEX_WIDTH+:ENTRY_INDEX_WIDTH] = 1;
		request_generation[0*GENERATION_WIDTH+:GENERATION_WIDTH] = 8'd0;
		#1ns;
		if(request_ready != 3'b001)begin
			$fatal(1, "stale-generation request did not reach the pool");
		end
		@(posedge clk);
		@(negedge clk);
		request_valid[0] = 1'b0;
		repeat (2) @(posedge clk);
		#1ns;
		if(!response_valid || response_queue != 0 || !response_error || !fault || fault_code != 4'd4)begin
			$fatal(1, "stale-generation request was not rejected correctly");
		end

		$display("LPU_QCTL_SHARED_POOL_TB_PASS");
		$finish;
	end
endmodule
