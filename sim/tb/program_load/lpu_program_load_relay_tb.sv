module lpu_program_load_relay_tb;
	import lpu_program_load_pkg::*;

	localparam integer MEM_SLICES_PER_HEMISPHERE = 52;
	localparam integer MEM_SLICES_PER_GROUP = 4;
	localparam integer BANKS_PER_SLICE = 2;
	localparam integer MEM_GROUPS_PER_RELAY = 2;
	localparam integer RELAY_INDEX = 2;
	localparam integer LOCAL_BANK_COUNT = 16;
	localparam integer LOCAL_BANK_BASE = 32;
	localparam integer EXPECTED_GROUP_COUNT = 13;
	localparam integer EXPECTED_RELAY_COUNT = 7;
	localparam integer EXPECTED_FINAL_RELAY_BANK_COUNT = 8;

	logic clk_i;
	logic rst_ni;
	logic input_valid_i;
	logic input_ready_o;
	logic [PROGRAM_LOAD_CONTROL_WIDTH-1:0] input_control_i;
	logic [127:0] input_data_i;
	logic [3:0] input_strb_i;
	logic [1:0] input_scope_i;
	logic [11:0] input_destination_i;
	logic [16:0] input_imem_address_i;
	logic input_last_i;

	logic [LOCAL_BANK_COUNT-1:0] local_valid_o;
	logic [LOCAL_BANK_COUNT-1:0] local_ready_i;
	logic [PROGRAM_LOAD_CONTROL_WIDTH-1:0] local_control_o;
	logic [127:0] local_data_o;
	logic [3:0] local_strb_o;
	logic [1:0] local_scope_o;
	logic [11:0] local_destination_o;
	logic [16:0] local_imem_address_o;
	logic local_last_o;

	logic forward_valid_o;
	logic forward_ready_i;
	logic [PROGRAM_LOAD_CONTROL_WIDTH-1:0] forward_control_o;
	logic [127:0] forward_data_o;
	logic [3:0] forward_strb_o;
	logic [1:0] forward_scope_o;
	logic [11:0] forward_destination_o;
	logic [16:0] forward_imem_address_o;
	logic forward_last_o;

	logic [1:0] level_o;
	logic idle_o;
	logic fault_o;
	logic [5:0] fault_code_o;

	logic local_fire_w;
	logic forward_fire_w;
	logic [164:0] local_record_w;
	logic [164:0] forward_record_w;
	logic [164:0] stalled_record;

	integer expected_id[0:127];
	integer expected_route[0:127];
	integer expected_local_offset[0:127];
	integer expected_write_index;
	integer expected_read_index;
	integer accepted_count;
	integer emitted_count;
	integer local_count;
	integer forward_count;
	integer checks;
	integer timeout;
	integer cycle_count;
	integer local_index;
	integer ii_emitted_count;
	integer ii_previous_cycle;
	logic ii_check_active;
	logic ii_seen_first;

	always #5 clk_i = ~clk_i;

	assign local_fire_w = |(local_valid_o & local_ready_i);
	assign forward_fire_w = forward_valid_o && forward_ready_i;
	assign local_record_w = {
		local_control_o,
		local_data_o,
		local_strb_o,
		local_scope_o,
		local_destination_o,
		local_imem_address_o,
		local_last_o
	};
	assign forward_record_w = {
		forward_control_o,
		forward_data_o,
		forward_strb_o,
		forward_scope_o,
		forward_destination_o,
		forward_imem_address_o,
		forward_last_o
	};

	lpu_program_load_relay #(
		.BUFFER_DEPTH(2),
		.MEM_SLICES_PER_HEMISPHERE(MEM_SLICES_PER_HEMISPHERE),
		.MEM_SLICES_PER_GROUP(MEM_SLICES_PER_GROUP),
		.BANKS_PER_SLICE(BANKS_PER_SLICE),
		.MEM_GROUPS_PER_RELAY(MEM_GROUPS_PER_RELAY),
		.RELAY_INDEX(RELAY_INDEX),
		.RELAY_HEMISPHERE(PROGRAM_HEMISPHERE_WEST),
		.LAST_RELAY(1'b0)
	) u_dut (
		.clk_i,
		.rst_ni,
		.input_valid_i,
		.input_ready_o,
		.input_control_i,
		.input_data_i,
		.input_strb_i,
		.input_scope_i,
		.input_destination_i,
		.input_imem_address_i,
		.input_last_i,
		.local_valid_o,
		.local_ready_i,
		.local_control_o,
		.local_data_o,
		.local_strb_o,
		.local_scope_o,
		.local_destination_o,
		.local_imem_address_o,
		.local_last_o,
		.forward_valid_o,
		.forward_ready_i,
		.forward_control_o,
		.forward_data_o,
		.forward_strb_o,
		.forward_scope_o,
		.forward_destination_o,
		.forward_imem_address_o,
		.forward_last_o,
		.level_o,
		.idle_o,
		.fault_o,
		.fault_code_o
	);

	task automatic queue_expected(
		input integer message_id,
		input integer route,
		input integer offset
	);
		begin
			expected_id[expected_write_index] = message_id;
			expected_route[expected_write_index] = route;
			expected_local_offset[expected_write_index] = offset;
			expected_write_index = expected_write_index + 1;
		end
	endtask

	task automatic drive_record(
		input logic [2:0] target_kind,
		input logic hemisphere,
		input logic [1:0] scope,
		input logic [7:0] target_index,
		input integer message_id
	);
		begin
			@(negedge clk_i);
			input_control_i = PROGRAM_LOAD_WRITE;
			input_data_i = {96'h5a5a_a5a5_0123_4567_89ab_cdef, 16'hcafe,
				message_id[15:0]};
			input_strb_i = 4'b0111;
			input_scope_i = scope;
			input_destination_i = program_destination_pack(hemisphere, target_kind, target_index);
			input_imem_address_i = message_id + 17'h40;
			input_last_i = message_id[0];
			input_valid_i = 1'b1;
			while(!input_ready_o)begin
				@(negedge clk_i);
			end
			@(posedge clk_i);
			accepted_count = accepted_count + 1;
			@(negedge clk_i);
			input_valid_i = 1'b0;
		end
	endtask

	task automatic wait_for_outputs(input integer expected_total);
		begin
			timeout = 0;
			while(expected_read_index < expected_total && timeout < 80)begin
				@(negedge clk_i);
				timeout = timeout + 1;
			end
			if(expected_read_index != expected_total)begin
				$fatal(1, "timeout waiting for outputs expected=%0d observed=%0d",
					expected_total, expected_read_index);
			end
		end
	endtask

	task automatic apply_reset;
		begin
			@(negedge clk_i);
			rst_ni = 1'b0;
			input_valid_i = 1'b0;
			repeat(3) @(posedge clk_i);
			@(negedge clk_i);
			if(!idle_o || level_o != 0 || fault_o || local_valid_o != '0 || forward_valid_o)begin
				$fatal(1, "reset did not clear Relay state");
			end
			rst_ni = 1'b1;
		end
	endtask

	// One accepted Record must produce exactly one local or forward transaction in input order.
	always @(posedge clk_i) begin
		if(rst_ni)begin
			cycle_count = cycle_count + 1;
			if(!$onehot0(local_valid_o))begin
				$fatal(1, "multiple local Frontends selected valid=%h", local_valid_o);
			end
			if(local_fire_w && forward_fire_w)begin
				$fatal(1, "Record fired locally and forward in the same cycle");
			end
			if(local_fire_w || forward_fire_w)begin
				if(expected_read_index >= expected_write_index)begin
					$fatal(1,
						"unexpected output transaction read=%0d write=%0d local=%0d forward=%0d data=%0d level=%0d accepted=%0d",
						expected_read_index, expected_write_index, local_fire_w, forward_fire_w,
						local_fire_w ? local_data_o[15:0] : forward_data_o[15:0], level_o,
						accepted_count);
				end
				if(local_fire_w)begin
					if(expected_route[expected_read_index] != 0)begin
						$fatal(1, "expected forward route but observed local route");
					end
					if(!local_valid_o[expected_local_offset[expected_read_index]])begin
						$fatal(1, "wrong local Frontend selected expected_offset=%0d valid=%h",
							expected_local_offset[expected_read_index], local_valid_o);
					end
					if(local_data_o[15:0] != expected_id[expected_read_index])begin
						$fatal(1, "local output order/data mismatch expected=%0d observed=%0d",
							expected_id[expected_read_index], local_data_o[15:0]);
					end
					local_count = local_count + 1;
				end
				else begin
					if(expected_route[expected_read_index] != 1)begin
						$fatal(1, "expected local route but observed forward route");
					end
					if(forward_data_o[15:0] != expected_id[expected_read_index])begin
						$fatal(1, "forward output order/data mismatch expected=%0d observed=%0d",
							expected_id[expected_read_index], forward_data_o[15:0]);
					end
					forward_count = forward_count + 1;
				end

				if(ii_check_active)begin
					if(ii_seen_first && cycle_count != ii_previous_cycle + 1)begin
						$fatal(1, "II=1 output stream inserted a bubble previous=%0d current=%0d",
							ii_previous_cycle, cycle_count);
					end
					ii_seen_first = 1'b1;
					ii_previous_cycle = cycle_count;
					ii_emitted_count = ii_emitted_count + 1;
				end

				expected_read_index = expected_read_index + 1;
				emitted_count = emitted_count + 1;
			end
		end
	end

	initial begin
		clk_i = 1'b0;
		rst_ni = 1'b0;
		input_valid_i = 1'b0;
		input_control_i = PROGRAM_LOAD_WRITE;
		input_data_i = '0;
		input_strb_i = 4'b0111;
		input_scope_i = PROGRAM_SCOPE_WEST;
		input_destination_i = program_destination_pack(
			PROGRAM_HEMISPHERE_WEST, PROGRAM_TARGET_MEM, LOCAL_BANK_BASE);
		input_imem_address_i = '0;
		input_last_i = 1'b0;
		local_ready_i = '1;
		forward_ready_i = 1'b1;
		expected_write_index = 0;
		expected_read_index = 0;
		accepted_count = 0;
		emitted_count = 0;
		local_count = 0;
		forward_count = 0;
		checks = 0;
		cycle_count = 0;
		ii_emitted_count = 0;
		ii_previous_cycle = 0;
		ii_check_active = 1'b0;
		ii_seen_first = 1'b0;

		if(EXPECTED_GROUP_COUNT !=
			(MEM_SLICES_PER_HEMISPHERE + MEM_SLICES_PER_GROUP - 1) / MEM_SLICES_PER_GROUP)begin
			$fatal(1, "MEM Group derivation failed");
		end
		if(EXPECTED_RELAY_COUNT !=
			(EXPECTED_GROUP_COUNT + MEM_GROUPS_PER_RELAY - 1) / MEM_GROUPS_PER_RELAY)begin
			$fatal(1, "Relay Count derivation failed");
		end
		if(EXPECTED_FINAL_RELAY_BANK_COUNT !=
			(EXPECTED_GROUP_COUNT - (EXPECTED_RELAY_COUNT - 1) * MEM_GROUPS_PER_RELAY) *
			MEM_SLICES_PER_GROUP * BANKS_PER_SLICE)begin
			$fatal(1, "final Relay Bank Count derivation failed");
		end
		if(u_dut.MEM_GROUP_COUNT != EXPECTED_GROUP_COUNT ||
			u_dut.RELAY_COUNT != EXPECTED_RELAY_COUNT || u_dut.LOCAL_BANK_COUNT != LOCAL_BANK_COUNT)begin
			$fatal(1, "Relay derived parameters do not match the expected MEM organization");
		end

		apply_reset();

		// Local region boundaries select exactly one of the sixteen local Bank Frontends.
		queue_expected(1, 0, 0);
		drive_record(PROGRAM_TARGET_MEM, PROGRAM_HEMISPHERE_WEST,
			PROGRAM_SCOPE_WEST, 8'd32, 1);
		queue_expected(2, 0, 15);
		drive_record(PROGRAM_TARGET_MEM, PROGRAM_HEMISPHERE_WEST,
			PROGRAM_SCOPE_WEST, 8'd47, 2);
		wait_for_outputs(2);
		checks = checks + 1;

		// The first Bank after this region and the final MEM Bank must continue downstream.
		queue_expected(3, 1, 0);
		drive_record(PROGRAM_TARGET_MEM, PROGRAM_HEMISPHERE_WEST,
			PROGRAM_SCOPE_WEST, 8'd48, 3);
		queue_expected(4, 1, 0);
		drive_record(PROGRAM_TARGET_MEM, PROGRAM_HEMISPHERE_WEST,
			PROGRAM_SCOPE_WEST, 8'd103, 4);
		wait_for_outputs(4);
		checks = checks + 1;

		// BOTH is already split by the Distributor; one Relay handles one concrete branch once.
		queue_expected(5, 0, 3);
		drive_record(PROGRAM_TARGET_MEM, PROGRAM_HEMISPHERE_WEST,
			PROGRAM_SCOPE_BOTH, 8'd35, 5);
		wait_for_outputs(5);
		checks = checks + 1;

		// Only the selected local Ready controls retirement; all Record fields remain stable.
		local_ready_i = '1;
		local_ready_i[3] = 1'b0;
		queue_expected(6, 0, 3);
		drive_record(PROGRAM_TARGET_MEM, PROGRAM_HEMISPHERE_WEST,
			PROGRAM_SCOPE_WEST, 8'd35, 6);
		timeout = 0;
		while(!local_valid_o[3] && timeout < 20)begin
			@(negedge clk_i);
			timeout = timeout + 1;
		end
		if(!local_valid_o[3] || local_valid_o != 16'h0008 || forward_valid_o)begin
			$fatal(1, "local target selection failed valid=%h", local_valid_o);
		end
		stalled_record = local_record_w;
		repeat(3)begin
			@(negedge clk_i);
			if(local_record_w != stalled_record || local_valid_o != 16'h0008)begin
				$fatal(1, "local Record changed during backpressure");
			end
		end
		local_ready_i[3] = 1'b1;
		wait_for_outputs(6);
		checks = checks + 1;

		// Forward backpressure also freezes the complete registered Record.
		forward_ready_i = 1'b0;
		queue_expected(7, 1, 0);
		drive_record(PROGRAM_TARGET_MEM, PROGRAM_HEMISPHERE_WEST,
			PROGRAM_SCOPE_WEST, 8'd64, 7);
		timeout = 0;
		while(!forward_valid_o && timeout < 20)begin
			@(negedge clk_i);
			timeout = timeout + 1;
		end
		stalled_record = forward_record_w;
		repeat(3)begin
			@(negedge clk_i);
			if(!forward_valid_o || forward_record_w != stalled_record)begin
				$fatal(1, "forward Record changed during backpressure");
			end
		end
		forward_ready_i = 1'b1;
		wait_for_outputs(7);
		checks = checks + 1;

		// Fill both entries. Registered Ready remains low during the first release edge.
		local_ready_i = '0;
		queue_expected(8, 0, 0);
		drive_record(PROGRAM_TARGET_MEM, PROGRAM_HEMISPHERE_WEST,
			PROGRAM_SCOPE_WEST, 8'd32, 8);
		queue_expected(9, 0, 1);
		drive_record(PROGRAM_TARGET_MEM, PROGRAM_HEMISPHERE_WEST,
			PROGRAM_SCOPE_WEST, 8'd33, 9);
		if(level_o != 2 || input_ready_o)begin
			$fatal(1, "Relay did not apply full backpressure level=%0d ready=%0d", level_o, input_ready_o);
		end

		queue_expected(10, 0, 2);
		@(negedge clk_i);
		input_data_i = {112'd0, 16'd10};
		input_destination_i = program_destination_pack(
			PROGRAM_HEMISPHERE_WEST, PROGRAM_TARGET_MEM, 8'd34);
		input_imem_address_i = 17'h4a;
		input_last_i = 1'b0;
		input_valid_i = 1'b1;
		if(input_ready_o)begin
			$fatal(1, "full Relay accepted a third Record before release");
		end
		local_ready_i = '1;
		@(posedge clk_i);
		@(negedge clk_i);
		if(!input_ready_o)begin
			$fatal(1, "registered Ready did not recover after one entry retired");
		end
		@(posedge clk_i);
		accepted_count = accepted_count + 1;
		@(negedge clk_i);
		input_valid_i = 1'b0;
		wait_for_outputs(10);
		checks = checks + 1;

		// Stable downstream readiness allows one accepted and one emitted Record every cycle.
		local_ready_i = '1;
		forward_ready_i = 1'b1;
		ii_check_active = 1'b1;
		ii_seen_first = 1'b0;
		ii_emitted_count = 0;
		for(integer stream_index = 0; stream_index < 8; stream_index = stream_index + 1)begin
			@(negedge clk_i);
			input_control_i = PROGRAM_LOAD_WRITE;
			input_data_i = '0;
			input_data_i[15:0] = 20 + stream_index;
			input_strb_i = 4'b0111;
			input_scope_i = PROGRAM_SCOPE_WEST;
			if(stream_index[0])begin
				input_destination_i = program_destination_pack(
					PROGRAM_HEMISPHERE_WEST, PROGRAM_TARGET_MEM, 8'd80);
			end
			else begin
				input_destination_i = program_destination_pack(
					PROGRAM_HEMISPHERE_WEST, PROGRAM_TARGET_MEM,
					LOCAL_BANK_BASE + stream_index);
			end
			input_imem_address_i = 17'h100 + stream_index;
			input_last_i = stream_index == 7;
			input_valid_i = 1'b1;
			if(!input_ready_o)begin
				$fatal(1, "II=1 input was not ready at stream index %0d", stream_index);
			end
			queue_expected(20 + stream_index, stream_index[0] ? 1 : 0,
				stream_index[0] ? 0 : stream_index);
			@(posedge clk_i);
			accepted_count = accepted_count + 1;
		end
		@(negedge clk_i);
		input_valid_i = 1'b0;
		wait_for_outputs(18);
		ii_check_active = 1'b0;
		if(ii_emitted_count != 8)begin
			$fatal(1, "II=1 stream output count mismatch observed=%0d", ii_emitted_count);
		end
		checks = checks + 1;

		// Reserved destinations raise a sticky Route Fault and block further acceptance.
		drive_record(PROGRAM_TARGET_RESERVED, PROGRAM_HEMISPHERE_WEST,
			PROGRAM_SCOPE_WEST, 8'd0, 40);
		timeout = 0;
		while(!fault_o && timeout < 20)begin
			@(negedge clk_i);
			timeout = timeout + 1;
		end
		if(!fault_o || fault_code_o != PROGRAM_FAULT_ROUTE || input_ready_o ||
			local_valid_o != '0 || forward_valid_o)begin
			$fatal(1, "invalid Destination did not stop the Relay with Route Fault");
		end
		checks = checks + 1;

		apply_reset();
		if(fault_o || !input_ready_o)begin
			$fatal(1, "reset did not clear sticky Route Fault");
		end

		// A concrete East Destination cannot enter a West Relay chain.
		drive_record(PROGRAM_TARGET_MEM, PROGRAM_HEMISPHERE_EAST,
			PROGRAM_SCOPE_EAST, 8'd32, 41);
		timeout = 0;
		while(!fault_o && timeout < 20)begin
			@(negedge clk_i);
			timeout = timeout + 1;
		end
		if(!fault_o || fault_code_o != PROGRAM_FAULT_ROUTE)begin
			$fatal(1, "wrong Hemisphere did not produce Route Fault");
		end
		checks = checks + 1;

		apply_reset();
		queue_expected(42, 0, 4);
		drive_record(PROGRAM_TARGET_MEM, PROGRAM_HEMISPHERE_WEST,
			PROGRAM_SCOPE_WEST, 8'd36, 42);
		wait_for_outputs(19);
		checks = checks + 1;

		if(accepted_count != emitted_count + 2)begin
			$fatal(1, "accepted/output accounting mismatch accepted=%0d emitted=%0d",
				accepted_count, emitted_count);
		end
		if(local_count != 12 || forward_count != 7)begin
			$fatal(1, "route counts mismatch local=%0d forward=%0d", local_count, forward_count);
		end

		$display("LPU_PROGRAM_LOAD_RELAY TEST_PASS checks=%0d accepted=%0d emitted=%0d",
			checks, accepted_count, emitted_count);
		$finish;
	end
endmodule
