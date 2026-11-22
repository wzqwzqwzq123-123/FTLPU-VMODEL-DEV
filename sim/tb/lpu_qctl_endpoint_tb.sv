`timescale 1ns/1ps

module lpu_qctl_endpoint_tb;
	logic clk_i;
	logic rst_ni;
	logic clear_i;
	logic run_i;
	logic configure_valid_i;
	logic [4:0] configure_count_i;
	logic [7:0] configure_generation_i;
	logic [3:0] store_head_index_o;
	logic [7:0] store_head_generation_o;
	logic store_loaded_i;
	logic store_head_valid_i;
	logic [95:0] store_head_record_i;
	logic store_head_error_i;
	logic [31:0] scheduler_cycle_i;
	logic scheduler_counter_ce_o;
	logic event_valid_i;
	logic [31:0] event_tag_i;
	logic event_wait_o;
	logic event_consume_o;
	logic sync_arrive_valid_o;
	logic sync_release_valid_i;
	logic notify_valid_o;
	logic notify_ready_i;
	logic mem_packet_valid_o;
	logic [31:0] mem_packet_ordinal_o;
	logic mem_packet_retired_i;
	logic configured_o;
	logic primed_o;
	logic done_o;
	logic fault_o;
	logic [3:0] fault_code_o;
	integer errors;

	lpu_qctl_endpoint #(
		.QUEUE_ENTRY_LIMIT(16), .GENERATION_WIDTH(8)
	) dut (.*);

	always #5 clk_i = ~clk_i;

	task automatic check(input logic condition, input string message);
		if(!condition)begin
			$display("ERROR %s", message);
			errors = errors + 1;
		end
	endtask

	task automatic configure_queue(input logic [4:0] count, input logic [7:0] generation);
		begin
			@(negedge clk_i);
			configure_count_i = count;
			configure_generation_i = generation;
			configure_valid_i = 1'b1;
			@(negedge clk_i);
			configure_valid_i = 1'b0;
		end
	endtask

	initial begin
		clk_i = 1'b0;
		rst_ni = 1'b0;
		clear_i = 1'b0;
		run_i = 1'b0;
		configure_valid_i = 1'b0;
		configure_count_i = '0;
		configure_generation_i = '0;
		store_loaded_i = 1'b0;
		store_head_valid_i = 1'b0;
		store_head_record_i = '0;
		store_head_error_i = 1'b0;
		scheduler_cycle_i = '0;
		event_valid_i = 1'b0;
		event_tag_i = '0;
		sync_release_valid_i = 1'b0;
		notify_ready_i = 1'b1;
		mem_packet_retired_i = 1'b0;
		errors = 0;
		repeat(3) @(posedge clk_i);
		rst_ni = 1'b1;

		// A zero-count Queue is already done and never requests a storage Head.
		store_loaded_i = 1'b1;
		configure_queue(0, 8'h1);
		run_i = 1'b1;
		repeat(2) @(posedge clk_i);
		check(configured_o && primed_o && done_o && !fault_o,
			"Count-zero Queue completes without a read or fault");

		// A configured Queue with an invalid expected Record faults during RUN.
		@(negedge clk_i);
		clear_i = 1'b1;
		@(negedge clk_i);
		clear_i = 1'b0;
		run_i = 1'b0;
		store_loaded_i = 1'b0;
		store_head_error_i = 1'b1;
		configure_queue(1, 8'h2);
		run_i = 1'b1;
		@(posedge clk_i);
		#1;
		check(fault_o && (fault_code_o == 4'd2),
			"invalid expected Record produces an explicit RUN-time store fault");
		check(!scheduler_counter_ce_o,
			"invalid expected Record cannot advance the Scheduler boundary");

		if(errors == 0)begin
			$display("QCTL_ENDPOINT_TB PASS");
		end
		else begin
			$fatal(1, "QCTL_ENDPOINT_TB FAIL errors=%0d", errors);
		end
		$finish;
	end
endmodule
