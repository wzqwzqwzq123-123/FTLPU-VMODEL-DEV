module lpu_qctl_controller_tb;
	logic clk_i;
	logic rst_ni;
	logic clear_i;
	logic configure_valid_i;
	logic run_i;
	logic configured_i;
	logic primed_i;
	logic done_i;
	logic [31:0] scheduler_cycle_i;
	logic scheduler_counter_ce_o;
	logic head_valid_i;
	logic [95:0] head_record_i;
	logic head_retire_o;
	logic sync_arrive_valid_o;
	logic sync_release_valid_i;
	logic notify_valid_o;
	logic notify_ready_i;
	logic event_valid_i;
	logic [31:0] event_tag_i;
	logic mem_packet_valid_o;
	logic [31:0] mem_packet_ordinal_o;
	logic mem_packet_retired_i;
	logic wait_event_blocked_o;
	logic [31:0] wait_event_tag_o;
	logic fault_o;
	logic [3:0] fault_code_o;
	integer errors;

	lpu_qctl_controller dut (.*);

	always #5 clk_i = ~clk_i;
	always_ff @(posedge clk_i or negedge rst_ni) begin
		if(!rst_ni)begin
			scheduler_cycle_i <= '0;
		end
		else if(clear_i || configure_valid_i)begin
			scheduler_cycle_i <= '0;
		end
		else if(scheduler_counter_ce_o)begin
			scheduler_cycle_i <= scheduler_cycle_i + 1'b1;
		end
	end

	task automatic check(input logic condition, input string message);
		begin
			if(!condition)begin
				$display("ERROR %s", message);
				errors = errors + 1;
			end
		end
	endtask

	task automatic restart(input logic [95:0] record);
		begin
			@(negedge clk_i);
			clear_i = 1'b1;
			@(negedge clk_i);
			clear_i = 1'b0;
			configure_valid_i = 1'b1;
			head_record_i = record;
			head_valid_i = 1'b1;
			@(negedge clk_i);
			configure_valid_i = 1'b0;
		end
	endtask

	initial begin
		clk_i = 1'b0;
		rst_ni = 1'b0;
		clear_i = 1'b0;
		configure_valid_i = 1'b0;
		run_i = 1'b1;
		configured_i = 1'b1;
		primed_i = 1'b1;
		done_i = 1'b0;
		head_valid_i = 1'b0;
		head_record_i = '0;
		sync_release_valid_i = 1'b0;
		notify_ready_i = 1'b0;
		event_valid_i = 1'b0;
		event_tag_i = '0;
		mem_packet_retired_i = 1'b0;
		errors = 0;
		repeat(2) @(posedge clk_i);
		rst_ni = 1'b1;

		// EVENT_WAIT stops on the exact boundary and ignores nonmatching TAGs.
		restart(lpu_qctl_pkg::qctl_pack_record(32'd3,
			lpu_qctl_pkg::QCTL_OPCODE_WAIT_EVENT, 32'h11));
		wait(scheduler_cycle_i == 3);
		#1;
		check(!scheduler_counter_ce_o && wait_event_blocked_o,
			"EVENT_WAIT blocks without a one-cycle slip");
		check(wait_event_tag_o == 32'h11, "EVENT_WAIT exposes requested TAG");
		@(negedge clk_i);
		event_valid_i = 1'b1;
		event_tag_i = 32'h22;
		#1;
		check(!head_retire_o, "nonmatching TAG does not retire");
		@(negedge clk_i);
		event_tag_i = 32'h11;
		#1;
		check(head_retire_o, "matching TAG retires EVENT_WAIT");
		event_valid_i = 1'b0;
		head_valid_i = 1'b0;
		$display("QCTL_EVENT_WAIT PASS");

		// SYNC remains arrived until the registered barrier release is observed.
		restart(lpu_qctl_pkg::qctl_pack_record(32'd0,
			lpu_qctl_pkg::QCTL_OPCODE_SYNC, 32'd0));
		#1;
		check(sync_arrive_valid_o && !scheduler_counter_ce_o,
			"SYNC enters wait and freezes cycle zero");
		@(posedge clk_i);
		#1;
		check(sync_arrive_valid_o && !head_retire_o, "SYNC request persists");
		@(negedge clk_i);
		sync_release_valid_i = 1'b1;
		#1;
		check(head_retire_o, "SYNC retires only on release");
		@(negedge clk_i);
		sync_release_valid_i = 1'b0;
		head_valid_i = 1'b0;
		$display("QCTL_SYNC_WAIT PASS");

		// An early NOTIFY request is held; ready completes it exactly once.
		restart(lpu_qctl_pkg::qctl_pack_record(32'd0,
			lpu_qctl_pkg::QCTL_OPCODE_NOTIFY, 32'd0));
		#1;
		check(notify_valid_o && !head_retire_o && !scheduler_counter_ce_o,
			"NOTIFY persists before barrier ready");
		@(negedge clk_i);
		notify_ready_i = 1'b1;
		#1;
		check(head_retire_o, "NOTIFY retires on ready handshake");
		@(negedge clk_i);
		notify_ready_i = 1'b0;
		head_valid_i = 1'b0;
		$display("QCTL_NOTIFY_WAIT PASS");

		// MEM_PACKET keeps ordinal stable until transport retirement.
		restart(lpu_qctl_pkg::qctl_pack_record(32'd0,
			lpu_qctl_pkg::QCTL_OPCODE_MEM_PACKET, 32'd9));
		#1;
		check(mem_packet_valid_o && (mem_packet_ordinal_o == 9),
			"MEM_PACKET request and ordinal are valid");
		@(posedge clk_i);
		#1;
		check(mem_packet_valid_o && (mem_packet_ordinal_o == 9) &&
			!scheduler_counter_ce_o, "MEM_PACKET request remains stable");
		@(negedge clk_i);
		mem_packet_retired_i = 1'b1;
		#1;
		check(head_retire_o, "MEM_PACKET retires on transport completion");
		@(negedge clk_i);
		mem_packet_retired_i = 1'b0;
		head_valid_i = 1'b0;
		$display("QCTL_MEMPACKET_WAIT PASS");

		if(errors == 0)begin
			$display("QCTL_CONTROLLER_TB PASS");
		end
		else begin
			$fatal(1, "QCTL_CONTROLLER_TB FAIL errors=%0d", errors);
		end
		$finish;
	end
endmodule
