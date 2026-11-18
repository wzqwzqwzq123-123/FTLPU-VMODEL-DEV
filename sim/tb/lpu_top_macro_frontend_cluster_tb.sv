`timescale 1ns/1ps

// Current top-level Macro Frontend integration test. Program data enters only
// through the public Program Loader/DMA-response interface; the retired direct
// macro_* issue ports are intentionally not recreated.
module lpu_top_macro_frontend_cluster_tb;
	import lpu_program_load_pkg::*;

	localparam integer COMMAND_DEPTH = 16;
	localparam integer COMMAND_ADDRESS_WIDTH = $clog2(COMMAND_DEPTH);
	localparam logic [1:0] PROGRAM_ENCODING_MACRO = 2'd0;
	localparam logic [95:0] MEM_WORD_0 = 96'h00000000_00000000_00000025;
	localparam logic [95:0] MEM_WORD_1 = 96'h00303200_00000180_02000021;
	localparam logic [95:0] MEM_WORD_2 = 96'h00000000_00000000_00000400;
	localparam logic [127:0] MXM_CONTROL = 128'h00000000000000000000000000000017;
	localparam logic [127:0] MXM_LOAD = 128'h00000000000000000400000800000028;

	logic clk;
	logic rst_n;
	logic program_reset;
	logic program_cmd_write_valid;
	logic program_cmd_write_ready;
	logic [COMMAND_ADDRESS_WIDTH-1:0] program_cmd_write_address;
	logic [2:0] program_cmd_write_opcode;
	logic [63:0] program_cmd_write_source_address;
	logic [31:0] program_cmd_write_byte_count;
	logic [11:0] program_cmd_write_destination;
	logic [1:0] program_cmd_write_format;
	logic [1:0] program_cmd_write_encoding_mode;
	logic [16:0] program_cmd_write_imem_base_address;
	logic program_cmd_write_image_first;
	logic program_cmd_write_image_last;
	logic [15:0] program_cmd_write_expected_word_count;
	logic [COMMAND_ADDRESS_WIDTH-1:0] program_cmd_write_jump_address;
	logic program_load_start_valid;
	logic program_load_start_ready;
	logic [COMMAND_ADDRESS_WIDTH:0] program_load_start_command_count;
	logic program_ddr_read_req_valid;
	logic program_ddr_read_req_ready;
	logic [63:0] program_ddr_read_req_address;
	logic [31:0] program_ddr_read_req_length;
	logic [7:0] program_ddr_read_req_id;
	logic program_ddr_read_rsp_valid;
	logic program_ddr_read_rsp_ready;
	logic [255:0] program_ddr_read_rsp_data;
	logic [31:0] program_ddr_read_rsp_keep;
	logic program_ddr_read_rsp_last;
	logic [7:0] program_ddr_read_rsp_id;
	logic program_ddr_read_rsp_error;
	logic program_start_request;
	logic program_start_ack;
	logic program_load_complete;
	logic program_ready;
	logic program_running;
	logic program_done;
	logic program_fault;
	logic [5:0] program_fault_code;
	logic [31:0] program_schedule_cycle;

	integer next_command;
	integer checks;
	integer timeout;
	integer mem_issue_seen;
	integer mxm_issue_seen;
	integer start_ack_count;

	always #5 clk = ~clk;

	always @(posedge clk) begin
		if(!rst_n)begin
			start_ack_count <= 0;
		end
		else if(program_start_ack)begin
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

	function automatic logic [255:0] make_mxm_image;
		begin
			make_mxm_image = {MXM_LOAD, MXM_CONTROL};
		end
	endfunction

	lpu_top #(
		.MEM_DEPTH_ROWS(256),
		.ACTIVE_MEM_COLUMNS(1),
		.PROGRAM_COMMAND_DEPTH(COMMAND_DEPTH),
		.PROGRAM_MEM_IMEM_DEPTH(16),
		.PROGRAM_MXM_IMEM_DEPTH(16),
		.PROGRAM_ACTIVE_CONTEXTS(4)
	) u_dut (
		.clk_i(clk),
		.rst_ni(rst_n),
		.program_reset_i(program_reset),
		.program_cmd_write_valid_i(program_cmd_write_valid),
		.program_cmd_write_ready_o(program_cmd_write_ready),
		.program_cmd_write_address_i(program_cmd_write_address),
		.program_cmd_write_opcode_i(program_cmd_write_opcode),
		.program_cmd_write_source_address_i(program_cmd_write_source_address),
		.program_cmd_write_byte_count_i(program_cmd_write_byte_count),
		.program_cmd_write_destination_i(program_cmd_write_destination),
		.program_cmd_write_format_i(program_cmd_write_format),
		.program_cmd_write_encoding_mode_i(program_cmd_write_encoding_mode),
		.program_cmd_write_imem_base_address_i(program_cmd_write_imem_base_address),
		.program_cmd_write_image_first_i(program_cmd_write_image_first),
		.program_cmd_write_image_last_i(program_cmd_write_image_last),
		.program_cmd_write_expected_word_count_i(program_cmd_write_expected_word_count),
		.program_cmd_write_jump_address_i(program_cmd_write_jump_address),
		.program_load_start_valid_i(program_load_start_valid),
		.program_load_start_ready_o(program_load_start_ready),
		.program_load_start_command_count_i(program_load_start_command_count),
		.program_ddr_read_req_valid_o(program_ddr_read_req_valid),
		.program_ddr_read_req_ready_i(program_ddr_read_req_ready),
		.program_ddr_read_req_address_o(program_ddr_read_req_address),
		.program_ddr_read_req_length_o(program_ddr_read_req_length),
		.program_ddr_read_req_id_o(program_ddr_read_req_id),
		.program_ddr_read_rsp_valid_i(program_ddr_read_rsp_valid),
		.program_ddr_read_rsp_ready_o(program_ddr_read_rsp_ready),
		.program_ddr_read_rsp_data_i(program_ddr_read_rsp_data),
		.program_ddr_read_rsp_keep_i(program_ddr_read_rsp_keep),
		.program_ddr_read_rsp_last_i(program_ddr_read_rsp_last),
		.program_ddr_read_rsp_id_i(program_ddr_read_rsp_id),
		.program_ddr_read_rsp_error_i(program_ddr_read_rsp_error),
		.program_start_request_i(program_start_request),
		.program_dependencies_ready_i(1'b1),
		.program_start_ack_o(program_start_ack),
		.program_load_complete_o(program_load_complete),
		.program_ready_o(program_ready),
		.program_running_o(program_running),
		.program_done_o(program_done),
		.program_fault_o(program_fault),
		.program_fault_code_o(program_fault_code),
		.program_schedule_cycle_o(program_schedule_cycle),
		.qctl_load_mode_i(1'b0),
		.qctl_partition_valid_i(1'b0),
		.qctl_partition_ready_o(),
		.qctl_partition_queue_i('0),
		.qctl_partition_base_i('0),
		.qctl_partition_count_i('0),
		.qctl_partition_generation_i('0),
		.qctl_load_valid_i(1'b0),
		.qctl_load_ready_o(),
		.qctl_load_address_i('0),
		.qctl_load_data_i('0),
		.qctl_sync_participant_mask_i('0),
		.qctl_event_valid_i('0),
		.qctl_event_ready_o(),
		.qctl_event_tag_i('0),
		.qctl_mem_packet_valid_o(),
		.qctl_mem_packet_ordinal_o(),
		.qctl_mem_packet_retired_i('0),
		.qctl_queue_active_o(),
		.qctl_wait_event_blocked_o(),
		.qctl_wait_event_tag_o(),
		.qctl_primed_o(),
		.qctl_done_o(),
		.qctl_fault_o(),
		.qctl_fault_code_o(),
		.mem_east_edge_valid_i('0),
		.mem_east_edge_data_i('0),
		.mem_east_edge_valid_o(),
		.mem_east_edge_data_o(),
		.mem_west_edge_valid_i('0),
		.mem_west_edge_data_i('0),
		.mem_west_edge_valid_o(),
		.mem_west_edge_data_o(),
		.mem_fault_o(),
		.mxm_fault_o(),
		.sxm_fault_o(),
		.vxm_fault_o(),
		.stream_conflict_o(),
		.cycle_o()
	);

	task automatic check(input logic condition, input string label);
		begin
			if(!condition)begin
				$fatal(1, "FAIL %s schedule=%0d program_fault=%0b code=%0d", label,
					program_schedule_cycle, program_fault, program_fault_code);
			end
			checks = checks + 1;
		end
	endtask

	task automatic pulse_program_reset;
		begin
			@(negedge clk);
			program_reset = 1'b1;
			@(posedge clk);
			@(negedge clk);
			program_reset = 1'b0;
			repeat(2) @(posedge clk);
			check(program_schedule_cycle == 0 && !program_running && !program_done,
				"Program Reset clears Program control state");
		end
	endtask

	task automatic write_command(
		input integer address,
		input logic [2:0] opcode,
		input logic [63:0] source_address,
		input logic [31:0] byte_count,
		input logic [11:0] destination,
		input logic [1:0] format,
		input logic [15:0] expected_words
	);
		begin
			@(negedge clk);
			program_cmd_write_address = address[COMMAND_ADDRESS_WIDTH-1:0];
			program_cmd_write_opcode = opcode;
			program_cmd_write_source_address = source_address;
			program_cmd_write_byte_count = byte_count;
			program_cmd_write_destination = destination;
			program_cmd_write_format = format;
			program_cmd_write_encoding_mode = PROGRAM_ENCODING_MACRO;
			program_cmd_write_imem_base_address = '0;
			program_cmd_write_image_first = 1'b1;
			program_cmd_write_image_last = 1'b1;
			program_cmd_write_expected_word_count = expected_words;
			program_cmd_write_jump_address = '0;
			program_cmd_write_valid = 1'b1;
			check(program_cmd_write_ready, "Program command RAM accepts descriptor");
			@(posedge clk);
			@(negedge clk);
			program_cmd_write_valid = 1'b0;
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
			write_command(next_command, PROGRAM_LOADER_LOAD_IMEM, source_address,
				byte_count, destination, format, expected_words);
			next_command = next_command + 1;
			write_command(next_command, PROGRAM_LOADER_WAIT_DMA, 0, 0,
				destination, format, expected_words);
			next_command = next_command + 1;
			write_command(next_command, PROGRAM_LOADER_COMMIT_QUEUE, 0, 0,
				destination, format, expected_words);
			next_command = next_command + 1;
		end
	endtask

	task automatic append_end;
		begin
			write_command(next_command, PROGRAM_LOADER_END, 0, 0,
				program_destination_pack(PROGRAM_HEMISPHERE_EAST, PROGRAM_TARGET_MEM, 8'd0),
				PROGRAM_FORMAT_96, 0);
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
			program_ddr_read_rsp_data = data;
			program_ddr_read_rsp_keep = keep;
			program_ddr_read_rsp_last = last;
			program_ddr_read_rsp_id = id;
			program_ddr_read_rsp_valid = 1'b1;
			timeout = 0;
			while(!program_ddr_read_rsp_ready && timeout < 100)begin
				@(negedge clk);
				timeout = timeout + 1;
			end
			check(program_ddr_read_rsp_ready, "DMA response accepted under ready/valid");
			@(posedge clk);
			@(negedge clk);
			program_ddr_read_rsp_valid = 1'b0;
		end
	endtask

	task automatic serve_dma_image(
		input logic [63:0] expected_address,
		input integer byte_count,
		input logic [287:0] image
	);
		logic [7:0] dma_id;
		begin
			timeout = 0;
			while(!program_ddr_read_req_valid && timeout < 500)begin
				@(negedge clk);
				timeout = timeout + 1;
			end
			check(program_ddr_read_req_valid, "Program Loader emits DMA command");
			check(program_ddr_read_req_address == expected_address &&
				program_ddr_read_req_length == byte_count,
				"Program descriptor preserves source address and byte count");
			dma_id = program_ddr_read_req_id;
			program_ddr_read_req_ready = 1'b1;
			@(posedge clk);
			@(negedge clk);
			program_ddr_read_req_ready = 1'b0;
			if(byte_count <= 32)begin
				send_dma_beat(image[0+:256], 32'hffff_ffff >> (32-byte_count), 1'b1, dma_id);
			end
			else begin
				send_dma_beat(image[0+:256], 32'hffff_ffff, 1'b0, dma_id);
				send_dma_beat({224'd0, image[256+:32]}, 32'h0000_000f, 1'b1, dma_id);
			end
		end
	endtask

	task automatic wait_for_program_ready;
		begin
			timeout = 0;
			while(!program_load_complete && timeout < 2000)begin
				@(negedge clk);
				check(program_schedule_cycle == 0 && !program_running,
					"WRITE and Commit do not advance Schedule Cycle");
				timeout = timeout + 1;
			end
			check(program_load_complete, "All Program writes commit before Load Complete");
			timeout = 0;
			while(!program_ready && timeout < 2000)begin
				@(negedge clk);
				check(program_schedule_cycle == 0 && !program_running,
					"PRIME does not advance Schedule Cycle");
				timeout = timeout + 1;
			end
			check(program_ready && !program_fault,
				"MEM and MXM Frontends reach Ready after PRIME");
		end
	endtask

	initial begin
		logic [287:0] mem_image;

		clk = 1'b0;
		rst_n = 1'b0;
		program_reset = 1'b0;
		program_cmd_write_valid = 1'b0;
		program_cmd_write_address = '0;
		program_cmd_write_opcode = '0;
		program_cmd_write_source_address = '0;
		program_cmd_write_byte_count = '0;
		program_cmd_write_destination = '0;
		program_cmd_write_format = '0;
		program_cmd_write_encoding_mode = '0;
		program_cmd_write_imem_base_address = '0;
		program_cmd_write_image_first = 1'b0;
		program_cmd_write_image_last = 1'b0;
		program_cmd_write_expected_word_count = '0;
		program_cmd_write_jump_address = '0;
		program_load_start_valid = 1'b0;
		program_load_start_command_count = '0;
		program_ddr_read_req_ready = 1'b0;
		program_ddr_read_rsp_valid = 1'b0;
		program_ddr_read_rsp_data = '0;
		program_ddr_read_rsp_keep = '0;
		program_ddr_read_rsp_last = 1'b0;
		program_ddr_read_rsp_id = '0;
		program_ddr_read_rsp_error = 1'b0;
		program_start_request = 1'b0;
		next_command = 0;
		checks = 0;
		timeout = 0;
		mem_issue_seen = 0;
		mxm_issue_seen = 0;
		start_ack_count = 0;

		repeat(5) @(posedge clk);
		@(negedge clk);
		rst_n = 1'b1;

		check(program_destination_pack(PROGRAM_HEMISPHERE_EAST,
			PROGRAM_TARGET_MEM, 8'd0) == 12'h000,
			"12-bit Destination encodes East MEM Queue 0");
		check(program_destination_pack(PROGRAM_HEMISPHERE_EAST,
			PROGRAM_TARGET_MXM_LOAD, 8'd0) == 12'h100,
			"12-bit Destination encodes East MXM Load Queue 0");

		mem_image = make_mem_image(3, 13'd100, 6'd1);
		append_image_commands(64'h1000, 36,
			program_destination_pack(PROGRAM_HEMISPHERE_EAST, PROGRAM_TARGET_MEM, 8'd0),
			PROGRAM_FORMAT_96, 3);
		append_image_commands(64'h2000, 32,
			program_destination_pack(PROGRAM_HEMISPHERE_EAST, PROGRAM_TARGET_MXM_LOAD, 8'd0),
			PROGRAM_FORMAT_128, 2);
		append_end();
		start_loader();
		serve_dma_image(64'h1000, 36, mem_image);
		serve_dma_image(64'h2000, 32, {32'd0, make_mxm_image()});
		wait_for_program_ready();

		check(!program_start_ack && program_schedule_cycle == 0,
			"Frontend Ready does not imply START");
		@(negedge clk);
		program_start_request = 1'b1;
		@(posedge clk);
		@(negedge clk);
		program_start_request = 1'b0;
		timeout = 0;
		while(start_ack_count == 0 && timeout < 20)begin
			@(negedge clk);
			timeout = timeout + 1;
		end
		check(start_ack_count == 1 && program_running && program_schedule_cycle == 0,
			"Unified START begins at Schedule Cycle 0");

		timeout = 0;
		while((mem_issue_seen == 0 || mxm_issue_seen == 0) && timeout < 100)begin
			@(negedge clk);
			if(u_dut.local_mem_issue_valid[0])begin
				mem_issue_seen = mem_issue_seen + 1;
				check(program_schedule_cycle == 3,
					"MEM Macro instruction issues at absolute Cycle 3");
				check(u_dut.local_mem_issue_instruction[15+:13] == 13'd100,
					"MEM Macro preserves decoded address 100");
			end
			if(u_dut.local_mxm_load_issue_valid[0])begin
				mxm_issue_seen = mxm_issue_seen + 1;
				check(program_schedule_cycle == 5,
					"MXM Load Macro instruction issues at absolute Cycle 5");
				check(u_dut.local_mxm_load_issue_instruction[0+:29] == 29'h00000008,
					"MXM Load Macro preserves decoded native instruction");
			end
			timeout = timeout + 1;
		end
		check(mem_issue_seen == 1 && mxm_issue_seen == 1,
			"Each current Macro Frontend issues exactly once");
		check(!program_fault,
			"Current MEM/MXM Macro path completes without Program fault");

		pulse_program_reset();
		write_command(0, PROGRAM_LOADER_LOAD_IMEM, 64'h3000, 32,
			program_destination_pack(PROGRAM_HEMISPHERE_EAST,
				PROGRAM_TARGET_SXM_TRANSPOSE, 8'd0), PROGRAM_FORMAT_128, 2);
		@(negedge clk);
		check(program_fault && program_fault_code == PROGRAM_FAULT_DESCRIPTOR,
			"Unintegrated SXM endpoint cannot produce a false acceptance");
		pulse_program_reset();
		write_command(0, PROGRAM_LOADER_LOAD_IMEM, 64'h4000, 32,
			program_destination_pack(PROGRAM_HEMISPHERE_EAST,
				PROGRAM_TARGET_VXM, 8'd0), PROGRAM_FORMAT_128, 2);
		@(negedge clk);
		check(program_fault && program_fault_code == PROGRAM_FAULT_DESCRIPTOR,
			"Unintegrated VXM endpoint cannot produce a false acceptance");

		$display("LPU_TOP_MACRO_CLUSTER PASS checks=%0d", checks);
		$finish;
	end
endmodule
