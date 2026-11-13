module lpu_top #(
	parameter integer ICU_QUEUE_DEPTH = 16,
	parameter integer MEM_DEPTH_ROWS = lpu_pkg::SRAM_DEPTH_ROWS,
	parameter integer ACTIVE_MEM_COLUMNS = 52,
	parameter integer MXM_ACCUMULATOR_BLOCK_COUNT = lpu_pkg::MXM_ACCUMULATOR_BLOCK_COUNT,
	parameter bit USE_SRAM_MACRO = 1'b0,
	parameter bit USE_NATIVE_MEM = 1'b1,
	parameter bit ENABLE_DISTRIBUTED_PROGRAM_FRONTEND = 1'b0,
	parameter integer PROGRAM_COMMAND_DEPTH = 32,
	parameter integer PROGRAM_DMA_DATA_WIDTH = 256,
	parameter integer PROGRAM_MEM_IMEM_DEPTH = 131072,
	parameter integer PROGRAM_MXM_IMEM_DEPTH = 65536,
	parameter integer PROGRAM_ACTIVE_CONTEXTS = 4,
	parameter bit ENABLE_QCTL = 1'b0,
	parameter integer QCTL_QUEUE_COUNT = 220,
	parameter integer PROGRAM_COMMAND_ADDRESS_WIDTH = PROGRAM_COMMAND_DEPTH <= 1 ? 1 : $clog2(PROGRAM_COMMAND_DEPTH)
) (
	input logic clk_i,
	input logic rst_ni,
	input logic run_i,
	input logic schedule_valid_i,
	output logic schedule_ready_o,
	input logic [7:0] schedule_queue_i,
	input logic schedule_is_instruction_i,
	input logic [31:0] schedule_command_i,
	input logic [415:0] schedule_payload_i,

	// Program Loader owns image descriptors and response reassembly after the external DMA.
	input logic program_reset_i,
	input logic program_command_write_valid_i,
	output logic program_command_write_ready_o,
	input logic [PROGRAM_COMMAND_ADDRESS_WIDTH-1:0] program_command_write_address_i,
	input logic [2:0] program_command_write_opcode_i,
	input logic [63:0] program_command_write_source_address_i,
	input logic [31:0] program_command_write_byte_count_i,
	input logic [11:0] program_command_write_destination_i,
	input logic [1:0] program_command_write_format_i,
	input logic [1:0] program_command_write_encoding_mode_i,
	input logic [16:0] program_command_write_imem_base_address_i,
	input logic program_command_write_image_first_i,
	input logic program_command_write_image_last_i,
	input logic [15:0] program_command_write_expected_word_count_i,
	input logic [PROGRAM_COMMAND_ADDRESS_WIDTH-1:0] program_command_write_jump_address_i,
	input logic program_load_start_valid_i,
	output logic program_load_start_ready_o,
	input logic [PROGRAM_COMMAND_ADDRESS_WIDTH:0] program_load_start_command_count_i,
	output logic program_dma_cmd_valid_o,
	input logic program_dma_cmd_ready_i,
	output logic [63:0] program_dma_cmd_address_o,
	output logic [31:0] program_dma_cmd_length_o,
	output logic [7:0] program_dma_cmd_id_o,
	input logic program_dma_rsp_valid_i,
	output logic program_dma_rsp_ready_o,
	input logic [PROGRAM_DMA_DATA_WIDTH-1:0] program_dma_rsp_data_i,
	input logic [PROGRAM_DMA_DATA_WIDTH/8-1:0] program_dma_rsp_keep_i,
	input logic program_dma_rsp_last_i,
	input logic [7:0] program_dma_rsp_id_i,
	input logic program_dma_rsp_error_i,
	input logic program_start_request_i,
	input logic program_dependencies_ready_i,
	output logic program_start_ack_o,
	output logic program_load_complete_o,
	output logic program_ready_o,
	output logic program_running_o,
	output logic program_done_o,
	output logic program_fault_o,
	output logic [5:0] program_fault_code_o,
	output logic [31:0] program_schedule_cycle_o,

	// Shared QCTL storage serves one Queue-local Controller per supported MEM/MXM stream.
	input logic qctl_load_mode_i,
	input logic qctl_partition_valid_i,
	output logic qctl_partition_ready_o,
	input logic [$clog2(QCTL_QUEUE_COUNT)-1:0] qctl_partition_queue_i,
	input logic [8:0] qctl_partition_base_i,
	input logic [4:0] qctl_partition_count_i,
	input logic [63:0] qctl_partition_generation_i,
	input logic qctl_load_valid_i,
	output logic qctl_load_ready_o,
	input logic [8:0] qctl_load_address_i,
	input logic [95:0] qctl_load_data_i,
	input logic [QCTL_QUEUE_COUNT-1:0] qctl_event_valid_i,
	output logic [QCTL_QUEUE_COUNT-1:0] qctl_event_ready_o,
	input logic [QCTL_QUEUE_COUNT*32-1:0] qctl_event_tag_i,
	input logic [QCTL_QUEUE_COUNT-1:0] qctl_sync_valid_i,
	output logic [QCTL_QUEUE_COUNT-1:0] qctl_sync_ready_o,
	output logic [QCTL_QUEUE_COUNT-1:0] qctl_notify_valid_o,
	input logic [QCTL_QUEUE_COUNT-1:0] qctl_notify_ready_i,
	output logic [QCTL_QUEUE_COUNT-1:0] qctl_mem_packet_valid_o,
	output logic [QCTL_QUEUE_COUNT*32-1:0] qctl_mem_packet_ordinal_o,
	input logic [QCTL_QUEUE_COUNT-1:0] qctl_mem_packet_retired_i,
	output logic [QCTL_QUEUE_COUNT-1:0] qctl_queue_active_o,
	output logic [QCTL_QUEUE_COUNT-1:0] qctl_wait_event_blocked_o,
	output logic [QCTL_QUEUE_COUNT*32-1:0] qctl_wait_event_tag_o,
	output logic [QCTL_QUEUE_COUNT-1:0] qctl_primed_o,
	output logic [QCTL_QUEUE_COUNT-1:0] qctl_done_o,
	output logic qctl_fault_o,
	output logic [7:0] qctl_fault_code_o,

	input logic [2*4*32-1:0] mem_east_edge_valid_i,
	input logic [2*4*32*64-1:0] mem_east_edge_data_i,
	output logic [2*4*32-1:0] mem_east_edge_valid_o,
	output logic [2*4*32*64-1:0] mem_east_edge_data_o,
	input logic [2*4*32-1:0] mem_west_edge_valid_i,
	input logic [2*4*32*64-1:0] mem_west_edge_data_i,
	output logic [2*4*32-1:0] mem_west_edge_valid_o,
	output logic [2*4*32*64-1:0] mem_west_edge_data_o,
	output logic [137:0] dispatch_valid_o,
	output logic [138*416-1:0] dispatch_payload_o,
	output logic [137:0] queue_fault_o,
	output logic [lpu_pkg::MEM_BANK_COUNT-1:0] mem_fault_o,
	output logic [1:0] mxm_fault_o,
	output logic [1:0] sxm_fault_o,
	output logic vxm_fault_o,
	output logic [1:0] stream_conflict_o,
	output logic [63:0] cycle_o
);
	localparam integer LEGACY_MEM_QUEUE_COUNT = 104;
	localparam integer MEM_BANK_COUNT = lpu_pkg::MEM_BANK_COUNT;

	logic legacy_schedule_ready;
	logic [137:0] legacy_dispatch_valid;
	logic [138*416-1:0] legacy_dispatch_payload;
	logic [137:0] legacy_queue_fault;
	logic [63:0] legacy_cycle_q;
	logic [MEM_BANK_COUNT-1:0] external_mem_issue_valid;
	logic [MEM_BANK_COUNT-1:0] external_mem_issue_ready;
	logic [MEM_BANK_COUNT*lpu_pkg::MEM_INSTRUCTION_WIDTH-1:0] external_mem_issue_instruction;
	logic [3:0] external_mxm_load_issue_valid;
	logic [4*48-1:0] external_mxm_load_issue_instruction;
	logic [3:0] external_mxm_dequant_issue_valid;
	logic [4*16-1:0] external_mxm_dequant_issue_instruction;
	logic [3:0] external_mxm_compute_issue_valid;
	logic [4*48-1:0] external_mxm_compute_issue_instruction;
	logic [1:0] external_sxm_transpose_issue_valid;
	logic [2*416-1:0] external_sxm_transpose_issue_instruction;
	logic [1:0] external_sxm_permute_issue_valid;
	logic [2*416-1:0] external_sxm_permute_issue_instruction;
	logic [7:0] external_vxm_local_issue_valid;
	logic [8*lpu_pkg::VXM_LOCAL_MAX_INSTRUCTION_WIDTH-1:0] external_vxm_local_issue_instruction;
	logic external_vxm_global_issue_valid;
	logic [lpu_pkg::VXM_GLOBAL_CONFIG_WIDTH-1:0] external_vxm_global_issue_instruction;
	logic [MEM_BANK_COUNT-1:0] local_mem_issue_valid;
	logic [MEM_BANK_COUNT*lpu_pkg::MEM_INSTRUCTION_WIDTH-1:0] local_mem_issue_instruction;
	logic [MEM_BANK_COUNT*32-1:0] local_mem_issue_cycle;
	logic [3:0] local_mxm_load_issue_valid;
	logic [4*29-1:0] local_mxm_load_issue_instruction;
	logic [4*32-1:0] local_mxm_load_issue_cycle;
	logic [3:0] local_mxm_dequant_issue_valid;
	logic [4*16-1:0] local_mxm_dequant_issue_instruction;
	logic [4*32-1:0] local_mxm_dequant_issue_cycle;
	logic [3:0] local_mxm_compute_issue_valid;
	logic [4*49-1:0] local_mxm_compute_issue_instruction;
	logic [4*32-1:0] local_mxm_compute_issue_cycle;
	logic [137:0] program_dispatch_valid;
	logic [138*416-1:0] program_dispatch_payload;
	logic program_distribute_valid;
	logic program_distribute_ready;
	logic [lpu_program_load_pkg::PROGRAM_LOAD_CONTROL_WIDTH-1:0] program_distribute_control;
	logic [127:0] program_distribute_data;
	logic [3:0] program_distribute_strb;
	logic [1:0] program_distribute_scope;
	logic [11:0] program_distribute_destination;
	logic [16:0] program_distribute_imem_address;
	logic program_distribute_last;
	logic program_distribute_idle;
	logic program_distribute_fault;
	logic [5:0] program_distribute_fault_code;
	logic endpoint_program_start;
	logic endpoint_program_start_ready;
	logic endpoint_started;
	logic endpoint_frontends_ready;
	logic endpoint_frontends_idle;
	logic endpoint_fault;
	logic [5:0] endpoint_fault_code;
	logic [31:0] endpoint_schedule_cycle;

	assign schedule_ready_o = ENABLE_DISTRIBUTED_PROGRAM_FRONTEND ? 1'b0 : legacy_schedule_ready;
	assign dispatch_valid_o = ENABLE_DISTRIBUTED_PROGRAM_FRONTEND ? program_dispatch_valid : legacy_dispatch_valid;
	assign dispatch_payload_o = ENABLE_DISTRIBUTED_PROGRAM_FRONTEND ? program_dispatch_payload : legacy_dispatch_payload;
	assign queue_fault_o = ENABLE_DISTRIBUTED_PROGRAM_FRONTEND ? '0 : legacy_queue_fault;
	assign cycle_o = ENABLE_DISTRIBUTED_PROGRAM_FRONTEND ? {32'd0, endpoint_schedule_cycle} : legacy_cycle_q;

	lpu_icu #(.QUEUE_DEPTH(ICU_QUEUE_DEPTH)) u_icu (
		.clk_i, .rst_ni, .run_i(run_i && !ENABLE_DISTRIBUTED_PROGRAM_FRONTEND),
		.enqueue_valid_i(schedule_valid_i && !ENABLE_DISTRIBUTED_PROGRAM_FRONTEND),
		.enqueue_ready_o(legacy_schedule_ready), .enqueue_queue_i(schedule_queue_i),
		.enqueue_is_instruction_i(schedule_is_instruction_i), .enqueue_command_i(schedule_command_i),
		.enqueue_payload_i(schedule_payload_i), .issue_valid_o(legacy_dispatch_valid),
		.issue_payload_o(legacy_dispatch_payload), .queue_fault_o(legacy_queue_fault)
	);

	// Adapt current architectural Queue numbers to FU-subsystem inputs.
	always_comb begin
		external_mem_issue_valid = '0;
		external_mem_issue_instruction = '0;
		external_mxm_load_issue_valid = '0;
		external_mxm_load_issue_instruction = '0;
		external_mxm_dequant_issue_valid = '0;
		external_mxm_dequant_issue_instruction = '0;
		external_mxm_compute_issue_valid = '0;
		external_mxm_compute_issue_instruction = '0;
		external_sxm_transpose_issue_valid = legacy_dispatch_valid[lpu_pkg::SXM_TRANSPOSE_QUEUE_BASE+:2];
		external_sxm_transpose_issue_instruction = '0;
		external_sxm_permute_issue_valid = legacy_dispatch_valid[lpu_pkg::SXM_PERMUTE_QUEUE_BASE+:2];
		external_sxm_permute_issue_instruction = '0;
		external_vxm_local_issue_valid = legacy_dispatch_valid[lpu_pkg::VXM_QUEUE_BASE+:lpu_pkg::VXM_LOCAL_QUEUE_COUNT];
		external_vxm_local_issue_instruction = '0;
		external_vxm_global_issue_valid = legacy_dispatch_valid[lpu_pkg::VXM_GLOBAL_QUEUE];
		external_vxm_global_issue_instruction = legacy_dispatch_payload[lpu_pkg::VXM_GLOBAL_QUEUE*416+:lpu_pkg::VXM_GLOBAL_CONFIG_WIDTH];
		// The old 104-Queue ICU namespace has one MEM Queue per Slice. Preserve
		// it as a compatibility source by targeting Bank 0 of each Slice.
		for(integer mem_queue = 0; mem_queue < LEGACY_MEM_QUEUE_COUNT; mem_queue = mem_queue + 1)begin
			integer bank_queue;
			bank_queue = (mem_queue / 52) * lpu_pkg::MEM_BANKS_PER_HEMISPHERE +
				(mem_queue % 52) * lpu_pkg::MEM_BANKS_PER_SLICE;
			external_mem_issue_valid[bank_queue] = legacy_dispatch_valid[mem_queue];
			external_mem_issue_instruction[
				bank_queue*lpu_pkg::MEM_INSTRUCTION_WIDTH+:lpu_pkg::MEM_INSTRUCTION_WIDTH] =
				legacy_dispatch_payload[mem_queue*416+:lpu_pkg::MEM_INSTRUCTION_WIDTH];
		end
		for(integer vxm_queue = 0; vxm_queue < lpu_pkg::VXM_LOCAL_QUEUE_COUNT; vxm_queue = vxm_queue + 1)begin
			external_vxm_local_issue_instruction[vxm_queue*lpu_pkg::VXM_LOCAL_MAX_INSTRUCTION_WIDTH+:lpu_pkg::VXM_LOCAL_MAX_INSTRUCTION_WIDTH] = legacy_dispatch_payload[(lpu_pkg::VXM_QUEUE_BASE+vxm_queue)*416+:lpu_pkg::VXM_LOCAL_MAX_INSTRUCTION_WIDTH];
		end
		for(integer hemisphere = 0; hemisphere < 2; hemisphere = hemisphere + 1)begin
			external_mxm_load_issue_valid[hemisphere*2] = legacy_dispatch_valid[lpu_pkg::MXM_LOAD_QUEUE_BASE+hemisphere];
			external_mxm_dequant_issue_valid[hemisphere*2] = legacy_dispatch_valid[lpu_pkg::MXM_DEQUANT_QUEUE_BASE+hemisphere];
			external_mxm_compute_issue_valid[hemisphere*2] = legacy_dispatch_valid[lpu_pkg::MXM_COMPUTE_QUEUE_BASE+hemisphere];
			external_mxm_load_issue_valid[hemisphere*2+1] = legacy_dispatch_valid[lpu_pkg::MXM_SECONDARY_LOAD_QUEUE_BASE+hemisphere];
			external_mxm_dequant_issue_valid[hemisphere*2+1] = legacy_dispatch_valid[lpu_pkg::MXM_SECONDARY_DEQUANT_QUEUE_BASE+hemisphere];
			external_mxm_compute_issue_valid[hemisphere*2+1] = legacy_dispatch_valid[lpu_pkg::MXM_SECONDARY_COMPUTE_QUEUE_BASE+hemisphere];
			external_mxm_load_issue_instruction[(hemisphere*2)*48+:48] = legacy_dispatch_payload[(lpu_pkg::MXM_LOAD_QUEUE_BASE+hemisphere)*416+:48];
			external_mxm_dequant_issue_instruction[(hemisphere*2)*16+:16] = legacy_dispatch_payload[(lpu_pkg::MXM_DEQUANT_QUEUE_BASE+hemisphere)*416+:16];
			external_mxm_compute_issue_instruction[(hemisphere*2)*48+:48] = legacy_dispatch_payload[(lpu_pkg::MXM_COMPUTE_QUEUE_BASE+hemisphere)*416+:48];
			external_mxm_load_issue_instruction[(hemisphere*2+1)*48+:48] = legacy_dispatch_payload[(lpu_pkg::MXM_SECONDARY_LOAD_QUEUE_BASE+hemisphere)*416+:48];
			external_mxm_dequant_issue_instruction[(hemisphere*2+1)*16+:16] = legacy_dispatch_payload[(lpu_pkg::MXM_SECONDARY_DEQUANT_QUEUE_BASE+hemisphere)*416+:16];
			external_mxm_compute_issue_instruction[(hemisphere*2+1)*48+:48] = legacy_dispatch_payload[(lpu_pkg::MXM_SECONDARY_COMPUTE_QUEUE_BASE+hemisphere)*416+:48];
			external_sxm_transpose_issue_instruction[hemisphere*416+:416] = legacy_dispatch_payload[(lpu_pkg::SXM_TRANSPOSE_QUEUE_BASE+hemisphere)*416+:416];
			external_sxm_permute_issue_instruction[hemisphere*416+:416] = legacy_dispatch_payload[(lpu_pkg::SXM_PERMUTE_QUEUE_BASE+hemisphere)*416+:416];
		end
	end

	// Monitor locally expanded MEM/MXM instructions in the existing dispatch namespace.
	always_comb begin
		program_dispatch_valid = '0;
		program_dispatch_payload = '0;
		// Existing dispatch observation also represents Bank 0 only; all 208
		// Bank issues remain visible on the dedicated local MEM signals.
		for(integer mem_queue = 0; mem_queue < LEGACY_MEM_QUEUE_COUNT; mem_queue = mem_queue + 1)begin
			integer bank_queue;
			bank_queue = (mem_queue / 52) * lpu_pkg::MEM_BANKS_PER_HEMISPHERE +
				(mem_queue % 52) * lpu_pkg::MEM_BANKS_PER_SLICE;
			program_dispatch_valid[mem_queue] = local_mem_issue_valid[bank_queue];
			program_dispatch_payload[
				mem_queue*416+:lpu_pkg::MEM_INSTRUCTION_WIDTH] = local_mem_issue_instruction[
				bank_queue*lpu_pkg::MEM_INSTRUCTION_WIDTH+:lpu_pkg::MEM_INSTRUCTION_WIDTH];
		end
		for(integer hemisphere = 0; hemisphere < 2; hemisphere = hemisphere + 1)begin
			program_dispatch_valid[lpu_pkg::MXM_LOAD_QUEUE_BASE+hemisphere] = local_mxm_load_issue_valid[hemisphere*2];
			program_dispatch_valid[lpu_pkg::MXM_DEQUANT_QUEUE_BASE+hemisphere] = local_mxm_dequant_issue_valid[hemisphere*2];
			program_dispatch_valid[lpu_pkg::MXM_COMPUTE_QUEUE_BASE+hemisphere] = local_mxm_compute_issue_valid[hemisphere*2];
			program_dispatch_valid[lpu_pkg::MXM_SECONDARY_LOAD_QUEUE_BASE+hemisphere] = local_mxm_load_issue_valid[hemisphere*2+1];
			program_dispatch_valid[lpu_pkg::MXM_SECONDARY_DEQUANT_QUEUE_BASE+hemisphere] = local_mxm_dequant_issue_valid[hemisphere*2+1];
			program_dispatch_valid[lpu_pkg::MXM_SECONDARY_COMPUTE_QUEUE_BASE+hemisphere] = local_mxm_compute_issue_valid[hemisphere*2+1];
			program_dispatch_payload[(lpu_pkg::MXM_LOAD_QUEUE_BASE+hemisphere)*416+:29] = local_mxm_load_issue_instruction[(hemisphere*2)*29+:29];
			program_dispatch_payload[(lpu_pkg::MXM_DEQUANT_QUEUE_BASE+hemisphere)*416+:16] = local_mxm_dequant_issue_instruction[(hemisphere*2)*16+:16];
			program_dispatch_payload[(lpu_pkg::MXM_COMPUTE_QUEUE_BASE+hemisphere)*416+:49] = local_mxm_compute_issue_instruction[(hemisphere*2)*49+:49];
			program_dispatch_payload[(lpu_pkg::MXM_SECONDARY_LOAD_QUEUE_BASE+hemisphere)*416+:29] = local_mxm_load_issue_instruction[(hemisphere*2+1)*29+:29];
			program_dispatch_payload[(lpu_pkg::MXM_SECONDARY_DEQUANT_QUEUE_BASE+hemisphere)*416+:16] = local_mxm_dequant_issue_instruction[(hemisphere*2+1)*16+:16];
			program_dispatch_payload[(lpu_pkg::MXM_SECONDARY_COMPUTE_QUEUE_BASE+hemisphere)*416+:49] = local_mxm_compute_issue_instruction[(hemisphere*2+1)*49+:49];
		end
	end

	generate
		if(ENABLE_DISTRIBUTED_PROGRAM_FRONTEND)begin : gen_program_control
			lpu_program_load_system #(
				.COMMAND_DEPTH(PROGRAM_COMMAND_DEPTH), .DMA_DATA_WIDTH(PROGRAM_DMA_DATA_WIDTH),
				.MEM_IMEM_DEPTH(PROGRAM_MEM_IMEM_DEPTH), .MXM_IMEM_DEPTH(PROGRAM_MXM_IMEM_DEPTH),
				.COMMAND_ADDRESS_WIDTH(PROGRAM_COMMAND_ADDRESS_WIDTH)
			) u_program_load_system (
				.clk_i, .rst_ni, .program_reset_i,
				.command_write_valid_i(program_command_write_valid_i), .command_write_ready_o(program_command_write_ready_o),
				.command_write_address_i(program_command_write_address_i), .command_write_opcode_i(program_command_write_opcode_i),
				.command_write_source_address_i(program_command_write_source_address_i), .command_write_byte_count_i(program_command_write_byte_count_i),
				.command_write_destination_i(program_command_write_destination_i),
				.command_write_format_i(program_command_write_format_i), .command_write_encoding_mode_i(program_command_write_encoding_mode_i),
				.command_write_imem_base_address_i(program_command_write_imem_base_address_i), .command_write_image_first_i(program_command_write_image_first_i),
				.command_write_image_last_i(program_command_write_image_last_i), .command_write_expected_word_count_i(program_command_write_expected_word_count_i),
				.command_write_jump_address_i(program_command_write_jump_address_i),
				.load_start_valid_i(program_load_start_valid_i), .load_start_ready_o(program_load_start_ready_o),
				.load_start_command_count_i(program_load_start_command_count_i), .dma_cmd_valid_o(program_dma_cmd_valid_o),
				.dma_cmd_ready_i(program_dma_cmd_ready_i), .dma_cmd_address_o(program_dma_cmd_address_o),
				.dma_cmd_length_o(program_dma_cmd_length_o), .dma_cmd_id_o(program_dma_cmd_id_o),
				.dma_rsp_valid_i(program_dma_rsp_valid_i), .dma_rsp_ready_o(program_dma_rsp_ready_o),
				.dma_rsp_data_i(program_dma_rsp_data_i), .dma_rsp_keep_i(program_dma_rsp_keep_i),
				.dma_rsp_last_i(program_dma_rsp_last_i), .dma_rsp_id_i(program_dma_rsp_id_i), .dma_rsp_error_i(program_dma_rsp_error_i),
				.program_start_request_i, .dependencies_ready_i(program_dependencies_ready_i), .program_start_ack_o,
				.program_load_complete_o, .program_ready_o, .program_running_o, .program_done_o,
				.program_fault_o, .program_fault_code_o, .schedule_cycle_o(program_schedule_cycle_o),
				.distribute_valid_o(program_distribute_valid), .distribute_ready_i(program_distribute_ready),
				.distribute_control_o(program_distribute_control), .distribute_data_o(program_distribute_data),
				.distribute_strb_o(program_distribute_strb), .distribute_scope_o(program_distribute_scope),
				.distribute_destination_o(program_distribute_destination),
				.distribute_imem_address_o(program_distribute_imem_address),
				.distribute_last_o(program_distribute_last), .distribute_idle_i(program_distribute_idle),
				.distribute_fault_i(program_distribute_fault),
				.distribute_fault_code_i(program_distribute_fault_code),
				.endpoint_program_start_o(endpoint_program_start), .endpoint_program_start_ready_i(endpoint_program_start_ready),
				.endpoint_started_i(endpoint_started), .endpoint_frontends_ready_i(endpoint_frontends_ready),
				.endpoint_frontends_idle_i(endpoint_frontends_idle), .endpoint_fault_i(endpoint_fault),
				.endpoint_fault_code_i(endpoint_fault_code), .endpoint_schedule_cycle_i(endpoint_schedule_cycle)
			);
		end
		else begin : gen_no_program_control
			assign program_command_write_ready_o = 1'b0;
			assign program_load_start_ready_o = 1'b0;
			assign program_dma_cmd_valid_o = 1'b0;
			assign program_dma_cmd_address_o = '0;
			assign program_dma_cmd_length_o = '0;
			assign program_dma_cmd_id_o = '0;
			assign program_dma_rsp_ready_o = 1'b0;
			assign program_start_ack_o = 1'b0;
			assign program_load_complete_o = 1'b0;
			assign program_ready_o = 1'b0;
			assign program_running_o = 1'b0;
			assign program_done_o = 1'b0;
			assign program_fault_o = 1'b0;
			assign program_fault_code_o = '0;
			assign program_schedule_cycle_o = '0;
			assign program_distribute_valid = 1'b0;
			assign program_distribute_control = '0;
			assign program_distribute_data = '0;
			assign program_distribute_strb = '0;
			assign program_distribute_scope = '0;
			assign program_distribute_destination = '0;
			assign program_distribute_imem_address = '0;
			assign program_distribute_last = 1'b0;
			assign endpoint_program_start = 1'b0;
		end
	endgenerate

	// The FU cluster is the only execution hierarchy in both Schedule and Program modes.
	lpu_fu_subsystem_cluster #(
		.MEM_IMEM_DEPTH(PROGRAM_MEM_IMEM_DEPTH), .MXM_IMEM_DEPTH(PROGRAM_MXM_IMEM_DEPTH),
		.ACTIVE_CONTEXTS(PROGRAM_ACTIVE_CONTEXTS), .MEM_DEPTH_ROWS(MEM_DEPTH_ROWS),
		.ACTIVE_MEM_COLUMNS(ACTIVE_MEM_COLUMNS), .MXM_ACCUMULATOR_BLOCK_COUNT(MXM_ACCUMULATOR_BLOCK_COUNT),
		.USE_SRAM_MACRO(USE_SRAM_MACRO), .USE_NATIVE_MEM(USE_NATIVE_MEM),
		.ENABLE_QCTL(ENABLE_DISTRIBUTED_PROGRAM_FRONTEND && ENABLE_QCTL),
		.QCTL_QUEUE_COUNT(QCTL_QUEUE_COUNT)
	) u_fu_subsystems (
		.clk_i, .rst_ni, .program_reset_i, .local_frontend_enable_i(ENABLE_DISTRIBUTED_PROGRAM_FRONTEND),
		.external_run_i(run_i), .program_distribute_valid_i(program_distribute_valid),
		.program_distribute_ready_o(program_distribute_ready),
		.program_distribute_control_i(program_distribute_control),
		.program_distribute_data_i(program_distribute_data),
		.program_distribute_strb_i(program_distribute_strb),
		.program_distribute_scope_i(program_distribute_scope),
		.program_distribute_destination_i(program_distribute_destination),
		.program_distribute_imem_address_i(program_distribute_imem_address),
		.program_distribute_last_i(program_distribute_last),
		.program_distribute_idle_o(program_distribute_idle),
		.program_distribute_fault_o(program_distribute_fault),
		.program_distribute_fault_code_o(program_distribute_fault_code),
		.program_start_i(endpoint_program_start), .program_start_ready_o(endpoint_program_start_ready),
		.started_o(endpoint_started), .all_frontends_ready_o(endpoint_frontends_ready),
		.all_frontends_idle_o(endpoint_frontends_idle), .schedule_cycle_o(endpoint_schedule_cycle),
		.frontend_fault_o(endpoint_fault), .frontend_fault_code_o(endpoint_fault_code),
		.qctl_load_mode_i, .qctl_partition_valid_i, .qctl_partition_ready_o, .qctl_partition_queue_i,
		.qctl_partition_base_i, .qctl_partition_count_i, .qctl_partition_generation_i,
		.qctl_load_valid_i, .qctl_load_ready_o, .qctl_load_address_i, .qctl_load_data_i,
		.qctl_event_valid_i, .qctl_event_ready_o, .qctl_event_tag_i, .qctl_sync_valid_i, .qctl_sync_ready_o,
		.qctl_notify_valid_o, .qctl_notify_ready_i, .qctl_mem_packet_valid_o, .qctl_mem_packet_ordinal_o,
		.qctl_mem_packet_retired_i, .qctl_queue_active_o, .qctl_wait_event_blocked_o, .qctl_wait_event_tag_o,
		.qctl_primed_o, .qctl_done_o, .qctl_fault_o, .qctl_fault_code_o,
		.external_mem_issue_valid_i(external_mem_issue_valid),
		.external_mem_issue_ready_o(external_mem_issue_ready),
		.external_mem_issue_instruction_i(external_mem_issue_instruction),
		.external_mxm_load_issue_valid_i(external_mxm_load_issue_valid), .external_mxm_load_issue_instruction_i(external_mxm_load_issue_instruction),
		.external_mxm_dequant_issue_valid_i(external_mxm_dequant_issue_valid), .external_mxm_dequant_issue_instruction_i(external_mxm_dequant_issue_instruction),
		.external_mxm_compute_issue_valid_i(external_mxm_compute_issue_valid), .external_mxm_compute_issue_instruction_i(external_mxm_compute_issue_instruction),
		.external_sxm_transpose_issue_valid_i(external_sxm_transpose_issue_valid), .external_sxm_transpose_issue_instruction_i(external_sxm_transpose_issue_instruction),
		.external_sxm_permute_issue_valid_i(external_sxm_permute_issue_valid), .external_sxm_permute_issue_instruction_i(external_sxm_permute_issue_instruction),
		.external_vxm_local_issue_valid_i(external_vxm_local_issue_valid), .external_vxm_local_issue_instruction_i(external_vxm_local_issue_instruction),
		.external_vxm_global_issue_valid_i(external_vxm_global_issue_valid), .external_vxm_global_issue_instruction_i(external_vxm_global_issue_instruction),
		.local_mem_issue_valid_o(local_mem_issue_valid), .local_mem_issue_instruction_o(local_mem_issue_instruction),
		.local_mem_issue_cycle_o(local_mem_issue_cycle), .local_mxm_load_issue_valid_o(local_mxm_load_issue_valid),
		.local_mxm_load_issue_instruction_o(local_mxm_load_issue_instruction), .local_mxm_load_issue_cycle_o(local_mxm_load_issue_cycle),
		.local_mxm_dequant_issue_valid_o(local_mxm_dequant_issue_valid), .local_mxm_dequant_issue_instruction_o(local_mxm_dequant_issue_instruction),
		.local_mxm_dequant_issue_cycle_o(local_mxm_dequant_issue_cycle), .local_mxm_compute_issue_valid_o(local_mxm_compute_issue_valid),
		.local_mxm_compute_issue_instruction_o(local_mxm_compute_issue_instruction), .local_mxm_compute_issue_cycle_o(local_mxm_compute_issue_cycle),
		.mem_east_edge_valid_i, .mem_east_edge_data_i,
		.mem_east_edge_valid_o, .mem_east_edge_data_o, .mem_west_edge_valid_i, .mem_west_edge_data_i,
		.mem_west_edge_valid_o, .mem_west_edge_data_o, .mem_fault_o, .mxm_fault_o, .sxm_fault_o,
		.vxm_fault_o, .stream_conflict_o
	);

	always_ff @(posedge clk_i or negedge rst_ni) begin
		if(!rst_ni)begin
			legacy_cycle_q <= '0;
		end
		else if(run_i && !ENABLE_DISTRIBUTED_PROGRAM_FRONTEND)begin
			legacy_cycle_q <= legacy_cycle_q + 1'b1;
		end
	end
endmodule
