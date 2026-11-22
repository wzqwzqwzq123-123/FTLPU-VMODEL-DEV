`timescale 1ns/1ps

module lpu_qctl_fabric_tb;
	localparam integer QUEUE_COUNT = 4;
	logic clk_i;
	logic rst_ni;
	logic clear_i;
	logic event_in_valid_i;
	logic event_in_ready_i;
	logic event_backpressure_o;
	logic [QUEUE_COUNT-1:0] endpoint_event_wait_i;
	logic [QUEUE_COUNT-1:0] endpoint_event_consume_i;
	logic [QUEUE_COUNT-1:0] event_wait_o;
	logic [QUEUE_COUNT-1:0] event_consume_o;
	logic [QUEUE_COUNT-1:0] event_buffer_valid_i;
	logic [31:0] event_buffer_tag_i;
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
	logic fault_o;
	logic [3:0] fault_code_o;
	integer errors;

	lpu_qctl_fabric #(.QUEUE_COUNT(QUEUE_COUNT)) dut (.*);

	always #5 clk_i = ~clk_i;

	task automatic check(input logic condition, input string message);
		if(!condition)begin
			$display("ERROR %s", message);
			errors = errors + 1;
		end
	endtask

	initial begin
		clk_i = 1'b0;
		rst_ni = 1'b0;
		clear_i = 1'b0;
		event_in_valid_i = 1'b0;
		event_in_ready_i = 1'b1;
		endpoint_event_wait_i = '0;
		endpoint_event_consume_i = '0;
		event_buffer_valid_i = '0;
		event_buffer_tag_i = '0;
		sync_participant_mask_i = 4'b0011;
		endpoint_sync_arrive_valid_i = '0;
		endpoint_notify_valid_i = '0;
		endpoint_mem_packet_valid_i = '0;
		endpoint_mem_packet_ordinal_i = '0;
		mem_packet_retired_i = '0;
		errors = 0;
		repeat(2) @(posedge clk_i);
		rst_ni = 1'b1;

		endpoint_sync_arrive_valid_i = 4'b0001;
		endpoint_notify_valid_i = 4'b0100;
		#1;
		check(endpoint_notify_ready_o == '0, "partial arrival blocks NOTIFY");
		@(posedge clk_i);
		endpoint_sync_arrive_valid_i = 4'b0011;
		#1;
		check(endpoint_notify_ready_o == 4'b0100, "all participants enable one NOTIFY");
		@(posedge clk_i);
		#1;
		check(endpoint_sync_release_valid_o == 4'b0011,
			"successful NOTIFY releases all participants");
		endpoint_notify_valid_i = '0;
		endpoint_sync_arrive_valid_i = '0;
		@(posedge clk_i);
		#1;
		check(endpoint_sync_release_valid_o == '0, "release is one cycle");

		event_in_valid_i = 1'b1;
		event_in_ready_i = 1'b0;
		#1;
		check(event_backpressure_o, "event backpressure reports valid without ready");

		if(errors == 0)begin
			$display("QCTL_FABRIC_TB PASS");
		end
		else begin
			$fatal(1, "QCTL_FABRIC_TB FAIL errors=%0d", errors);
		end
		$finish;
	end
endmodule
