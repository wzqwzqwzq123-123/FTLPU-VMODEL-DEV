`timescale 1ns/1ps

module lpu_top_fu_subsystem_program_tb;
	import lpu_program_load_pkg::*;

	localparam integer COMMAND_DEPTH = 64;
	localparam integer COMMAND_ADDRESS_WIDTH = $clog2(COMMAND_DEPTH);
	localparam logic [1:0] PROGRAM_ENCODING_MACRO = 2'd0;
	localparam logic [1:0] PROGRAM_ENCODING_FU3D = 2'd1;
	localparam logic [95:0] MEM_WORD_0 = 96'h00000000_00000000_00000027;
	localparam logic [95:0] MEM_WORD_1 = 96'h00303200_00000180_02000021;
	localparam logic [95:0] MEM_WORD_2 = 96'h00000000_00000000_00000400;
	localparam logic [127:0] MXM_CONTROL = 128'h00000000000000000000000000000017;
	localparam logic [127:0] MXM_LOAD = 128'h00000000000000000400000800000028;
	localparam logic [127:0] MXM_COMPUTE = 128'h00000060400040000004032000000030;
	localparam logic [127:0] MXM_DEQUANT = 128'h00000000000000000007f00000000010;

	logic clk;
	logic rst_n;
	logic program_reset;
	logic program_command_write_valid;
	logic program_command_write_ready;
	logic [COMMAND_ADDRESS_WIDTH-1:0] program_command_write_address;
	logic [2:0] program_command_write_opcode;
	logic [63:0] program_command_write_source_address;
	logic [31:0] program_command_write_byte_count;
	logic [11:0] program_command_write_destination;
	logic [1:0] program_command_write_format;
	logic [1:0] program_command_write_encoding_mode;
	logic [16:0] program_command_write_imem_base_address;
	logic program_command_write_image_first;
	logic program_command_write_image_last;
	logic [15:0] program_command_write_expected_word_count;
	logic [COMMAND_ADDRESS_WIDTH-1:0] program_command_write_jump_address;
	logic program_load_start_valid;
	logic program_load_start_ready;
	logic [COMMAND_ADDRESS_WIDTH:0] program_load_start_command_count;
	logic program_dma_cmd_valid;
	logic program_dma_cmd_ready;
	logic [63:0] program_dma_cmd_address;
	logic [31:0] program_dma_cmd_length;
	logic [7:0] program_dma_cmd_id;
	logic program_dma_rsp_valid;
	logic program_dma_rsp_ready;
	logic [255:0] program_dma_rsp_data;
	logic [31:0] program_dma_rsp_keep;
	logic program_dma_rsp_last;
	logic [7:0] program_dma_rsp_id;
	logic program_dma_rsp_error;
	logic program_start_request;
	logic program_dependencies_ready;
	logic program_start_ack;
	logic program_load_complete;
	logic program_ready;
	logic program_running;
	logic program_done;
	logic program_fault;
	logic [5:0] program_fault_code;
	logic [31:0] program_schedule_cycle;
	logic [63:0] physical_cycle;

	integer next_command;
	integer checks;
	integer timeout;
	integer start_ack_count;
	integer physical_clock_edges;

	always #5 clk = ~clk;

	// This counter proves that Program Reset never stops or replaces the physical clock.
	always @(posedge clk) begin
		physical_clock_edges <= physical_clock_edges + 1;
		if(rst_n && program_start_ack)begin
			start_ack_count <= start_ack_count + 1;
		end
	end

	function automatic logic [287:0] make_mem_image(
		input logic [31:0] start_cycle,
		input logic [12:0] address,
		input logic [5:0] stream
	);
		logic [287:0] image;
		begin
			image = {MEM_WORD_2, MEM_WORD_1, MEM_WORD_0};
			image[135+:32] = start_cycle;
			image[167+:13] = address;
			image[201+:6] = stream;
			make_mem_image = image;
		end
	endfunction

	function automatic logic [287:0] make_mxm_image(
		input logic [127:0] instruction
	);
		logic [287:0] image;
		begin
			image = '0;
			image[0+:128] = MXM_CONTROL;
			image[128+:128] = instruction;
			make_mxm_image = image;
		end
	endfunction

	lpu_top #(
		.ICU_QUEUE_DEPTH(4),
		.MEM_DEPTH_ROWS(256),
		.ACTIVE_MEM_COLUMNS(2),
		.ENABLE_DISTRIBUTED_PROGRAM_FRONTEND(1'b1),
		.PROGRAM_COMMAND_DEPTH(COMMAND_DEPTH),
		.PROGRAM_MEM_IMEM_DEPTH(16),
		.PROGRAM_MXM_IMEM_DEPTH(16),
		.PROGRAM_ACTIVE_CONTEXTS(4)
	) u_dut (
		.clk_i(clk),
		.rst_ni(rst_n),
		.run_i(1'b0),
		.schedule_valid_i(1'b0),
		.schedule_ready_o(),
		.schedule_queue_i('0),
		.schedule_is_instruction_i(1'b0),
		.schedule_command_i('0),
		.schedule_payload_i('0),
		.program_reset_i(program_reset),
		.program_command_write_valid_i(program_command_write_valid),
		.program_command_write_ready_o(program_command_write_ready),
		.program_command_write_address_i(program_command_write_address),
		.program_command_write_opcode_i(program_command_write_opcode),
		.program_command_write_source_address_i(program_command_write_source_address),
		.program_command_write_byte_count_i(program_command_write_byte_count),
		.program_command_write_destination_i(program_command_write_destination),
		.program_command_write_format_i(program_command_write_format),
		.program_command_write_encoding_mode_i(program_command_write_encoding_mode),
		.program_command_write_imem_base_address_i(program_command_write_imem_base_address),
		.program_command_write_image_first_i(program_command_write_image_first),
		.program_command_write_image_last_i(program_command_write_image_last),
		.program_command_write_expected_word_count_i(program_command_write_expected_word_count),
		.program_command_write_jump_address_i(program_command_write_jump_address),
		.program_load_start_valid_i(program_load_start_valid),
		.program_load_start_ready_o(program_load_start_ready),
		.program_load_start_command_count_i(program_load_start_command_count),
		.program_dma_cmd_valid_o(program_dma_cmd_valid),
		.program_dma_cmd_ready_i(program_dma_cmd_ready),
		.program_dma_cmd_address_o(program_dma_cmd_address),
		.program_dma_cmd_length_o(program_dma_cmd_length),
		.program_dma_cmd_id_o(program_dma_cmd_id),
		.program_dma_rsp_valid_i(program_dma_rsp_valid),
		.program_dma_rsp_ready_o(program_dma_rsp_ready),
		.program_dma_rsp_data_i(program_dma_rsp_data),
		.program_dma_rsp_keep_i(program_dma_rsp_keep),
		.program_dma_rsp_last_i(program_dma_rsp_last),
		.program_dma_rsp_id_i(program_dma_rsp_id),
		.program_dma_rsp_error_i(program_dma_rsp_error),
		.program_start_request_i(program_start_request),
		.program_dependencies_ready_i(program_dependencies_ready),
		.program_start_ack_o(program_start_ack),
		.program_load_complete_o(program_load_complete),
		.program_ready_o(program_ready),
		.program_running_o(program_running),
		.program_done_o(program_done),
		.program_fault_o(program_fault),
		.program_fault_code_o(program_fault_code),
		.program_schedule_cycle_o(program_schedule_cycle),
		.mem_east_edge_valid_i('0),
		.mem_east_edge_data_i('0),
		.mem_east_edge_valid_o(),
		.mem_east_edge_data_o(),
		.mem_west_edge_valid_i('0),
		.mem_west_edge_data_i('0),
		.mem_west_edge_valid_o(),
		.mem_west_edge_data_o(),
		.dispatch_valid_o(),
		.dispatch_payload_o(),
		.queue_fault_o(),
		.mem_fault_o(),
		.mxm_fault_o(),
		.sxm_fault_o(),
		.vxm_fault_o(),
		.stream_conflict_o(),
		.cycle_o(physical_cycle)
	);

	task automatic check(input logic condition, input string label);
		begin
			if(!condition)begin
				$fatal(1, "FAIL %s schedule=%0d fault=%0b code=%0d", label,
					program_schedule_cycle, program_fault, program_fault_code);
			end
			checks = checks + 1;
		end
	endtask

	task automatic pulse_program_reset;
		integer edge_before;
		begin
			edge_before = physical_clock_edges;
			@(negedge clk);
			program_reset = 1'b1;
			@(posedge clk);
			@(negedge clk);
			program_reset = 1'b0;
			repeat(2) @(posedge clk);
			check(physical_clock_edges > edge_before, "Program Reset preserves physical clock");
			check(program_schedule_cycle == 0 && !program_running && !program_done,
				"Program Reset clears program control state");
		end
	endtask

	task automatic write_command(
		input integer address,
		input logic [2:0] opcode,
		input logic [63:0] source_address,
		input logic [31:0] byte_count,
		input logic [11:0] destination,
		input logic [1:0] format,
		input logic [15:0] expected_words,
		input logic [16:0] imem_base,
		input logic [1:0] encoding_mode
	);
		begin
			@(negedge clk);
			program_command_write_address = address[COMMAND_ADDRESS_WIDTH-1:0];
			program_command_write_opcode = opcode;
			program_command_write_source_address = source_address;
			program_command_write_byte_count = byte_count;
			program_command_write_destination = destination;
			program_command_write_format = format;
			program_command_write_encoding_mode = encoding_mode;
			program_command_write_imem_base_address = imem_base;
			program_command_write_image_first = 1'b1;
			program_command_write_image_last = 1'b1;
			program_command_write_expected_word_count = expected_words;
			program_command_write_jump_address = '0;
			program_command_write_valid = 1'b1;
			check(program_command_write_ready, "Program command RAM ready");
			@(posedge clk);
			@(negedge clk);
			program_command_write_valid = 1'b0;
		end
	endtask

	task automatic append_image_commands(
		input logic [63:0] source_address,
		input logic [31:0] byte_count,
		input logic [11:0] destination,
		input logic [1:0] format,
		input logic [15:0] expected_words
	);
		begin
			write_command(next_command, PROGRAM_LOADER_LOAD_IMEM, source_address, byte_count,
				destination, format, expected_words, 17'd0, PROGRAM_ENCODING_MACRO);
			next_command = next_command + 1;
			write_command(next_command, PROGRAM_LOADER_WAIT_DMA, 0, 0,
				destination, format, expected_words, 17'd0, PROGRAM_ENCODING_MACRO);
			next_command = next_command + 1;
			write_command(next_command, PROGRAM_LOADER_COMMIT_QUEUE, 0, 0,
				destination, format, expected_words, 17'd0, PROGRAM_ENCODING_MACRO);
			next_command = next_command + 1;
		end
	endtask

	task automatic append_end;
		begin
			write_command(next_command, PROGRAM_LOADER_END, 0, 0,
				program_destination_pack(PROGRAM_HEMISPHERE_EAST, PROGRAM_TARGET_MEM, 8'd0),
				PROGRAM_FORMAT_96, 0, 17'd0, PROGRAM_ENCODING_MACRO);
			next_command = next_command + 1;
		end
	endtask

	task automatic start_loader;
		begin
			@(negedge clk);
			program_load_start_command_count = next_command;
			program_load_start_valid = 1'b1;
			check(program_load_start_ready, "Program Loader accepts command list");
			@(posedge clk);
			@(negedge clk);
			program_load_start_valid = 1'b0;
		end
	endtask

	task automatic send_dma_beat(
		input logic [255:0] data,
		input logic [31:0] keep,
		input logic last,
		input logic [7:0] id
	);
		begin
			@(negedge clk);
			program_dma_rsp_data = data;
			program_dma_rsp_keep = keep;
			program_dma_rsp_last = last;
			program_dma_rsp_id = id;
			program_dma_rsp_error = 1'b0;
			program_dma_rsp_valid = 1'b1;
			timeout = 0;
			while(!program_dma_rsp_ready && timeout < 100)begin
				@(negedge clk);
				timeout = timeout + 1;
			end
			check(program_dma_rsp_ready, "DMA response accepted under ready/valid");
			@(posedge clk);
			@(negedge clk);
			program_dma_rsp_valid = 1'b0;
		end
	endtask

	task automatic serve_dma_image(
		input logic [63:0] expected_address,
		input integer byte_count,
		input logic [287:0] image
	);
		logic [7:0] dma_id;
		logic [63:0] held_address;
		logic [31:0] held_length;
		begin
			timeout = 0;
			while(!program_dma_cmd_valid && timeout < 500)begin
				@(negedge clk);
				timeout = timeout + 1;
			end
			check(program_dma_cmd_valid, "DMA command produced");
			held_address = program_dma_cmd_address;
			held_length = program_dma_cmd_length;
			dma_id = program_dma_cmd_id;
			check(held_address == expected_address && held_length == byte_count,
				"ProgramImage source and byte count preserved");
			repeat(2)begin
				@(negedge clk);
				check(program_dma_cmd_valid && program_dma_cmd_address == held_address &&
					program_dma_cmd_length == held_length && program_dma_cmd_id == dma_id,
					"DMA command stable under backpressure");
			end
			program_dma_cmd_ready = 1'b1;
			@(posedge clk);
			@(negedge clk);
			program_dma_cmd_ready = 1'b0;
			if(byte_count <= 32)begin
				send_dma_beat(image[0+:256], (32'hffff_ffff >> (32-byte_count)), 1'b1, dma_id);
			end
			else begin
				send_dma_beat(image[0+:256], 32'hffff_ffff, 1'b0, dma_id);
				send_dma_beat({224'd0, image[256+:32]}, 32'h0000_000f, 1'b1, dma_id);
			end
		end
	endtask

	task automatic wait_load_and_prime;
		begin
			timeout = 0;
			while(!program_load_complete && timeout < 2000)begin
				@(negedge clk);
				check(program_schedule_cycle == 0 && !program_running,
					"Load and write commit do not advance Schedule Cycle");
				timeout = timeout + 1;
			end
			check(program_load_complete, "All writes committed before Load Complete");
			timeout = 0;
			while(!program_ready && timeout < 2000)begin
				@(negedge clk);
				check(program_schedule_cycle == 0 && !program_running,
					"Parallel Prefetch does not advance Schedule Cycle");
				timeout = timeout + 1;
			end
			check(program_ready && !program_fault, "All primed Frontends reached Ready");
		end
	endtask

	initial begin
		logic [287:0] mem_q0_image;
		logic [287:0] mem_q1_image;
		logic [287:0] mem_q103_image;
		logic [287:0] mem_q104_image;
		logic [287:0] mem_q105_image;
		logic [287:0] mem_q207_image;
		logic [287:0] cycle0_image;
		integer edge_before_switch;

		clk = 1'b0;
		rst_n = 1'b0;
		program_reset = 1'b0;
		program_command_write_valid = 1'b0;
		program_command_write_address = '0;
		program_command_write_opcode = '0;
		program_command_write_source_address = '0;
		program_command_write_byte_count = '0;
		program_command_write_destination = '0;
		program_command_write_format = '0;
		program_command_write_encoding_mode = '0;
		program_command_write_imem_base_address = '0;
		program_command_write_image_first = 1'b0;
		program_command_write_image_last = 1'b0;
		program_command_write_expected_word_count = '0;
		program_command_write_jump_address = '0;
		program_load_start_valid = 1'b0;
		program_load_start_command_count = '0;
		program_dma_cmd_ready = 1'b0;
		program_dma_rsp_valid = 1'b0;
		program_dma_rsp_data = '0;
		program_dma_rsp_keep = '0;
		program_dma_rsp_last = 1'b0;
		program_dma_rsp_id = '0;
		program_dma_rsp_error = 1'b0;
		program_start_request = 1'b0;
		program_dependencies_ready = 1'b0;
		next_command = 0;
		checks = 0;
		timeout = 0;
		start_ack_count = 0;
		physical_clock_edges = 0;

		repeat(5) @(posedge clk);
		@(negedge clk);
		rst_n = 1'b1;

		// The packed field order is Hemisphere[11], Kind[10:8], Target Index[7:0].
		check(program_destination_pack(PROGRAM_HEMISPHERE_EAST, PROGRAM_TARGET_MEM, 8'd0) == 12'h000,
			"Destination encoding East MEM 0");
		check(program_destination_pack(PROGRAM_HEMISPHERE_EAST, PROGRAM_TARGET_MEM, 8'd103) == 12'h067,
			"Destination encoding East MEM 103");
		check(program_destination_pack(PROGRAM_HEMISPHERE_WEST, PROGRAM_TARGET_MEM, 8'd0) == 12'h800,
			"Destination encoding West MEM 0");
		check(program_destination_pack(PROGRAM_HEMISPHERE_WEST, PROGRAM_TARGET_MEM, 8'd103) == 12'h867,
			"Destination encoding West MEM 103");
		check(program_destination_pack(PROGRAM_HEMISPHERE_EAST, PROGRAM_TARGET_MXM_COMPUTE, 8'd1) == 12'h301,
			"Destination encoding East MXM Compute 1");
		check(program_destination_pack(PROGRAM_HEMISPHERE_WEST, PROGRAM_TARGET_MXM_LOAD, 8'd0) == 12'h900,
			"Destination encoding West MXM Load 0");
		check(program_destination_pack(PROGRAM_HEMISPHERE_EAST, PROGRAM_TARGET_SXM_TRANSPOSE, 8'd0) == 12'h500,
			"Destination encoding East SXM Transpose");
		check(program_destination_pack(PROGRAM_HEMISPHERE_EAST, PROGRAM_TARGET_SXM_PERMUTE, 8'd0) == 12'h600,
			"Destination encoding East SXM Permute");

		// System Test C/D: load both hemispheres and all three MXM streams. No Queue is primed early.
		mem_q0_image = make_mem_image(5, 100, 1);
		mem_q1_image = make_mem_image(5, 200, 2);
		mem_q103_image = make_mem_image(9, 500, 5);
		mem_q104_image = make_mem_image(7, 300, 3);
		mem_q105_image = make_mem_image(7, 400, 4);
		mem_q207_image = make_mem_image(11, 600, 6);
		next_command = 0;
		append_image_commands(64'h1000, 36,
			program_destination_pack(PROGRAM_HEMISPHERE_EAST, PROGRAM_TARGET_MEM, 8'd0), PROGRAM_FORMAT_96, 3);
		append_image_commands(64'h1100, 36,
			program_destination_pack(PROGRAM_HEMISPHERE_EAST, PROGRAM_TARGET_MEM, 8'd1), PROGRAM_FORMAT_96, 3);
		append_image_commands(64'h1400, 36,
			program_destination_pack(PROGRAM_HEMISPHERE_EAST, PROGRAM_TARGET_MEM, 8'd103), PROGRAM_FORMAT_96, 3);
		append_image_commands(64'h1200, 36,
			program_destination_pack(PROGRAM_HEMISPHERE_WEST, PROGRAM_TARGET_MEM, 8'd0), PROGRAM_FORMAT_96, 3);
		append_image_commands(64'h1300, 36,
			program_destination_pack(PROGRAM_HEMISPHERE_WEST, PROGRAM_TARGET_MEM, 8'd1), PROGRAM_FORMAT_96, 3);
		append_image_commands(64'h1500, 36,
			program_destination_pack(PROGRAM_HEMISPHERE_WEST, PROGRAM_TARGET_MEM, 8'd103), PROGRAM_FORMAT_96, 3);
		append_image_commands(64'h2000, 32,
			program_destination_pack(PROGRAM_HEMISPHERE_EAST, PROGRAM_TARGET_MXM_LOAD, 8'd0), PROGRAM_FORMAT_128, 2);
		append_image_commands(64'h2300, 32,
			program_destination_pack(PROGRAM_HEMISPHERE_EAST, PROGRAM_TARGET_MXM_LOAD, 8'd1), PROGRAM_FORMAT_128, 2);
		append_image_commands(64'h2400, 32,
			program_destination_pack(PROGRAM_HEMISPHERE_WEST, PROGRAM_TARGET_MXM_LOAD, 8'd0), PROGRAM_FORMAT_128, 2);
		append_image_commands(64'h2500, 32,
			program_destination_pack(PROGRAM_HEMISPHERE_WEST, PROGRAM_TARGET_MXM_LOAD, 8'd1), PROGRAM_FORMAT_128, 2);
		append_image_commands(64'h2100, 32,
			program_destination_pack(PROGRAM_HEMISPHERE_EAST, PROGRAM_TARGET_MXM_COMPUTE, 8'd0), PROGRAM_FORMAT_128, 2);
		append_image_commands(64'h2200, 32,
			program_destination_pack(PROGRAM_HEMISPHERE_EAST, PROGRAM_TARGET_MXM_DEQUANT, 8'd0), PROGRAM_FORMAT_128, 2);
		append_end();
		start_loader();
		check(!program_command_write_ready, "One active Program Load locks the command RAM");
		serve_dma_image(64'h1000, 36, mem_q0_image);
		serve_dma_image(64'h1100, 36, mem_q1_image);
		serve_dma_image(64'h1400, 36, mem_q103_image);
		serve_dma_image(64'h1200, 36, mem_q104_image);
		serve_dma_image(64'h1300, 36, mem_q105_image);
		serve_dma_image(64'h1500, 36, mem_q207_image);
		serve_dma_image(64'h2000, 32, make_mxm_image(MXM_LOAD));
		serve_dma_image(64'h2300, 32, make_mxm_image(MXM_LOAD));
		serve_dma_image(64'h2400, 32, make_mxm_image(MXM_LOAD));
		serve_dma_image(64'h2500, 32, make_mxm_image(MXM_LOAD));
		serve_dma_image(64'h2100, 32, make_mxm_image(MXM_COMPUTE));
		serve_dma_image(64'h2200, 32, make_mxm_image(MXM_DEQUANT));
		wait_load_and_prime();
		check(!program_start_ack && program_schedule_cycle == 0,
			"Ready does not imply START");
		check(u_dut.u_fu_subsystems.gen_hemisphere[0].u_mem_subsystem.gen_bank_frontend[0].u_frontend.u_imem.data_mem_q[0] === MEM_WORD_0,
			"MEM global Queue 0 routed to East local Queue 0");
		check(u_dut.u_fu_subsystems.gen_hemisphere[0].u_mem_subsystem.gen_bank_frontend[1].u_frontend.u_imem.data_mem_q[1] === mem_q1_image[96+:96],
			"MEM global Queue 1 routed to East local Queue 1");
		check(u_dut.u_fu_subsystems.gen_hemisphere[0].u_mem_subsystem.gen_bank_frontend[103].u_frontend.u_imem.data_mem_q[1] === mem_q103_image[96+:96],
			"MEM global Queue 103 routed to East local Queue 103");
		check(u_dut.u_fu_subsystems.gen_hemisphere[1].u_mem_subsystem.gen_bank_frontend[0].u_frontend.u_imem.data_mem_q[1] === mem_q104_image[96+:96],
			"MEM global Queue 104 routed to West local Queue 0");
		check(u_dut.u_fu_subsystems.gen_hemisphere[1].u_mem_subsystem.gen_bank_frontend[1].u_frontend.u_imem.data_mem_q[1] === mem_q105_image[96+:96],
			"MEM global Queue 105 routed to West local Queue 1");
		check(u_dut.u_fu_subsystems.gen_hemisphere[1].u_mem_subsystem.gen_bank_frontend[103].u_frontend.u_imem.data_mem_q[1] === mem_q207_image[96+:96],
			"MEM global Queue 207 routed to West local Queue 103");
		check(u_dut.u_fu_subsystems.gen_hemisphere[0].gen_mxm[0].u_mxm_subsystem.u_load_frontend.u_imem.data_mem_q[1] === MXM_LOAD,
			"MXM global Queue 0 routed to East local Queue 0");
		check(u_dut.u_fu_subsystems.gen_hemisphere[0].gen_mxm[1].u_mxm_subsystem.u_load_frontend.u_imem.data_mem_q[1] === MXM_LOAD,
			"MXM global Queue 1 routed to East local Queue 1");
		check(u_dut.u_fu_subsystems.gen_hemisphere[1].gen_mxm[0].u_mxm_subsystem.u_load_frontend.u_imem.data_mem_q[1] === MXM_LOAD,
			"MXM global Queue 2 routed to West local Queue 0");
		check(u_dut.u_fu_subsystems.gen_hemisphere[1].gen_mxm[1].u_mxm_subsystem.u_load_frontend.u_imem.data_mem_q[1] === MXM_LOAD,
			"MXM global Queue 3 routed to West local Queue 1");
		check(u_dut.u_fu_subsystems.gen_hemisphere[0].gen_mxm[0].u_mxm_subsystem.u_compute_frontend.u_imem.data_mem_q[1] === MXM_COMPUTE,
			"MXM Compute uses an independent local iMEM");
		check(u_dut.u_fu_subsystems.gen_hemisphere[0].gen_mxm[0].u_mxm_subsystem.u_dequant_frontend.u_imem.data_mem_q[1] === MXM_DEQUANT,
			"MXM Dequant uses an independent local iMEM");

		// System Test A/B/E: reload two Bank-local images and accept an early START only after dependencies.
		pulse_program_reset();
		// Fixed Testbench deposits replace the removed architectural Host-to-MEM path.
		force u_dut.u_fu_subsystems.gen_hemisphere[0].u_mem_subsystem.gen_native_execution.u_native_mem.u_phase2a_data_plane.u_mem.gen_group[0].u_group.gen_slice[0].u_slice.gen_bank[0].u_logical_bank.gen_leaf[0].u_leaf.mem_array[100] = 64'h0101_0202_0303_0404;
		release u_dut.u_fu_subsystems.gen_hemisphere[0].u_mem_subsystem.gen_native_execution.u_native_mem.u_phase2a_data_plane.u_mem.gen_group[0].u_group.gen_slice[0].u_slice.gen_bank[0].u_logical_bank.gen_leaf[0].u_leaf.mem_array[100];
		force u_dut.u_fu_subsystems.gen_hemisphere[0].u_mem_subsystem.gen_native_execution.u_native_mem.u_phase2a_data_plane.u_mem.gen_group[0].u_group.gen_slice[0].u_slice.gen_bank[1].u_logical_bank.gen_leaf[0].u_leaf.mem_array[200] = 64'ha1a1_b2b2_c3c3_d4d4;
		release u_dut.u_fu_subsystems.gen_hemisphere[0].u_mem_subsystem.gen_native_execution.u_native_mem.u_phase2a_data_plane.u_mem.gen_group[0].u_group.gen_slice[0].u_slice.gen_bank[1].u_logical_bank.gen_leaf[0].u_leaf.mem_array[200];
		@(negedge clk);
		program_start_request = 1'b1;
		@(posedge clk);
		@(negedge clk);
		program_start_request = 1'b0;
		program_dependencies_ready = 1'b0;
		next_command = 0;
		append_image_commands(64'h3000, 36,
			program_destination_pack(PROGRAM_HEMISPHERE_EAST, PROGRAM_TARGET_MEM, 8'd0), PROGRAM_FORMAT_96, 3);
		append_image_commands(64'h3100, 36,
			program_destination_pack(PROGRAM_HEMISPHERE_EAST, PROGRAM_TARGET_MEM, 8'd1), PROGRAM_FORMAT_96, 3);
		append_end();
		start_loader();
		serve_dma_image(64'h3000, 36, mem_q0_image);
		serve_dma_image(64'h3100, 36, mem_q1_image);
		wait_load_and_prime();
		check(start_ack_count == 0 && !program_running,
			"Early START remains pending while dependencies are false");
		@(negedge clk);
		program_dependencies_ready = 1'b1;
		timeout = 0;
		while(start_ack_count == 0 && timeout < 50)begin
			@(negedge clk);
			timeout = timeout + 1;
		end
		check(start_ack_count == 1 && program_running,
			"Unified START begins all Frontends on one boundary");
		check(program_schedule_cycle == 0, "START exposes Schedule Cycle 0");
		timeout = 0;
		while(!(program_schedule_cycle == 5 && u_dut.local_mem_issue_valid[0] &&
			u_dut.local_mem_issue_valid[1]) && timeout < 100)begin
			@(negedge clk);
			timeout = timeout + 1;
		end
		check(timeout < 100, "Both MEM Banks issue together at Schedule Cycle 5");
		check(u_dut.local_mem_issue_instruction[15+:13] == 13'd100 &&
			u_dut.local_mem_issue_instruction[lpu_pkg::MEM_INSTRUCTION_WIDTH+15+:13] == 13'd200,
			"Bank-local Queue instructions retain addresses 100 and 200");
		check(u_dut.local_mem_issue_valid[1:0] == 2'b11 &&
			u_dut.u_fu_subsystems.gen_hemisphere[0].u_mem_subsystem.gen_native_execution.native_issue_valid[1:0] == 2'b11,
			"Frontend Queues reach the actual MEM FU issue interface");
		timeout = 0;
		while(!(u_dut.u_fu_subsystems.gen_hemisphere[0].u_mem_subsystem.gen_native_execution.u_native_mem.mem_producer_valid_o[0] &&
			u_dut.u_fu_subsystems.gen_hemisphere[0].u_mem_subsystem.gen_native_execution.u_native_mem.mem_producer_valid_o[4]) && timeout < 20)begin
			@(negedge clk);
			timeout = timeout + 1;
		end
		check(timeout < 20, "Both Native Banks complete their READ pipeline");
		check(u_dut.u_fu_subsystems.gen_hemisphere[0].u_mem_subsystem.gen_native_execution.u_native_mem.mem_producer_data_o[0+:64] == 64'h0101_0202_0303_0404,
			"Bank 0 executed READ 100 against its SRAM");
		check(u_dut.u_fu_subsystems.gen_hemisphere[0].u_mem_subsystem.gen_native_execution.u_native_mem.mem_producer_data_o[4*64+:64] == 64'ha1a1_b2b2_c3c3_d4d4,
			"Bank 1 executed READ 200 against its SRAM");
		timeout = 0;
		while(!program_done && !program_fault && timeout < 200)begin
			@(negedge clk);
			timeout = timeout + 1;
		end
		check(program_done && !program_fault, "Two-Column Program reaches Done without fault");

		// System Test F/H: switch Program without resetting the physical SRAM and issue at Cycle 0.
		edge_before_switch = physical_clock_edges;
		pulse_program_reset();
		check(physical_clock_edges > edge_before_switch, "Program switch keeps physical time alive");
		#1;
		check(u_dut.u_fu_subsystems.gen_hemisphere[0].u_mem_subsystem.gen_native_execution.u_native_mem.u_phase2a_data_plane.u_mem.gen_group[0].u_group.gen_slice[0].u_slice.gen_bank[0].u_logical_bank.gen_leaf[0].u_leaf.mem_array[100] == 64'h0101_0202_0303_0404,
			"Program switch preserves shared physical SRAM contents");
		cycle0_image = make_mem_image(0, 10, 3);
		start_ack_count = 0;
		program_dependencies_ready = 1'b1;
		@(negedge clk);
		program_start_request = 1'b1;
		@(posedge clk);
		@(negedge clk);
		program_start_request = 1'b0;
		next_command = 0;
		append_image_commands(64'h4000, 36,
			program_destination_pack(PROGRAM_HEMISPHERE_EAST, PROGRAM_TARGET_MEM, 8'd0), PROGRAM_FORMAT_96, 3);
		append_end();
		start_loader();
		serve_dma_image(64'h4000, 36, cycle0_image);
		wait_load_and_prime();
		timeout = 0;
		while(!(program_schedule_cycle == 0 && u_dut.local_mem_issue_valid[0]) && timeout < 100)begin
			@(negedge clk);
			timeout = timeout + 1;
		end
		check(timeout < 100 && start_ack_count == 1,
			"Second Program emits its first instruction at Schedule Cycle 0");
		check(u_dut.local_mem_issue_instruction[15+:13] == 13'd10,
			"Cycle-0 instruction belongs to the new Program");

		// System Test G: descriptor checks reject an invalid Queue and an overflowing iMEM image.
		pulse_program_reset();
		write_command(0, PROGRAM_LOADER_LOAD_IMEM, 64'h5000, 36,
			program_destination_pack(PROGRAM_HEMISPHERE_EAST, PROGRAM_TARGET_MEM, 8'd104),
			PROGRAM_FORMAT_96, 3, 17'd0, PROGRAM_ENCODING_MACRO);
		@(negedge clk);
		check(program_fault && program_fault_code == PROGRAM_FAULT_DESCRIPTOR,
			"Out-of-range MEM Target Index is rejected");
		pulse_program_reset();
		write_command(0, PROGRAM_LOADER_LOAD_IMEM, 64'h5050, 32,
			program_destination_pack(PROGRAM_HEMISPHERE_EAST, PROGRAM_TARGET_MXM_LOAD, 8'd2),
			PROGRAM_FORMAT_128, 2, 17'd0, PROGRAM_ENCODING_MACRO);
		@(negedge clk);
		check(program_fault && program_fault_code == PROGRAM_FAULT_DESCRIPTOR,
			"Out-of-range MXM Target Index is rejected");
		pulse_program_reset();
		write_command(0, PROGRAM_LOADER_LOAD_IMEM, 64'h5080, 32,
			program_destination_pack(PROGRAM_HEMISPHERE_EAST, PROGRAM_TARGET_RESERVED, 8'd0),
			PROGRAM_FORMAT_128, 2, 17'd0, PROGRAM_ENCODING_MACRO);
		@(negedge clk);
		check(program_fault && program_fault_code == PROGRAM_FAULT_DESCRIPTOR,
			"Reserved Target Kind is rejected");
		pulse_program_reset();
		write_command(0, PROGRAM_LOADER_LOAD_IMEM, 64'h5090, 32,
			program_destination_pack(PROGRAM_HEMISPHERE_EAST, PROGRAM_TARGET_VXM, 8'd0),
			PROGRAM_FORMAT_128, 2, 17'd0, PROGRAM_ENCODING_MACRO);
		@(negedge clk);
		check(program_fault && program_fault_code == PROGRAM_FAULT_DESCRIPTOR,
			"VXM Program Load remains explicitly unconnected");
		pulse_program_reset();
		write_command(0, PROGRAM_LOADER_LOAD_IMEM, 64'h50a0, 32,
			program_destination_pack(PROGRAM_HEMISPHERE_EAST, PROGRAM_TARGET_SXM_TRANSPOSE, 8'd0),
			PROGRAM_FORMAT_128, 2, 17'd0, PROGRAM_ENCODING_MACRO);
		@(negedge clk);
		check(program_fault && program_fault_code == PROGRAM_FAULT_DESCRIPTOR,
			"SXM Transpose Program Load remains explicitly unconnected");
		pulse_program_reset();
		write_command(0, PROGRAM_LOADER_LOAD_IMEM, 64'h50b0, 32,
			program_destination_pack(PROGRAM_HEMISPHERE_EAST, PROGRAM_TARGET_SXM_PERMUTE, 8'd0),
			PROGRAM_FORMAT_128, 2, 17'd0, PROGRAM_ENCODING_MACRO);
		@(negedge clk);
		check(program_fault && program_fault_code == PROGRAM_FAULT_DESCRIPTOR,
			"SXM Permute Program Load remains explicitly unconnected");
		pulse_program_reset();
		write_command(0, PROGRAM_LOADER_LOAD_IMEM, 64'h5100, 36,
			program_destination_pack(PROGRAM_HEMISPHERE_EAST, PROGRAM_TARGET_MEM, 8'd0),
			PROGRAM_FORMAT_96, 3, 17'd15, PROGRAM_ENCODING_MACRO);
		@(negedge clk);
		check(program_fault && program_fault_code == PROGRAM_FAULT_DESCRIPTOR,
			"ProgramImage exceeding local iMEM capacity is rejected");
		pulse_program_reset();
		write_command(0, PROGRAM_LOADER_LOAD_IMEM, 64'h5200, 36,
			program_destination_pack(PROGRAM_HEMISPHERE_EAST, PROGRAM_TARGET_MEM, 8'd0),
			PROGRAM_FORMAT_96, 3, 17'd0, PROGRAM_ENCODING_FU3D);
		@(negedge clk);
		check(program_fault && program_fault_code == PROGRAM_FAULT_DESCRIPTOR,
			"FU3D encoding is rejected by the Macro-only Program Control path");

		$display("LPU_TOP_FU_SUBSYSTEM_PROGRAM PASS checks=%0d physical_edges=%0d", checks, physical_clock_edges);
		$finish;
	end
endmodule
