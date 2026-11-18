module lpu_qctl_system_tb;
	localparam integer QUEUE_COUNT = 6;
	localparam integer POOL_DEPTH = 16;
	localparam integer QUEUE_ENTRY_LIMIT = 4;
	logic clk_i;
	logic rst_ni;
	logic clear_i;
	logic run_i;
	logic load_mode_i;
	logic partition_valid_i;
	logic partition_ready_o;
	logic [2:0] partition_queue_i;
	logic [3:0] partition_base_i;
	logic [2:0] partition_count_i;
	logic [63:0] partition_generation_i;
	logic load_valid_i;
	logic load_ready_o;
	logic [3:0] load_address_i;
	logic [95:0] load_data_i;
	logic [QUEUE_COUNT-1:0] sync_participant_mask_i;
	logic event_valid_i;
	logic event_ready_o;
	logic [31:0] event_tag_i;
	logic [QUEUE_COUNT*32-1:0] scheduler_cycle_i;
	logic [QUEUE_COUNT-1:0] scheduler_counter_ce_o;
	logic [QUEUE_COUNT-1:0] mem_packet_valid_o;
	logic [QUEUE_COUNT*32-1:0] mem_packet_ordinal_o;
	logic [QUEUE_COUNT-1:0] mem_packet_retired_i;
	logic [QUEUE_COUNT-1:0] queue_active_o;
	logic [QUEUE_COUNT-1:0] wait_event_blocked_o;
	logic [QUEUE_COUNT*32-1:0] wait_event_tag_o;
	logic [QUEUE_COUNT-1:0] primed_o;
	logic [QUEUE_COUNT-1:0] done_o;
	logic [QUEUE_COUNT-1:0] sync_arrive_o;
	logic [QUEUE_COUNT-1:0] notify_pending_o;
	logic [QUEUE_COUNT-1:0] sync_release_o;
	logic all_primed_o;
	logic all_done_o;
	logic fault_o;
	logic [7:0] fault_code_o;
	integer errors;
	integer release_rounds;
	logic release_mask_error;

	lpu_qctl_system #(
		.POOL_DEPTH(POOL_DEPTH),
		.QUEUE_COUNT(QUEUE_COUNT),
		.QUEUE_ENTRY_LIMIT(QUEUE_ENTRY_LIMIT),
		.CACHE_DEPTH(2),
		.EVENT_DEPTH(4),
		.READ_LATENCY(2)
	) dut (.*);

	always #5 clk_i = ~clk_i;
	for(genvar queue_index = 0; queue_index < QUEUE_COUNT; queue_index++)begin
		always_ff @(posedge clk_i or negedge rst_ni) begin
			if(!rst_ni)begin
				scheduler_cycle_i[queue_index*32+:32] <= '0;
			end
			else if(clear_i || !queue_active_o[queue_index])begin
				scheduler_cycle_i[queue_index*32+:32] <= '0;
			end
			else if(scheduler_counter_ce_o[queue_index])begin
				scheduler_cycle_i[queue_index*32+:32] <=
					scheduler_cycle_i[queue_index*32+:32] + 1'b1;
			end
		end
	end

	always_ff @(posedge clk_i or negedge rst_ni) begin
		if(!rst_ni || clear_i)begin
			release_rounds <= 0;
			release_mask_error <= 1'b0;
		end
		else if(|sync_release_o)begin
			release_rounds <= release_rounds + 1;
			if(sync_release_o != sync_participant_mask_i)begin
				release_mask_error <= 1'b1;
			end
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

	task automatic configure_queue(
		input logic [2:0] queue_id,
		input logic [3:0] base_address,
		input logic [2:0] entry_count
	);
		begin
			@(negedge clk_i);
			partition_valid_i = 1'b1;
			partition_queue_i = queue_id;
			partition_base_i = base_address;
			partition_count_i = entry_count;
			partition_generation_i = 64'h100 + queue_id;
			@(posedge clk_i);
			@(negedge clk_i);
			partition_valid_i = 1'b0;
		end
	endtask

	task automatic write_record(input logic [3:0] address, input logic [95:0] record);
		begin
			@(negedge clk_i);
			load_valid_i = 1'b1;
			load_address_i = address;
			load_data_i = record;
			@(posedge clk_i);
			@(negedge clk_i);
			load_valid_i = 1'b0;
		end
	endtask

	initial begin
		clk_i = 1'b0;
		rst_ni = 1'b0;
		clear_i = 1'b0;
		run_i = 1'b0;
		load_mode_i = 1'b1;
		partition_valid_i = 1'b0;
		partition_queue_i = '0;
		partition_base_i = '0;
		partition_count_i = '0;
		partition_generation_i = '0;
		load_valid_i = 1'b0;
		load_address_i = '0;
		load_data_i = '0;
		sync_participant_mask_i = 6'b000111;
		event_valid_i = 1'b0;
		event_tag_i = '0;
		mem_packet_retired_i = '0;
		errors = 0;
		repeat(3) @(posedge clk_i);
		rst_ni = 1'b1;

		configure_queue(0, 0, 2);
		configure_queue(1, 2, 2);
		configure_queue(2, 4, 2);
		configure_queue(3, 6, 2);
		configure_queue(4, 8, 2);
		configure_queue(5, 10, 1);
		write_record(0, lpu_qctl_pkg::qctl_pack_record(0, lpu_qctl_pkg::QCTL_OPCODE_SYNC, 0));
		write_record(1, lpu_qctl_pkg::qctl_pack_record(1, lpu_qctl_pkg::QCTL_OPCODE_SYNC, 0));
		write_record(2, lpu_qctl_pkg::qctl_pack_record(1, lpu_qctl_pkg::QCTL_OPCODE_SYNC, 0));
		write_record(3, lpu_qctl_pkg::qctl_pack_record(2, lpu_qctl_pkg::QCTL_OPCODE_SYNC, 0));
		write_record(4, lpu_qctl_pkg::qctl_pack_record(2, lpu_qctl_pkg::QCTL_OPCODE_SYNC, 0));
		write_record(5, lpu_qctl_pkg::qctl_pack_record(3, lpu_qctl_pkg::QCTL_OPCODE_SYNC, 0));
		write_record(6, lpu_qctl_pkg::qctl_pack_record(0, lpu_qctl_pkg::QCTL_OPCODE_NOTIFY, 0));
		write_record(7, lpu_qctl_pkg::qctl_pack_record(1, lpu_qctl_pkg::QCTL_OPCODE_NOTIFY, 0));
		write_record(8, lpu_qctl_pkg::qctl_pack_record(0, lpu_qctl_pkg::QCTL_OPCODE_WAIT_EVENT, 32'h55));
		write_record(9, lpu_qctl_pkg::qctl_pack_record(0, lpu_qctl_pkg::QCTL_OPCODE_MEM_PACKET, 7));
		write_record(10, lpu_qctl_pkg::qctl_pack_record(0, lpu_qctl_pkg::QCTL_OPCODE_WAIT_EVENT, 32'h55));

		// Buffer an early DMA completion before any Controller enters EVENT_WAIT.
		@(negedge clk_i);
		event_valid_i = 1'b1;
		event_tag_i = 32'h55;
		#1;
		check(event_ready_o, "early event accepted by independent buffer");
		@(negedge clk_i);
		event_valid_i = 1'b0;
		load_mode_i = 1'b0;
		wait(all_primed_o);
		run_i = 1'b1;

		// Q3 NOTIFY reaches cycle zero before all three participants arrive.
		@(posedge clk_i);
		#1;
		check(notify_pending_o[3] && !done_o[3],
			"early NOTIFY remains pending without creating a token");
		wait(release_rounds == 1);
		wait(release_rounds == 2);
		check(!release_mask_error, "each round releases exactly the participant mask");

		repeat(20) @(posedge clk_i);
		check(done_o[5], "one buffered TAG releases every matching Controller");
		check(mem_packet_valid_o[4], "EVENT_WAIT advances to MEM_PACKET");
		if(!mem_packet_valid_o[4])begin
			$display("Q4_DEBUG cycle=%0d wait=%0b done=%0b fault=%0b code=%0h",
				scheduler_cycle_i[4*32+:32], wait_event_blocked_o[4],
				done_o[4], fault_o, fault_code_o);
		end
		check(mem_packet_ordinal_o[4*32+:32] == 7,
			"MEM_PACKET ordinal follows the event record");
		repeat(2) @(posedge clk_i);
		check(mem_packet_valid_o[4], "MEM_PACKET valid persists before retirement");
		@(negedge clk_i);
		mem_packet_retired_i[4] = 1'b1;
		@(posedge clk_i);
		@(negedge clk_i);
		mem_packet_retired_i[4] = 1'b0;
		wait(all_done_o);
		check(!fault_o, "Pool Cache Controller integration remains fault free");

		// Reset removes all arrival, release, event, and Queue-active state.
		@(negedge clk_i);
		rst_ni = 1'b0;
		@(posedge clk_i);
		#1;
		check((queue_active_o == '0) && (sync_arrive_o == '0) &&
			(sync_release_o == '0) && (notify_pending_o == '0),
			"reset clears Queue and barrier state");
		@(negedge clk_i);
		rst_ni = 1'b1;

		if(errors == 0)begin
			$display("QCTL_SYSTEM_TB PASS");
		end
		else begin
			$fatal(1, "QCTL_SYSTEM_TB FAIL errors=%0d fault=%0h", errors, fault_code_o);
		end
		$finish;
	end

	initial begin
		#20000;
		$display("TIMEOUT_DEBUG primed=%b active=%b done=%b cycles=%h",
			primed_o, queue_active_o, done_o, scheduler_cycle_i);
		$display("TIMEOUT_DEBUG request_valid=%b request_ready=%b response_valid=%b fault=%b code=%0h",
			dut.request_valid, dut.request_ready, dut.response_valid, fault_o, fault_code_o);
		$display("TIMEOUT_DEBUG arrive=%b notify=%b release=%b mask=%b stored_arrive=%b rounds=%0d",
			sync_arrive_o, notify_pending_o, sync_release_o,
			sync_participant_mask_i, dut.u_sync_fabric.sync_arrive_mask_q,
			release_rounds);
		$display("TIMEOUT_DEBUG state0=%0d state1=%0d headret=%b cachehead=%b",
			dut.gen_queue_endpoint[0].u_controller.state_q,
			dut.gen_queue_endpoint[1].u_controller.state_q,
			dut.head_retire, dut.head_valid);
		$fatal(1, "QCTL_SYSTEM_TB TIMEOUT");
	end
endmodule
