`timescale 1ns/1ps

module lpu_mxm_subsystem_five_stream_tb;
	import lpu_program_load_pkg::*;

	logic clk;
	logic rst_n;
	logic run_enable;
	logic [31:0] schedule_cycle;
	logic program_valid;
	logic program_ready;
	logic [PROGRAM_LOAD_CONTROL_WIDTH-1:0] program_control;
	logic [PROGRAM_DESTINATION_WIDTH-1:0] program_destination;
	logic [16:0] program_address;
	logic [127:0] program_data;
	logic [3:0] program_strb;
	logic program_last;
	logic program_error;
	logic load_issue_valid;
	logic [lpu_mxm_isa_pkg::LOAD_INSTRUCTION_BITS-1:0] load_issue_instruction;
	logic [31:0] load_issue_cycle;
	logic compute_issue_valid;
	logic [lpu_mxm_isa_pkg::COMPUTE_INSTRUCTION_BITS-1:0] compute_issue_instruction;
	logic [31:0] compute_issue_cycle;
	logic dequant_issue_valid;
	logic [lpu_mxm_isa_pkg::DEQUANT_INSTRUCTION_BITS-1:0] dequant_issue_instruction;
	logic [31:0] dequant_issue_cycle;
	logic param_issue_valid;
	logic [lpu_mxm_isa_pkg::PARAM_LOAD_INSTRUCTION_BITS-1:0] param_issue_instruction;
	logic [31:0] param_issue_cycle;
	logic backend_issue_valid;
	logic [lpu_mxm_backend_isa_pkg::BACKEND_INSTRUCTION_BITS-1:0] backend_issue_instruction;
	logic [31:0] backend_issue_cycle;
	logic frontends_ready;
	logic frontends_idle;
	logic frontend_fault;
	logic [5:0] frontend_fault_code;
	logic fault;
	logic conflict;
	integer issue_count [0:4];
	integer fail_count;
	integer init_index;

	lpu_mxm_subsystem #(
		.HEMISPHERE_INDEX(PROGRAM_HEMISPHERE_EAST),
		.LOCAL_MXM_INDEX(0),
		.IMEM_DEPTH(16),
		.ACTIVE_CONTEXTS(2),
		.PAIR_LOAD_DEQUANT(1'b1)
	) u_dut (
		.clk_i(clk),
		.rst_ni(rst_n),
		.program_reset_i(1'b0),
		.local_frontend_enable_i(1'b1),
		.run_i(run_enable),
		.schedule_cycle_i(schedule_cycle),
		.qctl_configure_valid_i('0),
		.qctl_configure_count_i('0),
		.qctl_configure_generation_i('0),
		.qctl_head_index_o(),
		.qctl_head_generation_o(),
		.qctl_store_loaded_i('0),
		.qctl_head_valid_i('0),
		.qctl_head_record_i('0),
		.qctl_head_error_i('0),
		.qctl_event_valid_i('0),
		.qctl_event_tag_i('0),
		.qctl_event_wait_o(),
		.qctl_event_consume_o(),
		.qctl_sync_arrive_valid_o(),
		.qctl_sync_release_valid_i('0),
		.qctl_notify_valid_o(),
		.qctl_notify_ready_i('1),
		.qctl_mem_packet_valid_o(),
		.qctl_mem_packet_ordinal_o(),
		.qctl_mem_packet_retired_i('0),
		.qctl_configured_o(),
		.qctl_primed_o(),
		.qctl_done_o(),
		.qctl_fault_o(),
		.qctl_fault_code_o(),
		.program_valid_i(program_valid),
		.program_ready_o(program_ready),
		.program_control_i(program_control),
		.program_destination_i(program_destination),
		.program_address_i(program_address),
		.program_data_i(program_data),
		.program_strb_i(program_strb),
		.program_last_i(program_last),
		.program_error_o(program_error),
		.external_load_valid_i(1'b0),
		.external_load_instruction_i('0),
		.external_dequant_valid_i(1'b0),
		.external_dequant_instruction_i('0),
		.external_compute_valid_i(1'b0),
		.external_compute_instruction_i('0),
		.local_load_issue_valid_o(load_issue_valid),
		.local_load_issue_instruction_o(load_issue_instruction),
		.local_load_issue_cycle_o(load_issue_cycle),
		.local_dequant_issue_valid_o(dequant_issue_valid),
		.local_dequant_issue_instruction_o(dequant_issue_instruction),
		.local_dequant_issue_cycle_o(dequant_issue_cycle),
		.local_compute_issue_valid_o(compute_issue_valid),
		.local_compute_issue_instruction_o(compute_issue_instruction),
		.local_compute_issue_cycle_o(compute_issue_cycle),
		.local_param_load_issue_valid_o(param_issue_valid),
		.local_param_load_issue_instruction_o(param_issue_instruction),
		.local_param_load_issue_cycle_o(param_issue_cycle),
		.local_backend_issue_valid_o(backend_issue_valid),
		.local_backend_issue_instruction_o(backend_issue_instruction),
		.local_backend_issue_cycle_o(backend_issue_cycle),
		.frontends_ready_o(frontends_ready),
		.frontends_idle_o(frontends_idle),
		.frontend_fault_o(frontend_fault),
		.frontend_fault_code_o(frontend_fault_code),
		.east_from_sxm_valid_i('0),
		.east_from_sxm_data_i('0),
		.external_west_valid_i('0),
		.external_west_data_i('0),
		.east_external_valid_o(),
		.east_external_data_o(),
		.west_to_sxm_valid_o(),
		.west_to_sxm_data_o(),
		.fault_o(fault),
		.conflict_o(conflict)
	);

	always #5 clk = ~clk;

	task automatic push_bits(
		inout logic [127:0] bits,
		inout integer cursor,
		input logic [63:0] value,
		input integer width
	);
		integer bit_index;
		begin
			for(bit_index = 0; bit_index < width; bit_index = bit_index + 1)begin
				bits[cursor + bit_index] = value[bit_index];
			end
			cursor = cursor + width;
		end
	endtask

	function automatic logic [PROGRAM_TARGET_KIND_WIDTH-1:0] target_kind(input integer stream);
		case(stream)
			lpu_mxm_isa_pkg::MXM_QUEUE_LOAD: target_kind = PROGRAM_TARGET_MXM_LOAD;
			lpu_mxm_isa_pkg::MXM_QUEUE_COMPUTE: target_kind = PROGRAM_TARGET_MXM_COMPUTE;
			lpu_mxm_isa_pkg::MXM_QUEUE_DEQUANT: target_kind = PROGRAM_TARGET_MXM_DEQUANT;
			lpu_mxm_isa_pkg::MXM_QUEUE_PARAM_LOAD: target_kind = PROGRAM_TARGET_MXM_PARAM_LOAD;
			default: target_kind = PROGRAM_TARGET_MXM_BACKEND;
		endcase
	endfunction

	function automatic logic [48:0] native_instruction(input integer stream);
		case(stream)
			lpu_mxm_isa_pkg::MXM_QUEUE_LOAD: native_instruction = 49'h2;
			lpu_mxm_isa_pkg::MXM_QUEUE_COMPUTE: native_instruction = 49'h7;
			lpu_mxm_isa_pkg::MXM_QUEUE_DEQUANT: native_instruction = 49'h1;
			lpu_mxm_isa_pkg::MXM_QUEUE_PARAM_LOAD: native_instruction = 49'h1;
			default: native_instruction = 49'h8;
		endcase
	endfunction

	function automatic integer start_cycle_for_stream(input integer stream);
		case(stream)
			lpu_mxm_isa_pkg::MXM_QUEUE_LOAD: start_cycle_for_stream = 3;
			lpu_mxm_isa_pkg::MXM_QUEUE_COMPUTE: start_cycle_for_stream = 4;
			lpu_mxm_isa_pkg::MXM_QUEUE_DEQUANT: start_cycle_for_stream = 3;
			lpu_mxm_isa_pkg::MXM_QUEUE_PARAM_LOAD: start_cycle_for_stream = 6;
			default: start_cycle_for_stream = 7;
		endcase
	endfunction

	task automatic send_program_record(
		input logic [PROGRAM_LOAD_CONTROL_WIDTH-1:0] control,
		input logic [PROGRAM_DESTINATION_WIDTH-1:0] destination,
		input logic [16:0] address,
		input logic [127:0] data,
		input logic [3:0] strb,
		input logic last
	);
		begin
			@(negedge clk);
			program_valid = 1'b1;
			program_control = control;
			program_destination = destination;
			program_address = address;
			program_data = data;
			program_strb = strb;
			program_last = last;
			do @(posedge clk); while(!program_ready);
			if(program_error)begin
				$display("FAIL Program record rejected destination=%h control=%0d", destination, control);
				fail_count = fail_count + 1;
			end
			@(negedge clk);
			program_valid = 1'b0;
		end
	endtask

	task automatic load_stream(input integer stream);
		logic [127:0] bits;
		logic [PROGRAM_DESTINATION_WIDTH-1:0] destination;
		integer cursor;
		begin
			bits = '0;
			cursor = 0;
			push_bits(bits, cursor, 0, 3);
			push_bits(bits, cursor, start_cycle_for_stream(stream), 32);
			push_bits(bits, cursor, 0, lpu_mxm_isa_pkg::macro_operand_bits(stream));
			push_bits(bits, cursor, 0, 1);
			push_bits(bits, cursor, 0, 1);
			push_bits(bits, cursor, native_instruction(stream), lpu_mxm_isa_pkg::macro_native_bits(stream));
			push_bits(bits, cursor, 0, 2);
			push_bits(bits, cursor, lpu_mxm_isa_pkg::MXM_INDUCTION_NONE, 2);
			destination = program_destination_pack(PROGRAM_HEMISPHERE_EAST, target_kind(stream), 8'd0);
			send_program_record(PROGRAM_LOAD_WRITE, destination, 17'd0, 128'h15, 4'b1111, 1'b0);
			send_program_record(PROGRAM_LOAD_WRITE, destination, 17'd1, bits, 4'b1111, 1'b1);
			send_program_record(PROGRAM_LOAD_PRIME, destination, '0, '0, '0, 1'b1);
		end
	endtask

	initial begin
		integer cycle_value;
		logic [4:0] valid_vector;
		logic [4:0] expected_vector;
		clk = 1'b0;
		rst_n = 1'b0;
		run_enable = 1'b0;
		schedule_cycle = '0;
		program_valid = 1'b0;
		program_control = PROGRAM_LOAD_WRITE;
		program_destination = '0;
		program_address = '0;
		program_data = '0;
		program_strb = '0;
		program_last = 1'b0;
		fail_count = 0;
		for(init_index = 0; init_index < 5; init_index = init_index + 1) issue_count[init_index] = 0;
		repeat(4) @(posedge clk);
		rst_n = 1'b1;

		for(init_index = 0; init_index < 5; init_index = init_index + 1) load_stream(init_index);
		init_index = 0;
		while(!frontends_ready && !frontend_fault && (init_index < 500))begin
			@(posedge clk);
			#1;
			init_index = init_index + 1;
		end
		if(init_index == 500) $fatal(1, "timeout waiting for five MXM Frontends to PRIME");
		if(frontend_fault)begin
			$display("frontend_fault_vector=%b fetch_codes=%0d/%0d/%0d/%0d/%0d", u_dut.frontend_fault,
				u_dut.gen_frontend[0].u_frontend.fetch_fault_code,
				u_dut.gen_frontend[1].u_frontend.fetch_fault_code,
				u_dut.gen_frontend[2].u_frontend.fetch_fault_code,
				u_dut.gen_frontend[3].u_frontend.fetch_fault_code,
				u_dut.gen_frontend[4].u_frontend.fetch_fault_code);
			$fatal(1, "MXM Frontend fault during load code=%0d", frontend_fault_code);
		end

		for(cycle_value = 0; cycle_value <= 7; cycle_value = cycle_value + 1)begin
			@(negedge clk);
			run_enable = 1'b1;
			schedule_cycle = cycle_value;
			#1;
			valid_vector = {backend_issue_valid, param_issue_valid, dequant_issue_valid,
				compute_issue_valid, load_issue_valid};
			case(cycle_value)
				3: expected_vector = 5'b00101;
				4: expected_vector = 5'b00010;
				6: expected_vector = 5'b01000;
				7: expected_vector = 5'b10000;
				default: expected_vector = '0;
			endcase
			if(valid_vector !== expected_vector)begin
				$display("FAIL cycle %0d issue vector=%b expected=%b", cycle_value, valid_vector, expected_vector);
				fail_count = fail_count + 1;
			end
			if(load_issue_valid)begin issue_count[0] = issue_count[0] + 1; if(load_issue_instruction != 2'h2) fail_count = fail_count + 1; end
			if(compute_issue_valid)begin issue_count[1] = issue_count[1] + 1; if(compute_issue_instruction != 7'h7) fail_count = fail_count + 1; end
			if(dequant_issue_valid)begin issue_count[2] = issue_count[2] + 1; if(dequant_issue_instruction != 1'h1) fail_count = fail_count + 1; end
			if(param_issue_valid)begin issue_count[3] = issue_count[3] + 1; if(param_issue_instruction != 1'h1) fail_count = fail_count + 1; end
			if(backend_issue_valid)begin issue_count[4] = issue_count[4] + 1; if(backend_issue_instruction != 13'h8) fail_count = fail_count + 1; end
			@(posedge clk);
		end

		@(negedge clk);
		run_enable = 1'b0;
		for(init_index = 0; init_index < 5; init_index = init_index + 1)begin
			if(issue_count[init_index] != 1) fail_count = fail_count + 1;
		end
		// This transport test supplies no activation or weight data. The execution
		// core may therefore report its own datapath fault after accepting Compute;
		// only instruction-front-end and pairing faults are in scope here.
		if(conflict || frontend_fault)begin
			$display("FAIL final conflict=%0b frontend_fault=%0b", conflict, frontend_fault);
			fail_count = fail_count + 1;
		end
		if(fail_count == 0) $display("MXM_SUBSYSTEM_FIVE_STREAM_TB PASS");
		else $fatal(1, "MXM_SUBSYSTEM_FIVE_STREAM_TB FAIL count=%0d", fail_count);
		$finish;
	end
endmodule
