`timescale 1ns/1ps

module lpu_qctl_global_subsystem_tb;
	localparam integer QUEUE_COUNT = 228;
	localparam integer TOTAL_CAPACITY = 32;
	localparam integer QUEUE_ENTRY_LIMIT = 16;
	localparam integer GENERATION_WIDTH = 8;
	localparam integer ENTRY_INDEX_WIDTH = 4;
	localparam integer ENTRY_COUNT_WIDTH = 5;
	localparam integer ADDRESS_WIDTH = 5;
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
	logic event_in_valid_i;
	logic event_in_ready_o;
	logic [31:0] event_in_tag_i;
	logic [QUEUE_COUNT-1:0] event_in_target_mask_i;
	logic event_backpressure_o;
	logic [QUEUE_COUNT-1:0] endpoint_event_wait_i;
	logic [QUEUE_COUNT-1:0] endpoint_event_consume_i;
	logic [QUEUE_COUNT-1:0] endpoint_event_valid_o;
	logic [31:0] endpoint_event_tag_o;
	logic [QUEUE_COUNT-1:0] sync_participant_mask_i;
	logic [QUEUE_COUNT-1:0] endpoint_sync_arrive_valid_i;
	logic [QUEUE_COUNT-1:0] endpoint_notify_valid_i;
	logic [QUEUE_COUNT-1:0] endpoint_notify_ready_o;
	logic [QUEUE_COUNT-1:0] endpoint_sync_release_valid_o;
	logic [QUEUE_COUNT-1:0] endpoint_mem_packet_valid_i;
	logic [QUEUE_COUNT*32-1:0] endpoint_mem_packet_ordinal_i;
	logic [QUEUE_COUNT-1:0] mem_packet_valid_o;
	logic [QUEUE_COUNT*32-1:0] mem_packet_ordinal_o;
	logic [QUEUE_COUNT-1:0] mem_packet_retired_i;
	logic [QUEUE_COUNT-1:0] endpoint_mem_packet_retired_o;
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
	integer errors;

	lpu_qctl_global_subsystem #(
		.TOTAL_CAPACITY(TOTAL_CAPACITY), .QUEUE_COUNT(QUEUE_COUNT),
		.QUEUE_ENTRY_LIMIT(QUEUE_ENTRY_LIMIT), .EVENT_DEPTH(2),
		.REGION_DEPTH(8), .RELAY_BUFFER_DEPTH(2),
		.GENERATION_WIDTH(GENERATION_WIDTH)
	) dut (.*);

	always #5 clk_i = ~clk_i;

	task automatic check(input logic condition, input string message);
		if(!condition)begin
			$display("ERROR %s", message);
			errors = errors + 1;
		end
	endtask

	task automatic configure_queue(
		input logic [7:0] queue_id,
		input logic [ADDRESS_WIDTH-1:0] base,
		input logic [ENTRY_COUNT_WIDTH-1:0] count,
		input logic [GENERATION_WIDTH-1:0] generation
	);
		begin
			@(negedge clk_i);
			partition_valid_i = 1'b1;
			partition_queue_i = queue_id;
			partition_base_i = base;
			partition_count_i = count;
			partition_generation_i = generation;
			while(!partition_ready_o)begin
				@(negedge clk_i);
			end
			@(negedge clk_i);
			partition_valid_i = 1'b0;
		end
	endtask

	task automatic write_record(
		input logic [ADDRESS_WIDTH-1:0] address,
		input logic [95:0] data
	);
		begin
			@(negedge clk_i);
			load_valid_i = 1'b1;
			load_address_i = address;
			load_data_i = data;
			while(!load_ready_o)begin
				@(negedge clk_i);
			end
			@(negedge clk_i);
			load_valid_i = 1'b0;
		end
	endtask

	task automatic set_reader(
		input integer queue_id,
		input logic [ENTRY_INDEX_WIDTH-1:0] offset,
		input logic [GENERATION_WIDTH-1:0] generation
	);
		begin
			endpoint_head_index_i[queue_id*ENTRY_INDEX_WIDTH+:ENTRY_INDEX_WIDTH] = offset;
			endpoint_head_generation_i[queue_id*GENERATION_WIDTH+:GENERATION_WIDTH] = generation;
		end
	endtask

	initial begin
		clk_i = 1'b0;
		rst_ni = 1'b0;
		clear_i = 1'b0;
		load_mode_i = 1'b1;
		partition_valid_i = 1'b0;
		partition_queue_i = '0;
		partition_base_i = '0;
		partition_count_i = '0;
		partition_generation_i = '0;
		load_valid_i = 1'b0;
		load_address_i = '0;
		load_data_i = '0;
		endpoint_head_index_i = '0;
		endpoint_head_generation_i = '0;
		event_in_valid_i = 1'b0;
		event_in_tag_i = '0;
		event_in_target_mask_i = '0;
		endpoint_event_wait_i = '0;
		endpoint_event_consume_i = '0;
		sync_participant_mask_i = '0;
		endpoint_sync_arrive_valid_i = '0;
		endpoint_notify_valid_i = '0;
		endpoint_mem_packet_valid_i = '0;
		endpoint_mem_packet_ordinal_i = '0;
		mem_packet_retired_i = '0;
		endpoint_configured_i = '0;
		endpoint_primed_i = '0;
		endpoint_done_i = '0;
		endpoint_fault_i = '0;
		endpoint_fault_code_i = '0;
		errors = 0;
		repeat(3) @(posedge clk_i);
		rst_ni = 1'b1;

		// Cover East R0/R1/R6, West R0/R6 and MXM outer Queue mappings.
		configure_queue(8'd0, 5'd0, 5'd2, 8'h1);
		configure_queue(8'd16, 5'd2, 5'd1, 8'h1);
		configure_queue(8'd103, 5'd3, 5'd1, 8'h1);
		configure_queue(8'd104, 5'd4, 5'd1, 8'h1);
		configure_queue(8'd208, 5'd5, 5'd1, 8'h1);
		configure_queue(8'd210, 5'd6, 5'd1, 8'h1);
		configure_queue(8'd220, 5'd7, 5'd1, 8'h1);
		configure_queue(8'd226, 5'd8, 5'd1, 8'h1);

		set_reader(0, 0, 8'h1);
		set_reader(16, 0, 8'h1);
		set_reader(103, 0, 8'h1);
		set_reader(104, 0, 8'h1);
		set_reader(208, 0, 8'h1);
		set_reader(210, 0, 8'h1);
		set_reader(220, 0, 8'h1);
		set_reader(226, 0, 8'h1);

		write_record(5'd0, lpu_qctl_pkg::qctl_pack_record(3,
			lpu_qctl_pkg::QCTL_OPCODE_SYNC, 0));
		write_record(5'd2, lpu_qctl_pkg::qctl_pack_record(4,
			lpu_qctl_pkg::QCTL_OPCODE_WAIT_EVENT, 32'h16));
		write_record(5'd3, lpu_qctl_pkg::qctl_pack_record(5,
			lpu_qctl_pkg::QCTL_OPCODE_MEM_PACKET, 32'h103));
		write_record(5'd4, lpu_qctl_pkg::qctl_pack_record(6,
			lpu_qctl_pkg::QCTL_OPCODE_NOTIFY, 0));
		write_record(5'd5, lpu_qctl_pkg::qctl_pack_record(7,
			lpu_qctl_pkg::QCTL_OPCODE_WAIT_EVENT, 32'h208));
		write_record(5'd6, lpu_qctl_pkg::qctl_pack_record(8,
			lpu_qctl_pkg::QCTL_OPCODE_MEM_PACKET, 32'h210));
		write_record(5'd7, lpu_qctl_pkg::qctl_pack_record(10,
			lpu_qctl_pkg::QCTL_OPCODE_WAIT_EVENT, 32'h220));
		write_record(5'd8, lpu_qctl_pkg::qctl_pack_record(11,
			lpu_qctl_pkg::QCTL_OPCODE_NOTIFY, 32'h226));
		repeat(20) @(posedge clk_i);
		check(!load_complete_o, "missing Queue 0 Offset 1 blocks global load complete");
		check(!endpoint_store_loaded_o[0], "incomplete Queue valid bitmap remains not loaded");

		write_record(5'd1, lpu_qctl_pkg::qctl_pack_record(9,
			lpu_qctl_pkg::QCTL_OPCODE_WAIT_EVENT, 32'h01));
		wait(load_complete_o);
		#1;
		check(endpoint_head_valid_o[0] && endpoint_head_valid_o[16] &&
			endpoint_head_valid_o[103] && endpoint_head_valid_o[104] &&
			endpoint_head_valid_o[208] && endpoint_head_valid_o[210] &&
			endpoint_head_valid_o[220] && endpoint_head_valid_o[226],
			"multiple regional Queue ports read concurrently without arbitration");
		check(endpoint_head_record_o[16*96+:96] ==
			lpu_qctl_pkg::qctl_pack_record(4, lpu_qctl_pkg::QCTL_OPCODE_WAIT_EVENT, 32'h16),
			"multi-Relay routing preserves the Queue 16 Record");
		check(endpoint_head_record_o[210*96+:96] ==
			lpu_qctl_pkg::qctl_pack_record(8, lpu_qctl_pkg::QCTL_OPCODE_MEM_PACKET, 32'h210),
			"West final Relay stores the MXM Queue Record");
		check(endpoint_head_record_o[220*96+:96] ==
			lpu_qctl_pkg::qctl_pack_record(10, lpu_qctl_pkg::QCTL_OPCODE_WAIT_EVENT, 32'h220),
			"East final Relay stores the MXM Param Load Queue Record");
		check(endpoint_head_record_o[226*96+:96] ==
			lpu_qctl_pkg::qctl_pack_record(11, lpu_qctl_pkg::QCTL_OPCODE_NOTIFY, 32'h226),
			"West final Relay stores the MXM Backend Queue Record");

		set_reader(0, 1, 8'h1);
		#1;
		check(endpoint_head_valid_o[0] &&
			(endpoint_head_record_o[0+:96] == lpu_qctl_pkg::qctl_pack_record(9,
			 lpu_qctl_pkg::QCTL_OPCODE_WAIT_EVENT, 32'h01)),
			"local base plus Queue offset selects the second Record");

		// Program Clear invalidates stale storage without resetting the Record array.
		@(negedge clk_i);
		clear_i = 1'b1;
		@(negedge clk_i);
		clear_i = 1'b0;
		configure_queue(8'd0, 5'd0, 5'd1, 8'h2);
		set_reader(0, 0, 8'h2);
		repeat(4) @(posedge clk_i);
		check(!endpoint_store_loaded_o[0] && !endpoint_head_valid_o[0],
			"cleared Valid Bitmap blocks stale Record reuse");
		write_record(5'd0, lpu_qctl_pkg::qctl_pack_record(1,
			lpu_qctl_pkg::QCTL_OPCODE_SYNC, 0));
		wait(load_complete_o);

		// A duplicate Offset is consumed once and reported as a sticky Relay fault.
		write_record(5'd0, lpu_qctl_pkg::qctl_pack_record(2,
			lpu_qctl_pkg::QCTL_OPCODE_NOTIFY, 0));
		wait(fault_o);
		check(fault_code_o[7:4] == 4'h4, "duplicate East Record reports Relay fault");

		// Logical Partition ranges must remain disjoint in the Load Manager.
		@(negedge clk_i);
		clear_i = 1'b1;
		@(negedge clk_i);
		clear_i = 1'b0;
		configure_queue(8'd0, 5'd0, 5'd2, 8'h3);
		configure_queue(8'd1, 5'd1, 5'd2, 8'h3);
		wait(fault_o);
		check(fault_code_o == 8'h12, "overlapping logical Partitions fault in Load Manager");

		// Regional allocation failure is reported instead of silently dropping a Queue.
		@(negedge clk_i);
		clear_i = 1'b1;
		@(negedge clk_i);
		clear_i = 1'b0;
		configure_queue(8'd0, 5'd0, 5'd8, 8'h4);
		configure_queue(8'd1, 5'd8, 5'd1, 8'h4);
		wait(fault_o);
		check(fault_code_o == 8'h42, "East Relay regional capacity overflow faults explicitly");

		// Invalid Queue IDs and address-end overflow are consumed once and faulted.
		@(negedge clk_i);
		clear_i = 1'b1;
		@(negedge clk_i);
		clear_i = 1'b0;
		configure_queue(8'd228, 5'd0, 5'd0, 8'h5);
		wait(fault_o);
		check(fault_code_o == 8'h11, "unmapped Queue ID faults before Relay routing");
		@(negedge clk_i);
		clear_i = 1'b1;
		@(negedge clk_i);
		clear_i = 1'b0;
		configure_queue(8'd0, 5'd31, 5'd2, 8'h6);
		wait(fault_o);
		check(fault_code_o == 8'h11, "Base plus Count overflow faults before array access");

		if(errors == 0)begin
			$display("QCTL_GLOBAL_SUBSYSTEM_TB PASS");
		end
		else begin
			$fatal(1, "QCTL_GLOBAL_SUBSYSTEM_TB FAIL errors=%0d", errors);
		end
		$finish;
	end
endmodule
