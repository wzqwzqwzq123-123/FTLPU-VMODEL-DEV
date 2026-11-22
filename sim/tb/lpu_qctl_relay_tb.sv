`timescale 1ns/1ps

module lpu_qctl_relay_tb;
	localparam integer QUEUE_COUNT = 228;
	localparam integer ENTRY_INDEX_WIDTH = 4;
	localparam integer ENTRY_COUNT_WIDTH = 5;
	localparam integer GENERATION_WIDTH = 8;
	logic clk_i;
	logic rst_ni;
	logic clear_i;
	logic chain_packet_valid_i;
	logic chain_packet_ready_o;
	logic chain_packet_kind_i;
	logic [7:0] chain_packet_queue_i;
	logic [ENTRY_INDEX_WIDTH-1:0] chain_packet_offset_i;
	logic [ENTRY_COUNT_WIDTH-1:0] chain_packet_count_i;
	logic [GENERATION_WIDTH-1:0] chain_packet_generation_i;
	logic [95:0] chain_packet_record_i;
	logic next_packet_valid_o;
	logic next_packet_ready_i;
	logic next_packet_kind_o;
	logic [7:0] next_packet_queue_o;
	logic [ENTRY_INDEX_WIDTH-1:0] next_packet_offset_o;
	logic [ENTRY_COUNT_WIDTH-1:0] next_packet_count_o;
	logic [GENERATION_WIDTH-1:0] next_packet_generation_o;
	logic [95:0] next_packet_record_o;
	logic [QUEUE_COUNT*ENTRY_INDEX_WIDTH-1:0] queue_head_index_i;
	logic [QUEUE_COUNT*GENERATION_WIDTH-1:0] queue_head_generation_i;
	logic [QUEUE_COUNT-1:0] queue_configured_o;
	logic [QUEUE_COUNT-1:0] queue_loaded_o;
	logic [QUEUE_COUNT-1:0] queue_head_valid_o;
	logic [QUEUE_COUNT*96-1:0] queue_head_record_o;
	logic [QUEUE_COUNT-1:0] queue_head_error_o;
	logic [QUEUE_COUNT-1:0] configure_valid_o;
	logic [QUEUE_COUNT*ENTRY_COUNT_WIDTH-1:0] configure_count_o;
	logic [QUEUE_COUNT*GENERATION_WIDTH-1:0] configure_generation_o;
	logic idle_o;
	logic fault_o;
	logic [3:0] fault_code_o;
	logic last_packet_valid_i;
	logic last_packet_ready_o;
	logic last_fault_o;
	logic [3:0] last_fault_code_o;
	integer errors;

	lpu_qctl_relay #(
		.HEMISPHERE_ID(0), .RELAY_INDEX(0), .LAST_RELAY(1'b0),
		.QUEUE_COUNT(QUEUE_COUNT), .LOCAL_QUEUE_COUNT(16), .REGION_DEPTH(8),
		.BUFFER_DEPTH(2), .QUEUE_ENTRY_LIMIT(16), .GENERATION_WIDTH(GENERATION_WIDTH)
	) dut (.*);

	// A terminal Relay instance verifies that an unroutable packet faults locally.
	lpu_qctl_relay #(
		.HEMISPHERE_ID(0), .RELAY_INDEX(0), .LAST_RELAY(1'b1),
		.QUEUE_COUNT(QUEUE_COUNT), .LOCAL_QUEUE_COUNT(16), .REGION_DEPTH(8),
		.BUFFER_DEPTH(2), .QUEUE_ENTRY_LIMIT(16), .GENERATION_WIDTH(GENERATION_WIDTH)
	) last_dut (
		.clk_i, .rst_ni, .clear_i,
		.chain_packet_valid_i(last_packet_valid_i),
		.chain_packet_ready_o(last_packet_ready_o),
		.chain_packet_kind_i(lpu_qctl_pkg::QCTL_RELAY_RECORD),
		.chain_packet_queue_i(8'd16),
		.chain_packet_offset_i('0), .chain_packet_count_i('0),
		.chain_packet_generation_i(8'h1), .chain_packet_record_i(96'h55),
		.next_packet_valid_o(), .next_packet_ready_i(1'b0),
		.next_packet_kind_o(), .next_packet_queue_o(), .next_packet_offset_o(),
		.next_packet_count_o(), .next_packet_generation_o(), .next_packet_record_o(),
		.queue_head_index_i('0), .queue_head_generation_i('0),
		.queue_configured_o(), .queue_loaded_o(), .queue_head_valid_o(),
		.queue_head_record_o(), .queue_head_error_o(), .configure_valid_o(),
		.configure_count_o(), .configure_generation_o(), .idle_o(),
		.fault_o(last_fault_o), .fault_code_o(last_fault_code_o)
	);

	always #5 clk_i = ~clk_i;

	task automatic check(input logic condition, input string message);
		if(!condition)begin
			$display("ERROR %s", message);
			errors = errors + 1;
		end
	endtask

	task automatic send_packet(
		input logic kind,
		input logic [7:0] queue_id,
		input logic [3:0] offset,
		input logic [4:0] count,
		input logic [7:0] generation,
		input logic [95:0] record
	);
		begin
			@(negedge clk_i);
			chain_packet_valid_i = 1'b1;
			chain_packet_kind_i = kind;
			chain_packet_queue_i = queue_id;
			chain_packet_offset_i = offset;
			chain_packet_count_i = count;
			chain_packet_generation_i = generation;
			chain_packet_record_i = record;
			while(!chain_packet_ready_o)begin
				@(negedge clk_i);
			end
			@(negedge clk_i);
			chain_packet_valid_i = 1'b0;
		end
	endtask

	initial begin
		clk_i = 1'b0;
		rst_ni = 1'b0;
		clear_i = 1'b0;
		chain_packet_valid_i = 1'b0;
		chain_packet_kind_i = '0;
		chain_packet_queue_i = '0;
		chain_packet_offset_i = '0;
		chain_packet_count_i = '0;
		chain_packet_generation_i = '0;
		chain_packet_record_i = '0;
		next_packet_ready_i = 1'b0;
		queue_head_index_i = '0;
		queue_head_generation_i = '0;
		last_packet_valid_i = 1'b0;
		errors = 0;
		repeat(3) @(posedge clk_i);
		rst_ni = 1'b1;

		// Two non-local packets fill the Transit FIFO while preserving order.
		send_packet(lpu_qctl_pkg::QCTL_RELAY_RECORD, 8'd16, 0, 0, 8'h1, 96'h1);
		send_packet(lpu_qctl_pkg::QCTL_RELAY_RECORD, 8'd16, 1, 0, 8'h1, 96'h2);
		@(negedge clk_i);
		chain_packet_valid_i = 1'b1;
		chain_packet_kind_i = lpu_qctl_pkg::QCTL_RELAY_RECORD;
		chain_packet_queue_i = 8'd16;
		chain_packet_offset_i = 2;
		chain_packet_generation_i = 8'h1;
		chain_packet_record_i = 96'h3;
		#1;
		check(!chain_packet_ready_o, "full Transit FIFO backpressures its upstream");
		check(next_packet_valid_o && (next_packet_record_o == 96'h1),
			"blocked downstream keeps the oldest packet stable");
		next_packet_ready_i = 1'b1;
		@(posedge clk_i);
		@(negedge clk_i);
		check(next_packet_valid_o && (next_packet_record_o == 96'h2),
			"Transit FIFO preserves non-local packet order");
		chain_packet_valid_i = 1'b0;
		repeat(3) @(posedge clk_i);

		// Clear removes transit and regional validity without resetting Record RAM.
		@(negedge clk_i);
		clear_i = 1'b1;
		@(negedge clk_i);
		clear_i = 1'b0;
		next_packet_ready_i = 1'b0;
		send_packet(lpu_qctl_pkg::QCTL_RELAY_PARTITION, 8'd0, 0, 2, 8'h2, '0);
		queue_head_generation_i[0+:GENERATION_WIDTH] = 8'h2;
		#1;
		check(queue_configured_o[0] && !queue_loaded_o[0] && !queue_head_valid_o[0],
			"configured Queue remains unreadable until all expected Records arrive");
		send_packet(lpu_qctl_pkg::QCTL_RELAY_RECORD, 8'd0, 0, 0, 8'h2, 96'h11);
		#1;
		check(!queue_loaded_o[0], "one missing Offset keeps Queue incomplete");
		send_packet(lpu_qctl_pkg::QCTL_RELAY_RECORD, 8'd0, 1, 0, 8'h2, 96'h22);
		#1;
		check(queue_loaded_o[0] && queue_head_valid_o[0] &&
			(queue_head_record_o[0+:96] == 96'h11),
			"valid bitmap enables a complete local Queue and its Head");
		queue_head_index_i[0+:ENTRY_INDEX_WIDTH] = 1;
		#1;
		check(queue_head_valid_o[0] && (queue_head_record_o[0+:96] == 96'h22),
			"independent Queue reader selects the requested Offset");

		// Rewriting an already valid Offset is a protocol fault, not a loaded-count increment.
		send_packet(lpu_qctl_pkg::QCTL_RELAY_RECORD, 8'd0, 1, 0, 8'h2, 96'h33);
		wait(fault_o);
		check(fault_code_o == 4'd6, "duplicate Offset produces explicit Relay fault");

		// A stale-generation Record is consumed once and rejected explicitly.
		@(negedge clk_i);
		clear_i = 1'b1;
		@(negedge clk_i);
		clear_i = 1'b0;
		send_packet(lpu_qctl_pkg::QCTL_RELAY_PARTITION, 8'd0, 0, 1, 8'h3, '0);
		send_packet(lpu_qctl_pkg::QCTL_RELAY_RECORD, 8'd0, 0, 0, 8'h4, 96'h44);
		wait(fault_o);
		check(fault_code_o == 4'd4, "Generation mismatch produces explicit Relay fault");

		// Count zero is complete immediately but never exposes or reads a Head Record.
		@(negedge clk_i);
		clear_i = 1'b1;
		@(negedge clk_i);
		clear_i = 1'b0;
		send_packet(lpu_qctl_pkg::QCTL_RELAY_PARTITION, 8'd0, 0, 0, 8'h5, '0);
		queue_head_generation_i[0+:GENERATION_WIDTH] = 8'h5;
		#1;
		check(queue_configured_o[0] && queue_loaded_o[0] && !queue_head_valid_o[0],
			"Count-zero Queue completes without exposing a storage entry");

		// A terminal Relay must reject a packet that belongs farther down the chain.
		@(negedge clk_i);
		last_packet_valid_i = 1'b1;
		while(!last_packet_ready_o)begin
			@(negedge clk_i);
		end
		@(negedge clk_i);
		last_packet_valid_i = 1'b0;
		wait(last_fault_o);
		check(last_fault_code_o == 4'd7, "terminal Relay reports an explicit route fault");

		if(errors == 0)begin
			$display("QCTL_RELAY_TB PASS");
		end
		else begin
			$fatal(1, "QCTL_RELAY_TB FAIL errors=%0d", errors);
		end
		$finish;
	end
endmodule
