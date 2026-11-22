`timescale 1ns/1ps

module lpu_qctl_event_buffer_tb;
	localparam integer QUEUE_COUNT = 4;
	localparam integer EVENT_DEPTH = 2;
	logic clk_i;
	logic rst_ni;
	logic clear_i;
	logic event_in_valid_i;
	logic event_in_ready_o;
	logic [31:0] event_in_tag_i;
	logic [QUEUE_COUNT-1:0] event_in_target_mask_i;
	logic [QUEUE_COUNT-1:0] event_wait_i;
	logic [QUEUE_COUNT-1:0] event_consume_i;
	logic [QUEUE_COUNT-1:0] event_valid_o;
	logic [31:0] event_tag_o;
	logic fault_o;
	logic [3:0] fault_code_o;
	integer errors;

	lpu_qctl_event_buffer #(
		.QUEUE_COUNT(QUEUE_COUNT), .EVENT_DEPTH(EVENT_DEPTH)
	) dut (.*);

	always #5 clk_i = ~clk_i;

	task automatic check(input logic condition, input string message);
		if(!condition)begin
			$display("ERROR %s", message);
			errors = errors + 1;
		end
	endtask

	task automatic push_event(input logic [31:0] tag, input logic [QUEUE_COUNT-1:0] mask);
		begin
			@(negedge clk_i);
			event_in_valid_i = 1'b1;
			event_in_tag_i = tag;
			event_in_target_mask_i = mask;
			while(!event_in_ready_o)begin
				@(negedge clk_i);
			end
			@(negedge clk_i);
			event_in_valid_i = 1'b0;
		end
	endtask

	initial begin
		clk_i = 1'b0;
		rst_ni = 1'b0;
		clear_i = 1'b0;
		event_in_valid_i = 1'b0;
		event_in_tag_i = '0;
		event_in_target_mask_i = '0;
		event_wait_i = '0;
		event_consume_i = '0;
		errors = 0;
		repeat(2) @(posedge clk_i);
		rst_ni = 1'b1;

		// Early event remains pending until both independent consumers acknowledge.
		push_event(32'h55, 4'b0011);
		event_wait_i = 4'b0001;
		#1;
		check(event_valid_o == 4'b0001 && event_tag_o == 32'h55,
			"early event becomes visible to first target");
		event_consume_i = 4'b0001;
		@(posedge clk_i);
		event_consume_i = '0;
		event_wait_i = 4'b0010;
		#1;
		check(event_valid_o == 4'b0010 && event_tag_o == 32'h55,
			"pending mask preserves later consumer");
		event_consume_i = 4'b0010;
		@(posedge clk_i);
		event_consume_i = '0;
		#1;
		check(event_valid_o == '0, "event retires after final consumer");

		// Repeated equal TAGs occupy separate ordered entries.
		event_wait_i = 4'b0100;
		push_event(32'h77, 4'b0100);
		push_event(32'h77, 4'b0100);
		#1;
		check(!event_in_ready_o, "full buffer applies backpressure");
		event_consume_i = 4'b0100;
		@(posedge clk_i);
		event_consume_i = '0;
		#1;
		check(event_valid_o == 4'b0100 && event_tag_o == 32'h77,
			"second equal TAG remains after first retires");
		event_consume_i = 4'b0100;
		@(posedge clk_i);
		event_consume_i = '0;

		if(errors == 0)begin
			$display("QCTL_EVENT_BUFFER_TB PASS");
		end
		else begin
			$fatal(1, "QCTL_EVENT_BUFFER_TB FAIL errors=%0d", errors);
		end
		$finish;
	end
endmodule
