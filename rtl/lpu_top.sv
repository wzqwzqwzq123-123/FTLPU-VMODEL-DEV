module lpu_top #(
	parameter integer MEM_DEPTH_ROWS = lpu_pkg::SRAM_DEPTH_ROWS,
	parameter integer ACTIVE_MEM_COLUMNS = 52,
	parameter integer MXM_ACCUMULATOR_BLOCK_COUNT = lpu_pkg::MXM_ACCUMULATOR_BLOCK_COUNT,
	parameter bit USE_SRAM_MACRO = 1'b0,
	parameter bit USE_NATIVE_MEM = 1'b1,
	parameter integer PROGRAM_COMMAND_DEPTH = 32,
	parameter integer PROGRAM_DMA_DATA_WIDTH = 256,
	parameter integer PROGRAM_MEM_IMEM_DEPTH = 131072,
	parameter integer PROGRAM_MXM_IMEM_DEPTH = 65536,
	parameter integer PROGRAM_ACTIVE_CONTEXTS = 4,
	parameter bit ENABLE_QCTL = 1'b0,
	parameter integer QCTL_QUEUE_COUNT = 228,
	parameter integer PROGRAM_COMMAND_ADDRESS_WIDTH = PROGRAM_COMMAND_DEPTH <= 1 ? 1 : $clog2(PROGRAM_COMMAND_DEPTH)
) (
	input logic clk_i,
	input logic rst_ni,

	// Program Loader owns image descriptors and response reassembly after the external DMA.
	input logic program_reset_i,
	input logic program_cmd_write_valid_i,
	output logic program_cmd_write_ready_o,
	input logic [PROGRAM_COMMAND_ADDRESS_WIDTH-1:0] program_cmd_write_address_i,
	input logic [2:0] program_cmd_write_opcode_i,
	input logic [63:0] program_cmd_write_source_address_i,
	input logic [31:0] program_cmd_write_byte_count_i,
	input logic [lpu_program_load_pkg::PROGRAM_DESTINATION_WIDTH-1:0]
		program_cmd_write_destination_i,
	input logic [1:0] program_cmd_write_format_i,
	input logic [1:0] program_cmd_write_encoding_mode_i,
	input logic [16:0] program_cmd_write_imem_base_address_i,
	input logic program_cmd_write_image_first_i,
	input logic program_cmd_write_image_last_i,
	input logic [15:0] program_cmd_write_expected_word_count_i,
	input logic [PROGRAM_COMMAND_ADDRESS_WIDTH-1:0] program_cmd_write_jump_address_i,
	input logic program_load_start_valid_i,
	output logic program_load_start_ready_o,
	input logic [PROGRAM_COMMAND_ADDRESS_WIDTH:0] program_load_start_command_count_i,
	output logic program_ddr_read_req_valid_o,
	input logic program_ddr_read_req_ready_i,
	output logic [63:0] program_ddr_read_req_address_o,
	output logic [31:0] program_ddr_read_req_length_o,
	output logic [7:0] program_ddr_read_req_id_o,
	input logic program_ddr_read_rsp_valid_i,
	output logic program_ddr_read_rsp_ready_o,
	input logic [PROGRAM_DMA_DATA_WIDTH-1:0] program_ddr_read_rsp_data_i,
	input logic [PROGRAM_DMA_DATA_WIDTH/8-1:0] program_ddr_read_rsp_keep_i,
	input logic program_ddr_read_rsp_last_i,
	input logic [7:0] program_ddr_read_rsp_id_i,
	input logic program_ddr_read_rsp_error_i,
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
	input logic [QCTL_QUEUE_COUNT-1:0] qctl_sync_participant_mask_i,
	input logic qctl_event_valid_i,
	output logic qctl_event_ready_o,
	input logic [31:0] qctl_event_tag_i,
	input logic [QCTL_QUEUE_COUNT-1:0] qctl_event_target_mask_i,
	output logic qctl_event_backpressure_o,
	output logic [QCTL_QUEUE_COUNT-1:0] qctl_mem_packet_valid_o,
	output logic [QCTL_QUEUE_COUNT*32-1:0] qctl_mem_packet_ordinal_o,
	input logic [QCTL_QUEUE_COUNT-1:0] qctl_mem_packet_retired_i,
	output logic [QCTL_QUEUE_COUNT-1:0] qctl_queue_active_o,
	output logic [QCTL_QUEUE_COUNT-1:0] qctl_wait_event_blocked_o,
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
	output logic [lpu_pkg::MEM_BANK_COUNT-1:0] mem_fault_o,
	output logic [1:0] mxm_fault_o,
	output logic [1:0] sxm_fault_o,
	output logic vxm_fault_o,
	output logic [1:0] stream_conflict_o,
	output logic [63:0] cycle_o
);
	localparam integer MEM_BANK_COUNT = lpu_pkg::MEM_BANK_COUNT;
	localparam integer PROGRAM_RELAY_PORT_COUNT = lpu_program_load_pkg::PROGRAM_RELAY_PORT_COUNT;
	localparam integer PROGRAM_LOAD_CONTROL_WIDTH = lpu_program_load_pkg::PROGRAM_LOAD_CONTROL_WIDTH;
	localparam integer PROGRAM_DESTINATION_WIDTH = lpu_program_load_pkg::PROGRAM_DESTINATION_WIDTH;

	logic [MEM_BANK_COUNT-1:0] local_mem_issue_valid;
	logic [MEM_BANK_COUNT*lpu_pkg::MEM_INSTRUCTION_WIDTH-1:0] local_mem_issue_instruction;
	logic [MEM_BANK_COUNT*32-1:0] local_mem_issue_cycle;
	logic [3:0] local_mxm_load_issue_valid;
	logic [4*lpu_mxm_isa_pkg::LOAD_INSTRUCTION_BITS-1:0] local_mxm_load_issue_instruction;
	logic [4*32-1:0] local_mxm_load_issue_cycle;
	logic [3:0] local_mxm_dequant_issue_valid;
	logic [4*lpu_mxm_isa_pkg::DEQUANT_INSTRUCTION_BITS-1:0] local_mxm_dequant_issue_instruction;
	logic [4*32-1:0] local_mxm_dequant_issue_cycle;
	logic [3:0] local_mxm_compute_issue_valid;
	logic [4*lpu_mxm_isa_pkg::COMPUTE_INSTRUCTION_BITS-1:0] local_mxm_compute_issue_instruction;
	logic [4*32-1:0] local_mxm_compute_issue_cycle;
	logic [3:0] local_mxm_param_load_issue_valid;
	logic [4*lpu_mxm_isa_pkg::PARAM_LOAD_INSTRUCTION_BITS-1:0] local_mxm_param_load_issue_instruction;
	logic [4*32-1:0] local_mxm_param_load_issue_cycle;
	logic [3:0] local_mxm_backend_issue_valid;
	logic [4*lpu_mxm_backend_isa_pkg::BACKEND_INSTRUCTION_BITS-1:0] local_mxm_backend_issue_instruction;
	logic [4*32-1:0] local_mxm_backend_issue_cycle;
	logic load_distribute_valid;
	logic load_distribute_ready;
	logic [lpu_program_load_pkg::PROGRAM_LOAD_CONTROL_WIDTH-1:0] load_distribute_control;
	logic [127:0] load_distribute_data;
	logic [3:0] load_distribute_strb;
	logic [1:0] load_distribute_scope;
	logic [PROGRAM_DESTINATION_WIDTH-1:0] load_distribute_destination;
	logic [16:0] load_distribute_imem_address;
	logic load_distribute_last;
	logic load_distribute_idle;
	logic load_distribute_fault;
	logic [5:0] load_distribute_fault_code;
	logic [PROGRAM_RELAY_PORT_COUNT-1:0] mem_program_valid;
	logic [PROGRAM_RELAY_PORT_COUNT-1:0] mem_program_ready;
	logic [PROGRAM_RELAY_PORT_COUNT*PROGRAM_LOAD_CONTROL_WIDTH-1:0] mem_program_control;
	logic [PROGRAM_RELAY_PORT_COUNT*PROGRAM_DESTINATION_WIDTH-1:0] mem_program_destination;
	logic [PROGRAM_RELAY_PORT_COUNT*17-1:0] mem_program_imem_address;
	logic [PROGRAM_RELAY_PORT_COUNT*128-1:0] mem_program_data;
	logic [PROGRAM_RELAY_PORT_COUNT*4-1:0] mem_program_strb;
	logic [PROGRAM_RELAY_PORT_COUNT-1:0] mem_program_last;
	logic [PROGRAM_RELAY_PORT_COUNT-1:0] mem_program_error;
	logic [3:0] mxm_program_valid;
	logic [3:0] mxm_program_ready;
	logic [3:0] mxm_program_error;
	logic [1:0] sxm_program_valid;
	logic [1:0] sxm_program_ready;
	logic [1:0] sxm_program_error;
	logic [2*PROGRAM_LOAD_CONTROL_WIDTH-1:0] outer_program_control;
	logic [2*PROGRAM_DESTINATION_WIDTH-1:0] outer_program_destination;
	logic [33:0] outer_program_address;
	logic [255:0] outer_program_data;
	logic [7:0] outer_program_strb;
	logic [1:0] outer_program_last;
	logic vxm_program_valid;
	logic vxm_program_ready;
	logic vxm_program_error;
	logic [PROGRAM_LOAD_CONTROL_WIDTH-1:0] vxm_program_control;
	logic [PROGRAM_DESTINATION_WIDTH-1:0] vxm_program_destination;
	logic [16:0] vxm_program_address;
	logic [127:0] vxm_program_data;
	logic [3:0] vxm_program_strb;
	logic vxm_program_last;
	logic fu_cluster_program_start;
	logic fu_cluster_program_start_ready;
	logic fu_cluster_started;
	logic fu_cluster_frontends_ready;
	logic fu_cluster_frontends_idle;
	logic fu_cluster_fault;
	logic [5:0] fu_cluster_fault_code;
	logic [31:0] fu_cluster_schedule_cycle;

	assign cycle_o = {32'd0, fu_cluster_schedule_cycle};

	// Program Load owns DMA response buffering, Word reassembly and Program records.
	lpu_program_load_system #(
		.COMMAND_DEPTH(PROGRAM_COMMAND_DEPTH), .DMA_DATA_WIDTH(PROGRAM_DMA_DATA_WIDTH),
		.MEM_IMEM_DEPTH(PROGRAM_MEM_IMEM_DEPTH), .MXM_IMEM_DEPTH(PROGRAM_MXM_IMEM_DEPTH),
		.COMMAND_ADDRESS_WIDTH(PROGRAM_COMMAND_ADDRESS_WIDTH)
	) u_program_load_system (
		.clk_i, .rst_ni, .program_reset_i,
		.program_cmd_write_valid_i(program_cmd_write_valid_i), .program_cmd_write_ready_o(program_cmd_write_ready_o),
		.program_cmd_write_address_i(program_cmd_write_address_i), .program_cmd_write_opcode_i(program_cmd_write_opcode_i),
		.program_cmd_write_source_address_i(program_cmd_write_source_address_i), .program_cmd_write_byte_count_i(program_cmd_write_byte_count_i),
		.program_cmd_write_destination_i(program_cmd_write_destination_i),
		.program_cmd_write_format_i(program_cmd_write_format_i), .program_cmd_write_encoding_mode_i(program_cmd_write_encoding_mode_i),
		.program_cmd_write_imem_base_address_i(program_cmd_write_imem_base_address_i), .program_cmd_write_image_first_i(program_cmd_write_image_first_i),
		.program_cmd_write_image_last_i(program_cmd_write_image_last_i), .program_cmd_write_expected_word_count_i(program_cmd_write_expected_word_count_i),
		.program_cmd_write_jump_address_i(program_cmd_write_jump_address_i),
		.program_load_start_valid_i(program_load_start_valid_i), .program_load_start_ready_o(program_load_start_ready_o),
		.program_load_start_command_count_i(program_load_start_command_count_i), .ddr_read_req_valid_o(program_ddr_read_req_valid_o),
		.ddr_read_req_ready_i(program_ddr_read_req_ready_i), .ddr_read_req_address_o(program_ddr_read_req_address_o),
		.ddr_read_req_length_o(program_ddr_read_req_length_o), .ddr_read_req_id_o(program_ddr_read_req_id_o),
		.ddr_read_rsp_valid_i(program_ddr_read_rsp_valid_i), .ddr_read_rsp_ready_o(program_ddr_read_rsp_ready_o),
		.ddr_read_rsp_data_i(program_ddr_read_rsp_data_i), .ddr_read_rsp_keep_i(program_ddr_read_rsp_keep_i),
		.ddr_read_rsp_last_i(program_ddr_read_rsp_last_i), .ddr_read_rsp_id_i(program_ddr_read_rsp_id_i), .ddr_read_rsp_error_i(program_ddr_read_rsp_error_i),
		.program_start_request_i, .dependencies_ready_i(program_dependencies_ready_i), .program_start_ack_o,
		.program_load_complete_o, .program_ready_o, .program_running_o, .program_done_o,
		.program_fault_o, .program_fault_code_o, .schedule_cycle_o(program_schedule_cycle_o),
		.load_distribute_valid_o(load_distribute_valid), .load_distribute_ready_i(load_distribute_ready),
		.load_distribute_control_o(load_distribute_control), .load_distribute_data_o(load_distribute_data),
		.load_distribute_strb_o(load_distribute_strb), .load_distribute_scope_o(load_distribute_scope),
		.load_distribute_destination_o(load_distribute_destination),
		.load_distribute_imem_address_o(load_distribute_imem_address),
		.load_distribute_last_o(load_distribute_last), .load_distribute_idle_i(load_distribute_idle),
		.load_distribute_fault_i(load_distribute_fault),
		.load_distribute_fault_code_i(load_distribute_fault_code),
		.fu_cluster_program_start_o(fu_cluster_program_start), .fu_cluster_program_start_ready_i(fu_cluster_program_start_ready),
		.fu_cluster_started_i(fu_cluster_started), .fu_cluster_frontends_ready_i(fu_cluster_frontends_ready),
		.fu_cluster_frontends_idle_i(fu_cluster_frontends_idle), .fu_cluster_fault_i(fu_cluster_fault),
		.fu_cluster_fault_code_i(fu_cluster_fault_code), .fu_cluster_schedule_cycle_i(fu_cluster_schedule_cycle)
	);

	// Program Distribution owns destination decode, both Relay chains and FU-local routing.
	lpu_program_distribute_system u_program_distribute_system (
		.clk_i,
		.rst_ni,
		.program_reset_i,
		.load_distribute_valid_i(load_distribute_valid),
		.load_distribute_ready_o(load_distribute_ready),
		.load_distribute_control_i(load_distribute_control),
		.load_distribute_data_i(load_distribute_data),
		.load_distribute_strb_i(load_distribute_strb),
		.load_distribute_scope_i(load_distribute_scope),
		.load_distribute_destination_i(load_distribute_destination),
		.load_distribute_imem_address_i(load_distribute_imem_address),
		.load_distribute_last_i(load_distribute_last),
		.mem_program_valid_o(mem_program_valid),
		.mem_program_ready_i(mem_program_ready),
		.mem_program_control_o(mem_program_control),
		.mem_program_destination_o(mem_program_destination),
		.mem_program_imem_address_o(mem_program_imem_address),
		.mem_program_data_o(mem_program_data),
		.mem_program_strb_o(mem_program_strb),
		.mem_program_last_o(mem_program_last),
		.mem_program_error_i(mem_program_error),
		.mxm_program_valid_o(mxm_program_valid),
		.mxm_program_ready_i(mxm_program_ready),
		.mxm_program_error_i(mxm_program_error),
		.sxm_program_valid_o(sxm_program_valid),
		.sxm_program_ready_i(sxm_program_ready),
		.sxm_program_error_i(sxm_program_error),
		.outer_program_control_o(outer_program_control),
		.outer_program_destination_o(outer_program_destination),
		.outer_program_address_o(outer_program_address),
		.outer_program_data_o(outer_program_data),
		.outer_program_strb_o(outer_program_strb),
		.outer_program_last_o(outer_program_last),
		.vxm_program_valid_o(vxm_program_valid),
		.vxm_program_ready_i(vxm_program_ready),
		.vxm_program_error_i(vxm_program_error),
		.vxm_program_control_o(vxm_program_control),
		.vxm_program_destination_o(vxm_program_destination),
		.vxm_program_address_o(vxm_program_address),
		.vxm_program_data_o(vxm_program_data),
		.vxm_program_strb_o(vxm_program_strb),
		.vxm_program_last_o(vxm_program_last),
		.idle_o(load_distribute_idle),
		.fault_o(load_distribute_fault),
		.fault_code_o(load_distribute_fault_code)
	);

	// FU Cluster owns QCTL, Schedule Cycle and all FU-local instruction Frontends.
	lpu_fu_subsystem_cluster #(
		.MEM_IMEM_DEPTH(PROGRAM_MEM_IMEM_DEPTH), .MXM_IMEM_DEPTH(PROGRAM_MXM_IMEM_DEPTH),
		.ACTIVE_CONTEXTS(PROGRAM_ACTIVE_CONTEXTS), .MEM_DEPTH_ROWS(MEM_DEPTH_ROWS),
		.ACTIVE_MEM_COLUMNS(ACTIVE_MEM_COLUMNS), .MXM_ACCUMULATOR_BLOCK_COUNT(MXM_ACCUMULATOR_BLOCK_COUNT),
		.USE_SRAM_MACRO(USE_SRAM_MACRO), .USE_NATIVE_MEM(USE_NATIVE_MEM),
		.ENABLE_QCTL(ENABLE_QCTL),
		.QCTL_QUEUE_COUNT(QCTL_QUEUE_COUNT)
	) u_fu_subsystems (
		.clk_i, .rst_ni, .program_reset_i,
		.mem_program_valid_i(mem_program_valid), .mem_program_ready_o(mem_program_ready),
		.mem_program_control_i(mem_program_control),
		.mem_program_destination_i(mem_program_destination),
		.mem_program_imem_address_i(mem_program_imem_address), .mem_program_data_i(mem_program_data),
		.mem_program_strb_i(mem_program_strb), .mem_program_last_i(mem_program_last),
		.mem_program_error_o(mem_program_error),
		.mxm_program_valid_i(mxm_program_valid), .mxm_program_ready_o(mxm_program_ready),
		.mxm_program_error_o(mxm_program_error),
		.sxm_program_valid_i(sxm_program_valid), .sxm_program_ready_o(sxm_program_ready),
		.sxm_program_error_o(sxm_program_error),
		.outer_program_control_i(outer_program_control),
		.outer_program_destination_i(outer_program_destination),
		.outer_program_address_i(outer_program_address), .outer_program_data_i(outer_program_data),
		.outer_program_strb_i(outer_program_strb), .outer_program_last_i(outer_program_last),
		.vxm_program_valid_i(vxm_program_valid), .vxm_program_ready_o(vxm_program_ready),
		.vxm_program_error_o(vxm_program_error), .vxm_program_control_i(vxm_program_control),
		.vxm_program_destination_i(vxm_program_destination),
		.vxm_program_address_i(vxm_program_address), .vxm_program_data_i(vxm_program_data),
		.vxm_program_strb_i(vxm_program_strb), .vxm_program_last_i(vxm_program_last),
		.program_start_i(fu_cluster_program_start), .program_start_ready_o(fu_cluster_program_start_ready),
		.started_o(fu_cluster_started), .all_frontends_ready_o(fu_cluster_frontends_ready),
		.all_frontends_idle_o(fu_cluster_frontends_idle), .schedule_cycle_o(fu_cluster_schedule_cycle),
		.frontend_fault_o(fu_cluster_fault), .frontend_fault_code_o(fu_cluster_fault_code),
		.qctl_load_mode_i, .qctl_partition_valid_i, .qctl_partition_ready_o, .qctl_partition_queue_i,
		.qctl_partition_base_i, .qctl_partition_count_i, .qctl_partition_generation_i,
		.qctl_load_valid_i, .qctl_load_ready_o, .qctl_load_address_i, .qctl_load_data_i,
		.qctl_sync_participant_mask_i, .qctl_event_valid_i, .qctl_event_ready_o, .qctl_event_tag_i,
		.qctl_event_target_mask_i, .qctl_event_backpressure_o,
		.qctl_mem_packet_valid_o, .qctl_mem_packet_ordinal_o,
		.qctl_mem_packet_retired_i, .qctl_queue_active_o, .qctl_wait_event_blocked_o,
		.qctl_primed_o, .qctl_done_o, .qctl_fault_o, .qctl_fault_code_o,
		.local_mem_issue_valid_o(local_mem_issue_valid), .local_mem_issue_instruction_o(local_mem_issue_instruction),
		.local_mem_issue_cycle_o(local_mem_issue_cycle), .local_mxm_load_issue_valid_o(local_mxm_load_issue_valid),
		.local_mxm_load_issue_instruction_o(local_mxm_load_issue_instruction), .local_mxm_load_issue_cycle_o(local_mxm_load_issue_cycle),
		.local_mxm_dequant_issue_valid_o(local_mxm_dequant_issue_valid), .local_mxm_dequant_issue_instruction_o(local_mxm_dequant_issue_instruction),
		.local_mxm_dequant_issue_cycle_o(local_mxm_dequant_issue_cycle), .local_mxm_compute_issue_valid_o(local_mxm_compute_issue_valid),
		.local_mxm_compute_issue_instruction_o(local_mxm_compute_issue_instruction), .local_mxm_compute_issue_cycle_o(local_mxm_compute_issue_cycle),
		.local_mxm_param_load_issue_valid_o(local_mxm_param_load_issue_valid),
		.local_mxm_param_load_issue_instruction_o(local_mxm_param_load_issue_instruction),
		.local_mxm_param_load_issue_cycle_o(local_mxm_param_load_issue_cycle),
		.local_mxm_backend_issue_valid_o(local_mxm_backend_issue_valid),
		.local_mxm_backend_issue_instruction_o(local_mxm_backend_issue_instruction),
		.local_mxm_backend_issue_cycle_o(local_mxm_backend_issue_cycle),
		.mem_east_edge_valid_i, .mem_east_edge_data_i,
		.mem_east_edge_valid_o, .mem_east_edge_data_o, .mem_west_edge_valid_i, .mem_west_edge_data_i,
		.mem_west_edge_valid_o, .mem_west_edge_data_o, .mem_fault_o, .mxm_fault_o, .sxm_fault_o,
		.vxm_fault_o, .stream_conflict_o
	);
endmodule
