module lpu_top #(
	parameter integer ICU_QUEUE_DEPTH = 16,
	parameter integer MEM_DEPTH_ROWS = lpu_pkg::SRAM_DEPTH_ROWS,
	parameter integer ACTIVE_MEM_COLUMNS = 52,
	parameter integer MXM_ACCUMULATOR_BLOCK_COUNT = lpu_pkg::MXM_ACCUMULATOR_BLOCK_COUNT,
	parameter bit USE_SRAM_MACRO = 1'b0,
	parameter bit ENABLE_MACRO_FRONTEND_CLUSTER = 1'b0,
	parameter bit ENABLE_DISTRIBUTED_PROGRAM_FRONTEND = 1'b0,
	parameter integer PROGRAM_COMMAND_DEPTH = 32,
	parameter integer PROGRAM_DMA_DATA_WIDTH = 256,
	parameter integer PROGRAM_MEM_IMEM_DEPTH = 131072,
	parameter integer PROGRAM_MXM_IMEM_DEPTH = 65536,
	parameter integer PROGRAM_ACTIVE_CONTEXTS = 4,
	parameter bit ENABLE_QCTL = 1'b0,
	parameter integer PROGRAM_COMMAND_ADDRESS_WIDTH = PROGRAM_COMMAND_DEPTH <= 1 ? 1 : $clog2(PROGRAM_COMMAND_DEPTH)
) (
	input logic clk_i,
	input logic rst_ni,

	// The C model preloads a complete static schedule before cycle zero.
	// Keep run_i low while filling queues, then hold it high while executing.
	input logic run_i,
	input logic schedule_valid_i,
	output logic schedule_ready_o,
	input logic [7:0] schedule_queue_i,
	input logic schedule_is_instruction_i,
	input logic [31:0] schedule_command_i,
	input logic [415:0] schedule_payload_i,

	// ProgramImage command RAM and external DDR/C2C response boundary.
	input logic program_reset_i,
	input logic program_command_write_valid_i,
	output logic program_command_write_ready_o,
	input logic [PROGRAM_COMMAND_ADDRESS_WIDTH-1:0] program_command_write_address_i,
	input logic [2:0] program_command_write_opcode_i,
	input logic [63:0] program_command_write_source_address_i,
	input logic [31:0] program_command_write_byte_count_i,
	input logic [3:0] program_command_write_target_kind_i,
	input logic [7:0] program_command_write_global_queue_id_i,
	input logic [1:0] program_command_write_format_i,
	input logic [1:0] program_command_write_encoding_mode_i,
	input logic [16:0] program_command_write_imem_base_address_i,
	input logic program_command_write_image_first_i,
	input logic program_command_write_image_last_i,
	input logic [15:0] program_command_write_expected_word_count_i,
	input logic [15:0] program_command_write_sequence_id_i,
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

	// Direct QCTL image/event boundary. It stays separate from Program Loader
	// until the new ProgramStorage metadata contract is finalized.
	input logic qctl_load_mode_i,
	input logic qctl_partition_valid_i,
	output logic qctl_partition_ready_o,
	input logic [7:0] qctl_partition_queue_i,
	input logic [8:0] qctl_partition_base_i,
	input logic [4:0] qctl_partition_count_i,
	input logic [63:0] qctl_partition_generation_i,
	input logic qctl_load_valid_i,
	output logic qctl_load_ready_o,
	input logic [8:0] qctl_load_address_i,
	input logic [95:0] qctl_load_data_i,
	input logic [219:0] qctl_event_valid_i,
	output logic [219:0] qctl_event_ready_o,
	input logic [220*32-1:0] qctl_event_tag_i,
	input logic [219:0] qctl_sync_valid_i,
	output logic [219:0] qctl_sync_ready_o,
	output logic [219:0] qctl_notify_valid_o,
	input logic [219:0] qctl_notify_ready_i,
	output logic [219:0] qctl_mem_packet_valid_o,
	output logic [220*32-1:0] qctl_mem_packet_ordinal_o,
	input logic [219:0] qctl_mem_packet_retired_i,
	output logic [219:0] qctl_queue_active_o,
	output logic [219:0] qctl_wait_event_blocked_o,
	output logic [220*32-1:0] qctl_wait_event_tag_o,
	output logic [219:0] qctl_primed_o,
	output logic [219:0] qctl_done_o,
	output logic qctl_fault_o,
	output logic [7:0] qctl_fault_code_o,

	// Optional FU-subsystem Frontend Cluster boundary. The default keeps the
	// existing ICU Schedule path unchanged. Native VXM outputs stay explicit
	// until the resident-config/Execute adapter is connected to lpu_vxm_slice.
	input  logic [207:0]      macro_mem_issue_valid_i,
	output logic [207:0]      macro_mem_issue_ready_o,
	input  logic [208*47-1:0] macro_mem_issue_instruction_i,
	input  logic [3:0]        macro_mxm_load_issue_valid_i,
	output logic [3:0]        macro_mxm_load_issue_ready_o,
	input  logic [4*29-1:0]   macro_mxm_load_issue_instruction_i,
	input  logic [3:0]        macro_mxm_dequant_issue_valid_i,
	output logic [3:0]        macro_mxm_dequant_issue_ready_o,
	input  logic [4*16-1:0]   macro_mxm_dequant_issue_instruction_i,
	input  logic [3:0]        macro_mxm_compute_issue_valid_i,
	output logic [3:0]        macro_mxm_compute_issue_ready_o,
	input  logic [4*49-1:0]   macro_mxm_compute_issue_instruction_i,
	input  logic [1:0]        macro_sxm_transpose_issue_valid_i,
	output logic [1:0]        macro_sxm_transpose_issue_ready_o,
	input  logic [2*416-1:0]  macro_sxm_transpose_issue_instruction_i,
	input  logic [1:0]        macro_sxm_permute_issue_valid_i,
	output logic [1:0]        macro_sxm_permute_issue_ready_o,
	input  logic [2*416-1:0]  macro_sxm_permute_issue_instruction_i,
	input  logic              macro_vxm_config_valid_i,
	output logic              macro_vxm_config_ready_o,
	input  logic [95:0]       macro_vxm_config_instruction_i,
	output logic              macro_vxm_config_valid_o,
	input  logic              macro_vxm_config_ready_i,
	output logic [95:0]       macro_vxm_config_instruction_o,
	input  logic              macro_vxm_execute_valid_i,
	output logic              macro_vxm_execute_ready_o,
	output logic              macro_vxm_execute_valid_o,
	input  logic              macro_vxm_execute_ready_i,
	input  logic [137:0]      macro_source_queue_fault_i,
	output logic              macro_integration_fault_o,
	output logic [3:0]        macro_integration_fault_code_o,
	output logic [31:0]       schedule_cycle_o,

	// Host SRAM access is intended for cycle-zero initialization and final
	// result collection. Global MEM columns 0..51 are East and 52..103 West.
	input logic host_mem_write_valid_i,
	input logic [6:0] host_mem_column_i,
	input logic host_mem_bank_i,
	input logic [1:0] host_mem_tile_i,
	input logic [15:0] host_mem_address_i,
	input logic [63:0] host_mem_write_data_i,
	output logic [63:0] host_mem_read_data_o,

	// VXM-side East injection / West extraction and SXM-side mirror ports.
	input logic [2*4*32-1:0] mem_east_edge_valid_i,
	input logic [2*4*32*64-1:0] mem_east_edge_data_i,
	output logic [2*4*32-1:0] mem_east_edge_valid_o,
	output logic [2*4*32*64-1:0] mem_east_edge_data_o,
	input logic [2*4*32-1:0] mem_west_edge_valid_i,
	input logic [2*4*32*64-1:0] mem_west_edge_data_i,
	output logic [2*4*32-1:0] mem_west_edge_valid_o,
	output logic [2*4*32*64-1:0] mem_west_edge_data_o,

	// Architectural dispatch monitor. Queue numbering is defined in lpu_pkg;
	// MEM queue pulses also feed the integrated hemisphere datapaths below.
	output logic [137:0] dispatch_valid_o,
	output logic [138*416-1:0] dispatch_payload_o,
	output logic [137:0] queue_fault_o,
	output logic [2*52*2*4-1:0] mem_fault_o,
	output logic [1:0] mxm_fault_o,
	output logic [1:0] sxm_fault_o,
	output logic vxm_fault_o,
	output logic [1:0] stream_conflict_o,
	output logic [63:0] cycle_o
);
	logic [2*52*2-1:0] mem_bank_issue_valid;
	logic [2*52*2*47-1:0] mem_bank_issue_instruction;
	logic [4*48-1:0] mxm_load_instruction;
	logic [4*16-1:0] mxm_dequant_instruction;
	logic [4*48-1:0] mxm_compute_instruction;
	logic [7:0] vxm_local_issue_valid;
	logic [8*lpu_pkg::VXM_LOCAL_MAX_INSTRUCTION_WIDTH-1:0] vxm_local_issue_instruction;
	logic vxm_global_issue_valid;
	logic [lpu_pkg::VXM_GLOBAL_CONFIG_WIDTH-1:0] vxm_global_issue_instruction;
	logic [2*64-1:0] host_mem_read_data;
	logic [63:0] program_host_mem_read_data;
	logic [2*4*32-1:0] mem_to_vxm_west_valid;
	logic [2*4*32*64-1:0] mem_to_vxm_west_data;
	logic [2*4*32-1:0] vxm_to_mem_east_valid;
	logic [2*4*32*64-1:0] vxm_to_mem_east_data;
	logic vxm_stream_conflict;
	logic legacy_schedule_ready;
	logic [137:0] legacy_dispatch_valid;
	logic [138*416-1:0] legacy_dispatch_payload;
	logic [137:0] legacy_queue_fault;
	logic [137:0] macro_dispatch_valid;
	logic [138*416-1:0] macro_dispatch_payload;
	logic [137:0] macro_queue_fault;
	logic [137:0] program_dispatch_valid;
	logic [138*416-1:0] program_dispatch_payload;
	logic [137:0] program_queue_fault;
	logic unused_schedule_wrap;
	logic macro_adapter_enable;
	logic execution_run;
	logic [31:0] adapter_schedule_cycle;
	logic [63:0] adapter_cycle;

	logic [207:0] selected_mem_issue_valid;
	logic [208*47-1:0] selected_mem_issue_instruction;
	logic [3:0] selected_mxm_load_issue_valid;
	logic [4*29-1:0] selected_mxm_load_issue_instruction;
	logic [3:0] selected_mxm_dequant_issue_valid;
	logic [4*16-1:0] selected_mxm_dequant_issue_instruction;
	logic [3:0] selected_mxm_compute_issue_valid;
	logic [4*49-1:0] selected_mxm_compute_issue_instruction;
	logic [1:0] selected_sxm_transpose_issue_valid;
	logic [2*416-1:0] selected_sxm_transpose_issue_instruction;
	logic [1:0] selected_sxm_permute_issue_valid;
	logic [2*416-1:0] selected_sxm_permute_issue_instruction;
	logic selected_vxm_config_valid;
	logic [95:0] selected_vxm_config_instruction;
	logic selected_vxm_execute_valid;
	logic [137:0] selected_source_queue_fault;

	logic [207:0] adapter_mem_issue_ready;
	logic [3:0] adapter_mxm_load_issue_ready;
	logic [3:0] adapter_mxm_dequant_issue_ready;
	logic [3:0] adapter_mxm_compute_issue_ready;
	logic [1:0] adapter_sxm_transpose_issue_ready;
	logic [1:0] adapter_sxm_permute_issue_ready;
	logic adapter_vxm_config_ready;
	logic adapter_vxm_execute_ready;

	logic [207:0] program_mem_issue_valid;
	logic [208*47-1:0] program_mem_issue_instruction;
	logic [208*32-1:0] program_mem_issue_cycle;
	logic [3:0] program_mxm_load_issue_valid;
	logic [4*29-1:0] program_mxm_load_issue_instruction;
	logic [4*32-1:0] program_mxm_load_issue_cycle;
	logic [3:0] program_mxm_dequant_issue_valid;
	logic [4*16-1:0] program_mxm_dequant_issue_instruction;
	logic [4*32-1:0] program_mxm_dequant_issue_cycle;
	logic [3:0] program_mxm_compute_issue_valid;
	logic [4*49-1:0] program_mxm_compute_issue_instruction;
	logic [4*32-1:0] program_mxm_compute_issue_cycle;
	logic [1:0] program_endpoint_load_valid;
	logic [1:0] program_endpoint_load_ready;
	logic [5:0] program_endpoint_load_command;
	logic [255:0] program_endpoint_load_data;
	logic [31:0] program_endpoint_load_strb;
	logic [7:0] program_endpoint_load_target_kind;
	logic [15:0] program_endpoint_load_queue_id;
	logic [33:0] program_endpoint_load_imem_address;
	logic [1:0] program_endpoint_load_last;
	logic [31:0] program_endpoint_load_sequence_id;
	logic [1:0] program_endpoint_commit_valid;
	logic [1:0] program_endpoint_commit_ready;
	logic [31:0] program_endpoint_commit_sequence_id;
	logic [1:0] program_endpoint_commit_error;
	logic program_endpoint_start;
	logic program_endpoint_start_ready;
	logic program_endpoint_started;
	logic program_endpoint_frontends_ready;
	logic program_endpoint_frontends_idle;
	logic program_endpoint_fault;
	logic [5:0] program_endpoint_fault_code;
	logic [31:0] program_endpoint_schedule_cycle;
	logic program_running_internal;
	logic program_fault_internal;
	logic [5:0] program_fault_code_internal;

	initial begin
		if(ENABLE_MACRO_FRONTEND_CLUSTER && ENABLE_DISTRIBUTED_PROGRAM_FRONTEND)begin
			$error("External Macro Frontend and integrated Program Frontend modes are mutually exclusive");
		end
	end

	generate
		if(ENABLE_DISTRIBUTED_PROGRAM_FRONTEND)begin : gen_program_control
			lpu_program_control_system #(
				.COMMAND_DEPTH(PROGRAM_COMMAND_DEPTH),
				.DMA_DATA_WIDTH(PROGRAM_DMA_DATA_WIDTH),
				.MEM_IMEM_DEPTH(PROGRAM_MEM_IMEM_DEPTH),
				.MXM_IMEM_DEPTH(PROGRAM_MXM_IMEM_DEPTH),
				.ACTIVE_CONTEXTS(PROGRAM_ACTIVE_CONTEXTS),
				.COMMAND_ADDRESS_WIDTH(PROGRAM_COMMAND_ADDRESS_WIDTH)
			) u_program_control (
				.clk_i,
				.rst_ni,
				.program_reset_i,
				.command_write_valid_i(program_command_write_valid_i),
				.command_write_ready_o(program_command_write_ready_o),
				.command_write_address_i(program_command_write_address_i),
				.command_write_opcode_i(program_command_write_opcode_i),
				.command_write_source_address_i(program_command_write_source_address_i),
				.command_write_byte_count_i(program_command_write_byte_count_i),
				.command_write_target_kind_i(program_command_write_target_kind_i),
				.command_write_global_queue_id_i(program_command_write_global_queue_id_i),
				.command_write_format_i(program_command_write_format_i),
				.command_write_encoding_mode_i(program_command_write_encoding_mode_i),
				.command_write_imem_base_address_i(program_command_write_imem_base_address_i),
				.command_write_image_first_i(program_command_write_image_first_i),
				.command_write_image_last_i(program_command_write_image_last_i),
				.command_write_expected_word_count_i(program_command_write_expected_word_count_i),
				.command_write_sequence_id_i(program_command_write_sequence_id_i),
				.command_write_jump_address_i(program_command_write_jump_address_i),
				.load_start_valid_i(program_load_start_valid_i),
				.load_start_ready_o(program_load_start_ready_o),
				.load_start_command_count_i(program_load_start_command_count_i),
				.dma_cmd_valid_o(program_dma_cmd_valid_o),
				.dma_cmd_ready_i(program_dma_cmd_ready_i),
				.dma_cmd_address_o(program_dma_cmd_address_o),
				.dma_cmd_length_o(program_dma_cmd_length_o),
				.dma_cmd_id_o(program_dma_cmd_id_o),
				.dma_rsp_valid_i(program_dma_rsp_valid_i),
				.dma_rsp_ready_o(program_dma_rsp_ready_o),
				.dma_rsp_data_i(program_dma_rsp_data_i),
				.dma_rsp_keep_i(program_dma_rsp_keep_i),
				.dma_rsp_last_i(program_dma_rsp_last_i),
				.dma_rsp_id_i(program_dma_rsp_id_i),
				.dma_rsp_error_i(program_dma_rsp_error_i),
				.program_start_request_i,
				.dependencies_ready_i(program_dependencies_ready_i),
				.program_start_ack_o,
				.program_load_complete_o,
				.program_ready_o,
				.program_running_o(program_running_internal),
				.program_done_o,
				.program_fault_o(program_fault_internal),
				.program_fault_code_o(program_fault_code_internal),
				.schedule_cycle_o(program_schedule_cycle_o),
				.endpoint_load_valid_o(program_endpoint_load_valid),
				.endpoint_load_ready_i(program_endpoint_load_ready),
				.endpoint_load_command_o(program_endpoint_load_command),
				.endpoint_load_data_o(program_endpoint_load_data),
				.endpoint_load_strb_o(program_endpoint_load_strb),
				.endpoint_load_target_kind_o(program_endpoint_load_target_kind),
				.endpoint_load_queue_id_o(program_endpoint_load_queue_id),
				.endpoint_load_imem_address_o(program_endpoint_load_imem_address),
				.endpoint_load_last_o(program_endpoint_load_last),
				.endpoint_load_sequence_id_o(program_endpoint_load_sequence_id),
				.endpoint_commit_valid_i(program_endpoint_commit_valid),
				.endpoint_commit_ready_o(program_endpoint_commit_ready),
				.endpoint_commit_sequence_id_i(program_endpoint_commit_sequence_id),
				.endpoint_commit_error_i(program_endpoint_commit_error),
				.endpoint_program_start_o(program_endpoint_start),
				.endpoint_program_start_ready_i(program_endpoint_start_ready),
				.endpoint_started_i(program_endpoint_started),
				.endpoint_frontends_ready_i(program_endpoint_frontends_ready),
				.endpoint_frontends_idle_i(program_endpoint_frontends_idle),
				.endpoint_fault_i(program_endpoint_fault),
				.endpoint_fault_code_i(program_endpoint_fault_code),
				.endpoint_schedule_cycle_i(program_endpoint_schedule_cycle)
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
			assign program_done_o = 1'b0;
			assign program_schedule_cycle_o = '0;
			assign program_endpoint_load_valid = '0;
			assign program_endpoint_load_command = '0;
			assign program_endpoint_load_data = '0;
			assign program_endpoint_load_strb = '0;
			assign program_endpoint_load_target_kind = '0;
			assign program_endpoint_load_queue_id = '0;
			assign program_endpoint_load_imem_address = '0;
			assign program_endpoint_load_last = '0;
			assign program_endpoint_load_sequence_id = '0;
			assign program_endpoint_commit_ready = '0;
			assign program_endpoint_start = 1'b0;
			assign program_mem_issue_valid = '0;
			assign program_mem_issue_instruction = '0;
			assign program_mem_issue_cycle = '0;
			assign program_mxm_load_issue_valid = '0;
			assign program_mxm_load_issue_instruction = '0;
			assign program_mxm_load_issue_cycle = '0;
			assign program_mxm_dequant_issue_valid = '0;
			assign program_mxm_dequant_issue_instruction = '0;
			assign program_mxm_dequant_issue_cycle = '0;
			assign program_mxm_compute_issue_valid = '0;
			assign program_mxm_compute_issue_instruction = '0;
			assign program_mxm_compute_issue_cycle = '0;
			assign program_running_internal = 1'b0;
			assign program_fault_internal = 1'b0;
			assign program_fault_code_internal = '0;
		end
	endgenerate

	assign macro_adapter_enable = ENABLE_MACRO_FRONTEND_CLUSTER;
	assign execution_run = ENABLE_DISTRIBUTED_PROGRAM_FRONTEND ? program_running_internal : run_i;

	assign selected_mem_issue_valid = macro_mem_issue_valid_i;
	assign selected_mem_issue_instruction = macro_mem_issue_instruction_i;
	assign selected_mxm_load_issue_valid = macro_mxm_load_issue_valid_i;
	assign selected_mxm_load_issue_instruction = macro_mxm_load_issue_instruction_i;
	assign selected_mxm_dequant_issue_valid = macro_mxm_dequant_issue_valid_i;
	assign selected_mxm_dequant_issue_instruction = macro_mxm_dequant_issue_instruction_i;
	assign selected_mxm_compute_issue_valid = macro_mxm_compute_issue_valid_i;
	assign selected_mxm_compute_issue_instruction = macro_mxm_compute_issue_instruction_i;
	assign selected_sxm_transpose_issue_valid = macro_sxm_transpose_issue_valid_i;
	assign selected_sxm_transpose_issue_instruction = macro_sxm_transpose_issue_instruction_i;
	assign selected_sxm_permute_issue_valid = macro_sxm_permute_issue_valid_i;
	assign selected_sxm_permute_issue_instruction = macro_sxm_permute_issue_instruction_i;
	assign selected_vxm_config_valid = macro_vxm_config_valid_i;
	assign selected_vxm_config_instruction = macro_vxm_config_instruction_i;
	assign selected_vxm_execute_valid = macro_vxm_execute_valid_i;
	assign selected_source_queue_fault = macro_source_queue_fault_i;
	assign macro_mem_issue_ready_o = ENABLE_MACRO_FRONTEND_CLUSTER ? adapter_mem_issue_ready : '0;
	assign macro_mxm_load_issue_ready_o = ENABLE_MACRO_FRONTEND_CLUSTER ? adapter_mxm_load_issue_ready : '0;
	assign macro_mxm_dequant_issue_ready_o = ENABLE_MACRO_FRONTEND_CLUSTER ? adapter_mxm_dequant_issue_ready : '0;
	assign macro_mxm_compute_issue_ready_o = ENABLE_MACRO_FRONTEND_CLUSTER ? adapter_mxm_compute_issue_ready : '0;
	assign macro_sxm_transpose_issue_ready_o = ENABLE_MACRO_FRONTEND_CLUSTER ? adapter_sxm_transpose_issue_ready : '0;
	assign macro_sxm_permute_issue_ready_o = ENABLE_MACRO_FRONTEND_CLUSTER ? adapter_sxm_permute_issue_ready : '0;
	assign macro_vxm_config_ready_o = ENABLE_MACRO_FRONTEND_CLUSTER ? adapter_vxm_config_ready : 1'b0;
	assign macro_vxm_execute_ready_o = ENABLE_MACRO_FRONTEND_CLUSTER ? adapter_vxm_execute_ready : 1'b0;

	assign schedule_cycle_o = ENABLE_DISTRIBUTED_PROGRAM_FRONTEND ? program_schedule_cycle_o : adapter_schedule_cycle;
	assign cycle_o = ENABLE_DISTRIBUTED_PROGRAM_FRONTEND ? {32'd0, program_schedule_cycle_o} : adapter_cycle;
	assign program_running_o = program_running_internal && !program_fault_o;
	assign program_fault_o = program_fault_internal ||
		(ENABLE_DISTRIBUTED_PROGRAM_FRONTEND && (macro_integration_fault_o ||
		 (|mem_fault_o) || (|mxm_fault_o) || (|sxm_fault_o) || vxm_fault_o || (|stream_conflict_o)));
	assign program_fault_code_o = program_fault_internal ? program_fault_code_internal :
		(program_fault_o ? 6'h3f : 6'd0);

	lpu_icu #(
		.QUEUE_DEPTH(ICU_QUEUE_DEPTH)
	) u_icu (
		.clk_i,
		.rst_ni,
		.run_i,
		.enqueue_valid_i(schedule_valid_i && !macro_adapter_enable && !ENABLE_DISTRIBUTED_PROGRAM_FRONTEND),
		.enqueue_ready_o(legacy_schedule_ready),
		.enqueue_queue_i(schedule_queue_i),
		.enqueue_is_instruction_i(schedule_is_instruction_i),
		.enqueue_command_i(schedule_command_i),
		.enqueue_payload_i(schedule_payload_i),
		.issue_valid_o(legacy_dispatch_valid),
		.issue_payload_o(legacy_dispatch_payload),
		.queue_fault_o(legacy_queue_fault)
	);

	// The cluster owns the one shared logical Schedule timebase. It does not
	// reinterpret FU-local instructions; unsupported width adaptation faults.
	lpu_frontend_cluster u_frontend_cluster (
		.clk_i,
		.rst_ni,
		.run_i(execution_run),
		.enable_i(macro_adapter_enable),
		.mem_issue_valid_i(selected_mem_issue_valid),
		.mem_issue_ready_o(adapter_mem_issue_ready),
		.mem_issue_instruction_i(selected_mem_issue_instruction),
		.mxm_load_issue_valid_i(selected_mxm_load_issue_valid),
		.mxm_load_issue_ready_o(adapter_mxm_load_issue_ready),
		.mxm_load_issue_instruction_i(selected_mxm_load_issue_instruction),
		.mxm_dequant_issue_valid_i(selected_mxm_dequant_issue_valid),
		.mxm_dequant_issue_ready_o(adapter_mxm_dequant_issue_ready),
		.mxm_dequant_issue_instruction_i(selected_mxm_dequant_issue_instruction),
		.mxm_compute_issue_valid_i(selected_mxm_compute_issue_valid),
		.mxm_compute_issue_ready_o(adapter_mxm_compute_issue_ready),
		.mxm_compute_issue_instruction_i(selected_mxm_compute_issue_instruction),
		.sxm_transpose_issue_valid_i(selected_sxm_transpose_issue_valid),
		.sxm_transpose_issue_ready_o(adapter_sxm_transpose_issue_ready),
		.sxm_transpose_issue_instruction_i(selected_sxm_transpose_issue_instruction),
		.sxm_permute_issue_valid_i(selected_sxm_permute_issue_valid),
		.sxm_permute_issue_ready_o(adapter_sxm_permute_issue_ready),
		.sxm_permute_issue_instruction_i(selected_sxm_permute_issue_instruction),
		.vxm_config_valid_i(selected_vxm_config_valid),
		.vxm_config_ready_o(adapter_vxm_config_ready),
		.vxm_config_instruction_i(selected_vxm_config_instruction),
		.vxm_config_valid_o(macro_vxm_config_valid_o),
		.vxm_config_ready_i(macro_vxm_config_ready_i),
		.vxm_config_instruction_o(macro_vxm_config_instruction_o),
		.vxm_execute_valid_i(selected_vxm_execute_valid),
		.vxm_execute_ready_o(adapter_vxm_execute_ready),
		.vxm_execute_valid_o(macro_vxm_execute_valid_o),
		.vxm_execute_ready_i(macro_vxm_execute_ready_i),
		.source_queue_fault_i(selected_source_queue_fault),
		.dispatch_valid_o(macro_dispatch_valid),
		.dispatch_payload_o(macro_dispatch_payload),
		.queue_fault_o(macro_queue_fault),
		.schedule_cycle_o(adapter_schedule_cycle),
		.cycle_o(adapter_cycle),
		.schedule_wrap_o(unused_schedule_wrap),
		.integration_fault_o(macro_integration_fault_o),
		.integration_fault_code_o(macro_integration_fault_code_o)
	);

	assign schedule_ready_o = (macro_adapter_enable || ENABLE_DISTRIBUTED_PROGRAM_FRONTEND) ?
		1'b0 : legacy_schedule_ready;
	assign dispatch_valid_o = ENABLE_DISTRIBUTED_PROGRAM_FRONTEND ? program_dispatch_valid :
		(macro_adapter_enable ? macro_dispatch_valid : legacy_dispatch_valid);
	assign dispatch_payload_o = ENABLE_DISTRIBUTED_PROGRAM_FRONTEND ? program_dispatch_payload :
		(macro_adapter_enable ? macro_dispatch_payload : legacy_dispatch_payload);
	assign queue_fault_o = ENABLE_DISTRIBUTED_PROGRAM_FRONTEND ? program_queue_fault :
		(macro_adapter_enable ? macro_queue_fault : legacy_queue_fault);

	// Program mode exposes FU-local Queue launches through the existing architectural monitor map.
	always_comb begin
		program_dispatch_valid = '0;
		program_dispatch_payload = '0;
		program_queue_fault = '0;
		for(integer hemisphere = 0; hemisphere < 2; hemisphere = hemisphere + 1)begin
			for(integer local_mxm = 0; local_mxm < 2; local_mxm = local_mxm + 1)begin
				integer mxm_index;
				integer load_queue;
				integer dequant_queue;
				integer compute_queue;
				mxm_index = hemisphere*2 + local_mxm;
				load_queue = local_mxm == 0 ? 104+hemisphere : 132+hemisphere;
				dequant_queue = local_mxm == 0 ? 106+hemisphere : 134+hemisphere;
				compute_queue = local_mxm == 0 ? 108+hemisphere : 136+hemisphere;
				program_dispatch_valid[load_queue] = program_mxm_load_issue_valid[mxm_index];
				program_dispatch_payload[load_queue*416+:29] =
					program_mxm_load_issue_instruction[mxm_index*29+:29];
				program_dispatch_valid[dequant_queue] = program_mxm_dequant_issue_valid[mxm_index];
				program_dispatch_payload[dequant_queue*416+:16] =
					program_mxm_dequant_issue_instruction[mxm_index*16+:16];
				program_dispatch_valid[compute_queue] = program_mxm_compute_issue_valid[mxm_index];
				program_dispatch_payload[compute_queue*416+:49] =
					program_mxm_compute_issue_instruction[mxm_index*49+:49];
			end
		end
	end

	always_comb begin
		mem_bank_issue_valid = '0;
		mem_bank_issue_instruction = '0;
		mxm_load_instruction = '0;
		mxm_dequant_instruction = '0;
		mxm_compute_instruction = '0;
		vxm_local_issue_valid = dispatch_valid_o[lpu_pkg::VXM_QUEUE_BASE+:lpu_pkg::VXM_LOCAL_QUEUE_COUNT];
		vxm_local_issue_instruction = '0;
		vxm_global_issue_valid = dispatch_valid_o[lpu_pkg::VXM_GLOBAL_QUEUE];
		vxm_global_issue_instruction = dispatch_payload_o[lpu_pkg::VXM_GLOBAL_QUEUE*416+:lpu_pkg::VXM_GLOBAL_CONFIG_WIDTH];
		host_mem_read_data_o = ENABLE_DISTRIBUTED_PROGRAM_FRONTEND ?
			program_host_mem_read_data : '0;
		for(integer slice = 0; slice < 104; slice++)begin
			if(macro_adapter_enable)begin
				mem_bank_issue_valid[slice*2+:2] = selected_mem_issue_valid[slice*2+:2];
				mem_bank_issue_instruction[slice*2*47+:2*47] = selected_mem_issue_instruction[slice*2*47+:2*47];
			end
			else begin
				mem_bank_issue_valid[slice*2] = dispatch_valid_o[slice];
				mem_bank_issue_instruction[(slice*2)*47+:47] = dispatch_payload_o[slice*416+:47];
			end
		end
		for (integer queue = 0; queue < lpu_pkg::VXM_LOCAL_QUEUE_COUNT; queue++)
			vxm_local_issue_instruction[queue*lpu_pkg::VXM_LOCAL_MAX_INSTRUCTION_WIDTH+:lpu_pkg::VXM_LOCAL_MAX_INSTRUCTION_WIDTH] = dispatch_payload_o[(lpu_pkg::VXM_QUEUE_BASE+queue)*416+:lpu_pkg::VXM_LOCAL_MAX_INSTRUCTION_WIDTH];
		for (integer hemisphere = 0; hemisphere < 2; hemisphere++) begin
			mxm_load_instruction[(hemisphere*2)*48+:48] = dispatch_payload_o[(104+hemisphere)*416+:48];
			mxm_dequant_instruction[(hemisphere*2)*16+:16] = dispatch_payload_o[(106+hemisphere)*416+:16];
			mxm_compute_instruction[(hemisphere*2)*48+:48] = dispatch_payload_o[(108+hemisphere)*416+:48];
			mxm_load_instruction[(hemisphere*2+1)*48+:48] = dispatch_payload_o[(132+hemisphere)*416+:48];
			mxm_dequant_instruction[(hemisphere*2+1)*16+:16] = dispatch_payload_o[(134+hemisphere)*416+:16];
			mxm_compute_instruction[(hemisphere*2+1)*48+:48] = dispatch_payload_o[(136+hemisphere)*416+:48];
		end

		if(!ENABLE_DISTRIBUTED_PROGRAM_FRONTEND && (host_mem_column_i < 52))begin
			host_mem_read_data_o = host_mem_read_data[0+:64];
		end
		else if(!ENABLE_DISTRIBUTED_PROGRAM_FRONTEND && (host_mem_column_i < 104))begin
			host_mem_read_data_o = host_mem_read_data[64+:64];
		end
	end

	generate
		if(!ENABLE_DISTRIBUTED_PROGRAM_FRONTEND)begin : gen_external_fu_subsystems
		for (genvar hemisphere_gen = 0; hemisphere_gen < 2; hemisphere_gen++) begin : gen_mem
			localparam integer HEMISPHERE_INDEX = hemisphere_gen;
			logic [4*32-1:0] east_edge_valid;
			logic [4*32*64-1:0] east_edge_data;
			logic [4*32-1:0] west_edge_valid;
			logic [4*32*64-1:0] west_edge_data;
			logic [4*32-1:0] sxm_east_valid;
			logic [4*32*64-1:0] sxm_east_data;
			logic [4*32-1:0] sxm_west_valid;
			logic [4*32*64-1:0] sxm_west_data;
			logic [4*32-1:0] mxm_west_valid;
			logic [4*32*64-1:0] mxm_west_data;
			logic [4*32-1:0] mxm_east_valid;
			logic [4*32*64-1:0] mxm_east_data;
			logic [2*4*32-1:0] local_mxm_west_valid;
			logic [2*4*32*64-1:0] local_mxm_west_data;
			logic [2*4*32-1:0] local_mxm_east_valid;
			logic [2*4*32*64-1:0] local_mxm_east_data;
			logic [1:0] local_mxm_fault;
			logic [1:0] local_mxm_conflict;
			logic [63:0] host_read;
			logic [5:0] host_local_column;
			logic [52*2*4-1:0] mem_fault;
			logic mem_stream_conflict;
			logic sxm_stream_conflict;
			logic sxm_fault;
			logic mxm_stream_conflict;
			logic mxm_fault;

			if(HEMISPHERE_INDEX == 0)begin
				assign host_local_column = host_mem_column_i[5:0];
			end
			else begin
				assign host_local_column = host_mem_column_i[5:0] - 6'd52;
			end

			lpu_mem_hemisphere #(
				.DEPTH_ROWS(MEM_DEPTH_ROWS),
				.ACTIVE_COLUMNS(ACTIVE_MEM_COLUMNS),
				.USE_SRAM_MACRO(USE_SRAM_MACRO)
			) u_mem (
				.clk_i,
				.rst_ni,
				.run_i(execution_run),
				.issue_valid_i(mem_bank_issue_valid[HEMISPHERE_INDEX*52*2+:52*2]),
				.issue_instruction_i(mem_bank_issue_instruction[HEMISPHERE_INDEX*52*2*47+:52*2*47]),
				.east_edge_valid_i(vxm_to_mem_east_valid[HEMISPHERE_INDEX*4*32+:4*32]),
				.east_edge_data_i(vxm_to_mem_east_data[HEMISPHERE_INDEX*4*32*64+:4*32*64]),
				.east_edge_valid_o(east_edge_valid),
				.east_edge_data_o(east_edge_data),
				.west_edge_valid_i(sxm_west_valid),
				.west_edge_data_i(sxm_west_data),
				.west_edge_valid_o(west_edge_valid),
				.west_edge_data_o(west_edge_data),
				.host_write_valid_i(host_mem_write_valid_i && (host_mem_column_i >= HEMISPHERE_INDEX * 52) && (host_mem_column_i < (HEMISPHERE_INDEX + 1) * 52)),
				.host_column_i(host_local_column),
				.host_bank_i(host_mem_bank_i),
				.host_tile_i(host_mem_tile_i),
				.host_address_i(host_mem_address_i),
				.host_write_data_i(host_mem_write_data_i),
				.host_read_data_o(host_read),
				.mem_fault_o(mem_fault),
				.conflict_o(mem_stream_conflict)
			);

			lpu_sxm_slice u_sxm (
				.clk_i,
				.rst_ni,
				.run_i(execution_run),
				.transpose_issue_valid_i(dispatch_valid_o[128+HEMISPHERE_INDEX]),
				.transpose_issue_instruction_i(dispatch_payload_o[(128+HEMISPHERE_INDEX)*416+:416]),
				.permute_issue_valid_i(dispatch_valid_o[130+HEMISPHERE_INDEX]),
				.permute_issue_instruction_i(dispatch_payload_o[(130+HEMISPHERE_INDEX)*416+:416]),
				.east_inner_valid_i(east_edge_valid),
				.east_inner_data_i(east_edge_data),
				.east_outer_valid_o(sxm_east_valid),
				.east_outer_data_o(sxm_east_data),
				.west_outer_valid_i(mxm_west_valid),
				.west_outer_data_i(mxm_west_data),
				.west_inner_valid_o(sxm_west_valid),
				.west_inner_data_o(sxm_west_data),
				.fault_o(sxm_fault),
				.conflict_o(sxm_stream_conflict)
			);

			for (genvar local_mxm = 0; local_mxm < 2; local_mxm++) begin : gen_mxm
				localparam integer MXM_INDEX = HEMISPHERE_INDEX * 2 + local_mxm;
				localparam integer LOAD_QUEUE = local_mxm == 0 ? 104 + HEMISPHERE_INDEX : 132 + HEMISPHERE_INDEX;
				localparam integer DEQUANT_QUEUE = local_mxm == 0 ? 106 + HEMISPHERE_INDEX : 134 + HEMISPHERE_INDEX;
				localparam integer COMPUTE_QUEUE = local_mxm == 0 ? 108 + HEMISPHERE_INDEX : 136 + HEMISPHERE_INDEX;

				lpu_mxm_slice #(
					.LOCAL_MXM_INDEX(local_mxm),
					.ACCUMULATOR_BLOCK_COUNT(MXM_ACCUMULATOR_BLOCK_COUNT)
				) u_mxm (
					.clk_i,
					.rst_ni,
					.run_i(execution_run),
					.load_issue_valid_i(dispatch_valid_o[LOAD_QUEUE]),
					.load_issue_instruction_i(mxm_load_instruction[MXM_INDEX*48+:48]),
					.dequant_issue_valid_i(dispatch_valid_o[DEQUANT_QUEUE]),
					.dequant_issue_instruction_i(mxm_dequant_instruction[MXM_INDEX*16+:16]),
					.compute_issue_valid_i(dispatch_valid_o[COMPUTE_QUEUE]),
					.compute_issue_instruction_i(mxm_compute_instruction[MXM_INDEX*48+:48]),
					.east_from_sxm_valid_i(sxm_east_valid),
					.east_from_sxm_data_i(sxm_east_data),
					.external_west_valid_i(local_mxm == 0 ? mem_west_edge_valid_i[HEMISPHERE_INDEX*4*32+:4*32] : '0),
					.external_west_data_i(mem_west_edge_data_i[HEMISPHERE_INDEX*4*32*64+:4*32*64]),
					.east_external_valid_o(local_mxm_east_valid[local_mxm*4*32+:4*32]),
					.east_external_data_o(local_mxm_east_data[local_mxm*4*32*64+:4*32*64]),
					.west_to_sxm_valid_o(local_mxm_west_valid[local_mxm*4*32+:4*32]),
					.west_to_sxm_data_o(local_mxm_west_data[local_mxm*4*32*64+:4*32*64]),
					.fault_o(local_mxm_fault[local_mxm]),
					.conflict_o(local_mxm_conflict[local_mxm])
				);
			end

			always_comb begin
				mxm_east_valid = local_mxm_east_valid[0+:4*32] & local_mxm_east_valid[4*32+:4*32];
				mxm_east_data = local_mxm_east_data[0+:4*32*64];
				mxm_west_valid = local_mxm_west_valid[0+:4*32];
				mxm_west_data = local_mxm_west_data[0+:4*32*64];
				mxm_stream_conflict = |local_mxm_conflict;
				for (integer stream_cell = 0; stream_cell < 4 * 32; stream_cell++) begin
					if(local_mxm_west_valid[4*32+stream_cell])begin
						if(mxm_west_valid[stream_cell])begin
							mxm_stream_conflict = 1'b1;
						end
						else begin
							mxm_west_valid[stream_cell] = 1'b1;
							mxm_west_data[stream_cell*64+:64] = local_mxm_west_data[(4*32+stream_cell)*64+:64];
						end
					end
				end
				mxm_fault = |local_mxm_fault;
			end

			assign mem_east_edge_valid_o[HEMISPHERE_INDEX*4*32+:4*32] = mxm_east_valid;
			assign mem_east_edge_data_o[HEMISPHERE_INDEX*4*32*64+:4*32*64] = mxm_east_data;
			assign mem_west_edge_valid_o[HEMISPHERE_INDEX*4*32+:4*32] = west_edge_valid;
			assign mem_west_edge_data_o[HEMISPHERE_INDEX*4*32*64+:4*32*64] = west_edge_data;
			assign mem_to_vxm_west_valid[HEMISPHERE_INDEX*4*32+:4*32] = west_edge_valid;
			assign mem_to_vxm_west_data[HEMISPHERE_INDEX*4*32*64+:4*32*64] = west_edge_data;
			assign host_mem_read_data[HEMISPHERE_INDEX*64+:64] = host_read;
			assign mem_fault_o[HEMISPHERE_INDEX*52*2*4+:52*2*4] = mem_fault;
			assign sxm_fault_o[HEMISPHERE_INDEX] = sxm_fault;
			assign mxm_fault_o[HEMISPHERE_INDEX] = mxm_fault;
			assign stream_conflict_o[HEMISPHERE_INDEX] = mem_stream_conflict | sxm_stream_conflict | mxm_stream_conflict | vxm_stream_conflict;
		end

	lpu_vxm_subsystem u_vxm (
		.clk_i,
		.rst_ni,
		.run_i(execution_run),
		.local_issue_valid_i(vxm_local_issue_valid),
		.local_issue_instruction_i(vxm_local_issue_instruction),
		.global_issue_valid_i(vxm_global_issue_valid),
		.global_issue_instruction_i(vxm_global_issue_instruction),
		.west_from_mem_valid_i(mem_to_vxm_west_valid),
		.west_from_mem_data_i(mem_to_vxm_west_data),
		.external_east_valid_i(mem_east_edge_valid_i),
		.external_east_data_i(mem_east_edge_data_i),
		.east_to_mem_valid_o(vxm_to_mem_east_valid),
		.east_to_mem_data_o(vxm_to_mem_east_data),
		.fault_o(vxm_fault_o),
		.conflict_o(vxm_stream_conflict)
	);
			assign program_endpoint_load_ready = '0;
			assign program_endpoint_commit_valid = '0;
			assign program_endpoint_commit_sequence_id = '0;
			assign program_endpoint_commit_error = '0;
			assign program_endpoint_start_ready = 1'b0;
			assign program_endpoint_started = 1'b0;
			assign program_endpoint_frontends_ready = 1'b0;
			assign program_endpoint_frontends_idle = 1'b0;
			assign program_endpoint_fault = 1'b0;
			assign program_endpoint_fault_code = '0;
			assign program_endpoint_schedule_cycle = '0;
			assign program_host_mem_read_data = '0;
			assign qctl_partition_ready_o = 1'b0;
			assign qctl_load_ready_o = 1'b0;
			assign qctl_event_ready_o = '0;
			assign qctl_sync_ready_o = '0;
			assign qctl_notify_valid_o = '0;
			assign qctl_mem_packet_valid_o = '0;
			assign qctl_mem_packet_ordinal_o = '0;
			assign qctl_queue_active_o = '0;
			assign qctl_wait_event_blocked_o = '0;
			assign qctl_wait_event_tag_o = '0;
			assign qctl_primed_o = '0;
			assign qctl_done_o = '0;
			assign qctl_fault_o = 1'b0;
			assign qctl_fault_code_o = '0;
		end
		else begin : gen_local_fu_subsystems
			lpu_fu_subsystem_cluster #(
				.MEM_IMEM_DEPTH(PROGRAM_MEM_IMEM_DEPTH),
				.MXM_IMEM_DEPTH(PROGRAM_MXM_IMEM_DEPTH),
				.ACTIVE_CONTEXTS(PROGRAM_ACTIVE_CONTEXTS),
				.MEM_DEPTH_ROWS(MEM_DEPTH_ROWS),
				.ACTIVE_MEM_COLUMNS(ACTIVE_MEM_COLUMNS),
				.MXM_ACCUMULATOR_BLOCK_COUNT(MXM_ACCUMULATOR_BLOCK_COUNT),
				.USE_SRAM_MACRO(USE_SRAM_MACRO),
				.ENABLE_QCTL(ENABLE_QCTL)
			) u_fu_subsystems (
				.clk_i,
				.rst_ni,
				.program_reset_i,
				.local_frontend_enable_i(1'b1),
				.external_run_i(run_i),
				.endpoint_load_valid_i(program_endpoint_load_valid),
				.endpoint_load_ready_o(program_endpoint_load_ready),
				.endpoint_load_command_i(program_endpoint_load_command),
				.endpoint_load_data_i(program_endpoint_load_data),
				.endpoint_load_strb_i(program_endpoint_load_strb),
				.endpoint_load_target_kind_i(program_endpoint_load_target_kind),
				.endpoint_load_queue_id_i(program_endpoint_load_queue_id),
				.endpoint_load_imem_address_i(program_endpoint_load_imem_address),
				.endpoint_load_last_i(program_endpoint_load_last),
				.endpoint_load_sequence_id_i(program_endpoint_load_sequence_id),
				.endpoint_commit_valid_o(program_endpoint_commit_valid),
				.endpoint_commit_ready_i(program_endpoint_commit_ready),
				.endpoint_commit_sequence_id_o(program_endpoint_commit_sequence_id),
				.endpoint_commit_error_o(program_endpoint_commit_error),
				.program_start_i(program_endpoint_start),
				.program_start_ready_o(program_endpoint_start_ready),
				.started_o(program_endpoint_started),
				.all_frontends_ready_o(program_endpoint_frontends_ready),
				.all_frontends_idle_o(program_endpoint_frontends_idle),
				.schedule_cycle_o(program_endpoint_schedule_cycle),
				.frontend_fault_o(program_endpoint_fault),
				.frontend_fault_code_o(program_endpoint_fault_code),
				.qctl_load_mode_i,
				.qctl_partition_valid_i,
				.qctl_partition_ready_o,
				.qctl_partition_queue_i,
				.qctl_partition_base_i,
				.qctl_partition_count_i,
				.qctl_partition_generation_i,
				.qctl_load_valid_i,
				.qctl_load_ready_o,
				.qctl_load_address_i,
				.qctl_load_data_i,
				.qctl_event_valid_i,
				.qctl_event_ready_o,
				.qctl_event_tag_i,
				.qctl_sync_valid_i,
				.qctl_sync_ready_o,
				.qctl_notify_valid_o,
				.qctl_notify_ready_i,
				.qctl_mem_packet_valid_o,
				.qctl_mem_packet_ordinal_o,
				.qctl_mem_packet_retired_i,
				.qctl_queue_active_o,
				.qctl_wait_event_blocked_o,
				.qctl_wait_event_tag_o,
				.qctl_primed_o,
				.qctl_done_o,
				.qctl_fault_o,
				.qctl_fault_code_o,
				.external_mem_issue_valid_i('0),
				.external_mem_issue_instruction_i('0),
				.external_mxm_load_issue_valid_i('0),
				.external_mxm_load_issue_instruction_i('0),
				.external_mxm_dequant_issue_valid_i('0),
				.external_mxm_dequant_issue_instruction_i('0),
				.external_mxm_compute_issue_valid_i('0),
				.external_mxm_compute_issue_instruction_i('0),
				.external_sxm_transpose_issue_valid_i('0),
				.external_sxm_transpose_issue_instruction_i('0),
				.external_sxm_permute_issue_valid_i('0),
				.external_sxm_permute_issue_instruction_i('0),
				.external_vxm_local_issue_valid_i('0),
				.external_vxm_local_issue_instruction_i('0),
				.external_vxm_global_issue_valid_i(1'b0),
				.external_vxm_global_issue_instruction_i('0),
				.local_mem_issue_valid_o(program_mem_issue_valid),
				.local_mem_issue_instruction_o(program_mem_issue_instruction),
				.local_mem_issue_cycle_o(program_mem_issue_cycle),
				.local_mxm_load_issue_valid_o(program_mxm_load_issue_valid),
				.local_mxm_load_issue_instruction_o(program_mxm_load_issue_instruction),
				.local_mxm_load_issue_cycle_o(program_mxm_load_issue_cycle),
				.local_mxm_dequant_issue_valid_o(program_mxm_dequant_issue_valid),
				.local_mxm_dequant_issue_instruction_o(program_mxm_dequant_issue_instruction),
				.local_mxm_dequant_issue_cycle_o(program_mxm_dequant_issue_cycle),
				.local_mxm_compute_issue_valid_o(program_mxm_compute_issue_valid),
				.local_mxm_compute_issue_instruction_o(program_mxm_compute_issue_instruction),
				.local_mxm_compute_issue_cycle_o(program_mxm_compute_issue_cycle),
				.host_mem_write_valid_i,
				.host_mem_column_i,
				.host_mem_bank_i,
				.host_mem_tile_i,
				.host_mem_address_i,
				.host_mem_write_data_i,
				.host_mem_read_data_o(program_host_mem_read_data),
				.mem_east_edge_valid_i,
				.mem_east_edge_data_i,
				.mem_east_edge_valid_o,
				.mem_east_edge_data_o,
				.mem_west_edge_valid_i,
				.mem_west_edge_data_i,
				.mem_west_edge_valid_o,
				.mem_west_edge_data_o,
				.mem_fault_o,
				.mxm_fault_o,
				.sxm_fault_o,
				.vxm_fault_o,
				.stream_conflict_o
			);
		end
	endgenerate

endmodule
