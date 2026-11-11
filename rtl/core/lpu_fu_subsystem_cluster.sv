module lpu_fu_subsystem_cluster #(
	parameter integer MEM_IMEM_DEPTH = 131072,
	parameter integer MXM_IMEM_DEPTH = 65536,
	parameter integer ACTIVE_CONTEXTS = 4,
	parameter integer MEM_DEPTH_ROWS = lpu_pkg::SRAM_DEPTH_ROWS,
	parameter integer ACTIVE_MEM_COLUMNS = 52,
	parameter integer MXM_ACCUMULATOR_BLOCK_COUNT = lpu_pkg::MXM_ACCUMULATOR_BLOCK_COUNT,
	parameter bit USE_SRAM_MACRO = 1'b0,
	parameter bit USE_NATIVE_MEM = 1'b1,
	parameter bit ENABLE_QCTL = 1'b0,
	parameter integer QCTL_QUEUE_COUNT = 220,
	parameter integer QCTL_POOL_DEPTH = 512,
	parameter integer QCTL_QUEUE_ENTRY_LIMIT = 16,
	parameter integer QCTL_CACHE_DEPTH = 4
) (
	input logic clk_i,
	input logic rst_ni,
	input logic program_reset_i,
	input logic local_frontend_enable_i,
	input logic external_run_i,

	input logic [1:0] endpoint_load_valid_i,
	output logic [1:0] endpoint_load_ready_o,
	input logic [2*lpu_program_load_pkg::PROGRAM_LOAD_CONTROL_WIDTH-1:0] endpoint_load_control_i,
	input logic [255:0] endpoint_load_data_i,
	input logic [7:0] endpoint_load_strb_i,
	input logic [23:0] endpoint_load_destination_i,
	input logic [33:0] endpoint_load_imem_address_i,
	input logic [1:0] endpoint_load_last_i,
	output logic [1:0] endpoint_commit_valid_o,
	input logic [1:0] endpoint_commit_ready_i,
	output logic [1:0] endpoint_commit_error_o,

	input logic program_start_i,
	output logic program_start_ready_o,
	output logic started_o,
	output logic all_frontends_ready_o,
	output logic all_frontends_idle_o,
	output logic [31:0] schedule_cycle_o,
	output logic frontend_fault_o,
	output logic [5:0] frontend_fault_code_o,

	// QCTL has 208 MEM Bank lanes followed by four MXM Load, four Dequant and
	// four Compute lanes. VXM/SXM Queue IDs remain reserved for later closure.
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

	input logic [lpu_pkg::MEM_BANK_COUNT-1:0] external_mem_issue_valid_i,
	output logic [lpu_pkg::MEM_BANK_COUNT-1:0] external_mem_issue_ready_o,
	input logic [lpu_pkg::MEM_BANK_COUNT*lpu_pkg::MEM_INSTRUCTION_WIDTH-1:0] external_mem_issue_instruction_i,
	input logic [3:0] external_mxm_load_issue_valid_i,
	input logic [4*48-1:0] external_mxm_load_issue_instruction_i,
	input logic [3:0] external_mxm_dequant_issue_valid_i,
	input logic [4*16-1:0] external_mxm_dequant_issue_instruction_i,
	input logic [3:0] external_mxm_compute_issue_valid_i,
	input logic [4*48-1:0] external_mxm_compute_issue_instruction_i,
	input logic [1:0] external_sxm_transpose_issue_valid_i,
	input logic [2*416-1:0] external_sxm_transpose_issue_instruction_i,
	input logic [1:0] external_sxm_permute_issue_valid_i,
	input logic [2*416-1:0] external_sxm_permute_issue_instruction_i,
	input logic [7:0] external_vxm_local_issue_valid_i,
	input logic [8*lpu_pkg::VXM_LOCAL_MAX_INSTRUCTION_WIDTH-1:0] external_vxm_local_issue_instruction_i,
	input logic external_vxm_global_issue_valid_i,
	input logic [lpu_pkg::VXM_GLOBAL_CONFIG_WIDTH-1:0] external_vxm_global_issue_instruction_i,

	output logic [lpu_pkg::MEM_BANK_COUNT-1:0] local_mem_issue_valid_o,
	output logic [lpu_pkg::MEM_BANK_COUNT*lpu_pkg::MEM_INSTRUCTION_WIDTH-1:0] local_mem_issue_instruction_o,
	output logic [lpu_pkg::MEM_BANK_COUNT*32-1:0] local_mem_issue_cycle_o,
	output logic [3:0] local_mxm_load_issue_valid_o,
	output logic [4*29-1:0] local_mxm_load_issue_instruction_o,
	output logic [4*32-1:0] local_mxm_load_issue_cycle_o,
	output logic [3:0] local_mxm_dequant_issue_valid_o,
	output logic [4*16-1:0] local_mxm_dequant_issue_instruction_o,
	output logic [4*32-1:0] local_mxm_dequant_issue_cycle_o,
	output logic [3:0] local_mxm_compute_issue_valid_o,
	output logic [4*49-1:0] local_mxm_compute_issue_instruction_o,
	output logic [4*32-1:0] local_mxm_compute_issue_cycle_o,

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
	output logic [1:0] stream_conflict_o
);
	import lpu_program_load_pkg::*;

	localparam logic [5:0] FAULT_NONE = 6'd0;
	localparam logic [5:0] FAULT_ROUTE = 6'd1;
	localparam logic [5:0] FAULT_FRONTEND = 6'd2;
	localparam logic [5:0] FAULT_QCTL = 6'd3;
	localparam integer QCTL_MXM_LOAD_BASE = lpu_pkg::MEM_BANK_COUNT;
	localparam integer QCTL_MXM_DEQUANT_BASE = QCTL_MXM_LOAD_BASE + 4;
	localparam integer QCTL_MXM_COMPUTE_BASE = QCTL_MXM_DEQUANT_BASE + 4;

	logic started_q;
	logic [31:0] schedule_cycle_q;
	logic execution_run;
	logic route_fault_q;
	logic [1:0] selected_ready_w;
	logic [1:0] selected_valid_w;
	logic [1:0] destination_hemisphere_match_w;
	logic [5:0] destination_target_kind_w;
	logic [15:0] destination_target_index_w;
	logic [1:0] write_fire_w;
	logic [1:0] write_error_w;
	logic [1:0] route_error_fire_w;
	logic [1:0] commit_valid_q;
	logic [1:0] commit_error_q;

	logic [1:0] mem_program_valid;
	logic [1:0] mem_program_ready;
	logic [1:0] mem_program_error;
	logic [1:0] mem_frontends_ready;
	logic [1:0] mem_frontends_idle;
	logic [1:0] mem_frontend_fault;
	logic [11:0] mem_frontend_fault_code;

	logic [3:0] mxm_program_valid;
	logic [3:0] mxm_program_ready;
	logic [3:0] mxm_program_error;
	logic [3:0] mxm_frontends_ready;
	logic [3:0] mxm_frontends_idle;
	logic [3:0] mxm_frontend_fault;
	logic [23:0] mxm_frontend_fault_code;

	logic [2*4*32-1:0] mem_to_vxm_west_valid;
	logic [2*4*32*64-1:0] mem_to_vxm_west_data;
	logic [2*4*32-1:0] vxm_to_mem_east_valid;
	logic [2*4*32*64-1:0] vxm_to_mem_east_data;
	logic vxm_stream_conflict;
	logic [QCTL_QUEUE_COUNT-1:0] qctl_scheduler_enable;
	logic [QCTL_QUEUE_COUNT*32-1:0] qctl_queue_cycle;
	logic qctl_all_primed;
	logic qctl_all_done;

	assign execution_run = local_frontend_enable_i ? started_q : external_run_i;
	assign started_o = started_q;
	assign schedule_cycle_o = schedule_cycle_q;
	assign endpoint_commit_valid_o = commit_valid_q;
	assign endpoint_commit_error_o = commit_error_q;
	assign all_frontends_ready_o = (&mem_frontends_ready) && (&mxm_frontends_ready) &&
		(!ENABLE_QCTL || qctl_all_primed) && !(|commit_valid_q) && !frontend_fault_o;
	assign all_frontends_idle_o = (&mem_frontends_idle) && (&mxm_frontends_idle);
	assign program_start_ready_o = local_frontend_enable_i && all_frontends_ready_o && !started_q;
	assign frontend_fault_o = route_fault_q || (|mem_frontend_fault) ||
		(|mxm_frontend_fault) || (ENABLE_QCTL && qctl_fault_o);
	assign frontend_fault_code_o = route_fault_q ? FAULT_ROUTE :
		(((|mem_frontend_fault) || (|mxm_frontend_fault)) ? FAULT_FRONTEND :
		((ENABLE_QCTL && qctl_fault_o) ? FAULT_QCTL : FAULT_NONE));

	// Shared storage is global, while every generated Controller owns exactly one
	// Queue-local Scheduler clock. Inactive lanes bypass QCTL in the FU subsystem.
	generate
		if(ENABLE_QCTL)begin : gen_qctl
			lpu_qctl_fabric #(
				.POOL_DEPTH(QCTL_POOL_DEPTH),
				.QUEUE_COUNT(QCTL_QUEUE_COUNT),
				.QUEUE_ENTRY_LIMIT(QCTL_QUEUE_ENTRY_LIMIT),
				.CACHE_DEPTH(QCTL_CACHE_DEPTH)
			) u_qctl_fabric (
				.clk_i,
				.rst_ni,
				.clear_i(program_reset_i),
				.run_i(execution_run),
				.load_mode_i(qctl_load_mode_i),
				.partition_valid_i(qctl_partition_valid_i),
				.partition_ready_o(qctl_partition_ready_o),
				.partition_queue_i(qctl_partition_queue_i),
				.partition_base_i(qctl_partition_base_i),
				.partition_count_i(qctl_partition_count_i),
				.partition_generation_i(qctl_partition_generation_i),
				.load_valid_i(qctl_load_valid_i),
				.load_ready_o(qctl_load_ready_o),
				.load_address_i(qctl_load_address_i),
				.load_data_i(qctl_load_data_i),
				.event_valid_i(qctl_event_valid_i),
				.event_ready_o(qctl_event_ready_o),
				.event_tag_i(qctl_event_tag_i),
				.sync_valid_i(qctl_sync_valid_i),
				.sync_ready_o(qctl_sync_ready_o),
				.notify_valid_o(qctl_notify_valid_o),
				.notify_ready_i(qctl_notify_ready_i),
				.mem_packet_valid_o(qctl_mem_packet_valid_o),
				.mem_packet_ordinal_o(qctl_mem_packet_ordinal_o),
				.mem_packet_retired_i(qctl_mem_packet_retired_i),
				.queue_active_o(qctl_queue_active_o),
				.scheduler_enable_o(qctl_scheduler_enable),
				.queue_cycle_o(qctl_queue_cycle),
				.wait_event_blocked_o(qctl_wait_event_blocked_o),
				.wait_event_tag_o(qctl_wait_event_tag_o),
				.primed_o(qctl_primed_o),
				.done_o(qctl_done_o),
				.all_primed_o(qctl_all_primed),
				.all_done_o(qctl_all_done),
				.fault_o(qctl_fault_o),
				.fault_code_o(qctl_fault_code_o)
			);
		end
		else begin : gen_no_qctl
			assign qctl_partition_ready_o = 1'b0;
			assign qctl_load_ready_o = 1'b0;
			assign qctl_event_ready_o = '0;
			assign qctl_sync_ready_o = '0;
			assign qctl_notify_valid_o = '0;
			assign qctl_mem_packet_valid_o = '0;
			assign qctl_mem_packet_ordinal_o = '0;
			assign qctl_queue_active_o = '0;
			assign qctl_scheduler_enable = '0;
			assign qctl_queue_cycle = '0;
			assign qctl_wait_event_blocked_o = '0;
			assign qctl_wait_event_tag_o = '0;
			assign qctl_primed_o = '1;
			assign qctl_done_o = '1;
			assign qctl_all_primed = 1'b1;
			assign qctl_all_done = 1'b1;
			assign qctl_fault_o = 1'b0;
			assign qctl_fault_code_o = '0;
		end
	endgenerate

	generate
		for(genvar destination_gen = 0; destination_gen < 2; destination_gen = destination_gen + 1)begin : gen_destination_fields
			assign destination_hemisphere_match_w[destination_gen] =
				endpoint_load_destination_i[destination_gen*PROGRAM_DESTINATION_WIDTH+
					PROGRAM_DESTINATION_HEMISPHERE_BIT] ==
					(destination_gen == 0 ? PROGRAM_HEMISPHERE_EAST : PROGRAM_HEMISPHERE_WEST);
			assign destination_target_kind_w[destination_gen*PROGRAM_TARGET_KIND_WIDTH+:
				PROGRAM_TARGET_KIND_WIDTH] = endpoint_load_destination_i[
				destination_gen*PROGRAM_DESTINATION_WIDTH+PROGRAM_DESTINATION_KIND_LSB+:
				PROGRAM_TARGET_KIND_WIDTH];
			assign destination_target_index_w[destination_gen*PROGRAM_TARGET_INDEX_WIDTH+:
				PROGRAM_TARGET_INDEX_WIDTH] = endpoint_load_destination_i[
				destination_gen*PROGRAM_DESTINATION_WIDTH+PROGRAM_DESTINATION_INDEX_LSB+:
				PROGRAM_TARGET_INDEX_WIDTH];
		end
	endgenerate

	// The cluster only routes Program Load traffic; all instruction state lives inside FU subsystems.
	always_comb begin
		endpoint_load_ready_o = '0;
		selected_ready_w = '0;
		selected_valid_w = '0;
		write_fire_w = '0;
		write_error_w = '0;
		route_error_fire_w = '0;
		mem_program_valid = '0;
		mxm_program_valid = '0;

		for(integer hemisphere = 0; hemisphere < 2; hemisphere = hemisphere + 1)begin
			selected_ready_w[hemisphere] = 1'b1;
			case(destination_target_kind_w[hemisphere*PROGRAM_TARGET_KIND_WIDTH+:
				PROGRAM_TARGET_KIND_WIDTH])
				PROGRAM_TARGET_MEM: begin
					selected_valid_w[hemisphere] =
						destination_hemisphere_match_w[hemisphere] &&
						(destination_target_index_w[hemisphere*PROGRAM_TARGET_INDEX_WIDTH+:
						 PROGRAM_TARGET_INDEX_WIDTH] < lpu_pkg::MEM_BANKS_PER_HEMISPHERE);
					selected_ready_w[hemisphere] = selected_valid_w[hemisphere] ?
						mem_program_ready[hemisphere] : 1'b1;
				end
				PROGRAM_TARGET_MXM_LOAD,
				PROGRAM_TARGET_MXM_DEQUANT,
				PROGRAM_TARGET_MXM_COMPUTE: begin
					if(destination_hemisphere_match_w[hemisphere] &&
						destination_target_index_w[hemisphere*PROGRAM_TARGET_INDEX_WIDTH+:
							PROGRAM_TARGET_INDEX_WIDTH] < 2)begin
						selected_valid_w[hemisphere] = 1'b1;
						selected_ready_w[hemisphere] = mxm_program_ready[
							hemisphere*2 + destination_target_index_w[
							hemisphere*PROGRAM_TARGET_INDEX_WIDTH+:PROGRAM_TARGET_INDEX_WIDTH]];
					end
				end
				default: selected_valid_w[hemisphere] = 1'b0;
			endcase

			endpoint_load_ready_o[hemisphere] = selected_ready_w[hemisphere] &&
				((endpoint_load_control_i[hemisphere] != PROGRAM_LOAD_WRITE) ||
				 !commit_valid_q[hemisphere] || endpoint_commit_ready_i[hemisphere]);
			write_fire_w[hemisphere] = endpoint_load_valid_i[hemisphere] &&
				endpoint_load_ready_o[hemisphere] &&
				(endpoint_load_control_i[hemisphere] == PROGRAM_LOAD_WRITE);

			mem_program_valid[hemisphere] = endpoint_load_valid_i[hemisphere] &&
				endpoint_load_ready_o[hemisphere] &&
				(destination_target_kind_w[hemisphere*PROGRAM_TARGET_KIND_WIDTH+:
				 PROGRAM_TARGET_KIND_WIDTH] == PROGRAM_TARGET_MEM) && selected_valid_w[hemisphere];

			for(integer local_mxm = 0; local_mxm < 2; local_mxm = local_mxm + 1)begin
				mxm_program_valid[hemisphere*2+local_mxm] = endpoint_load_valid_i[hemisphere] &&
					endpoint_load_ready_o[hemisphere] &&
					((destination_target_kind_w[hemisphere*PROGRAM_TARGET_KIND_WIDTH+:
					   PROGRAM_TARGET_KIND_WIDTH] >= PROGRAM_TARGET_MXM_LOAD) &&
					  (destination_target_kind_w[hemisphere*PROGRAM_TARGET_KIND_WIDTH+:
					   PROGRAM_TARGET_KIND_WIDTH] <= PROGRAM_TARGET_MXM_COMPUTE) &&
					  (destination_target_index_w[hemisphere*PROGRAM_TARGET_INDEX_WIDTH+:
					   PROGRAM_TARGET_INDEX_WIDTH] == local_mxm) &&
					  destination_hemisphere_match_w[hemisphere]);
			end

			write_error_w[hemisphere] = write_fire_w[hemisphere] &&
				(!selected_valid_w[hemisphere] ||
				 ((destination_target_kind_w[hemisphere*PROGRAM_TARGET_KIND_WIDTH+:
				   PROGRAM_TARGET_KIND_WIDTH] == PROGRAM_TARGET_MEM) &&
				  ((endpoint_load_strb_i[hemisphere*4+:4] != 4'b0111) ||
				   (endpoint_load_imem_address_i[hemisphere*17+:17] >= MEM_IMEM_DEPTH))) ||
				 (((destination_target_kind_w[hemisphere*PROGRAM_TARGET_KIND_WIDTH+:
				    PROGRAM_TARGET_KIND_WIDTH] >= PROGRAM_TARGET_MXM_LOAD) &&
				   (destination_target_kind_w[hemisphere*PROGRAM_TARGET_KIND_WIDTH+:
				    PROGRAM_TARGET_KIND_WIDTH] <= PROGRAM_TARGET_MXM_COMPUTE)) &&
				  ((endpoint_load_strb_i[hemisphere*4+:4] != 4'b1111) ||
				   (endpoint_load_imem_address_i[hemisphere*17+:17] >= MXM_IMEM_DEPTH))));
			route_error_fire_w[hemisphere] = endpoint_load_valid_i[hemisphere] &&
				endpoint_load_ready_o[hemisphere] &&
				(((endpoint_load_control_i[hemisphere] == PROGRAM_LOAD_PRIME) &&
				  !selected_valid_w[hemisphere]) ||
				 ((endpoint_load_control_i[hemisphere] == PROGRAM_LOAD_PRIME) &&
				  ((endpoint_load_data_i[hemisphere*128+:128] != '0) ||
				   (endpoint_load_strb_i[hemisphere*4+:4] != '0))));
		end
	end

	// One-cycle elastic commit response preserves the Program Loader write contract.
	generate
		for(genvar commit_gen = 0; commit_gen < 2; commit_gen = commit_gen + 1)begin : gen_commit
			always_ff @(posedge clk_i or negedge rst_ni) begin
				if(!rst_ni)begin
					commit_valid_q[commit_gen] <= 1'b0;
					commit_error_q[commit_gen] <= 1'b0;
				end
				else if(program_reset_i)begin
					commit_valid_q[commit_gen] <= 1'b0;
					commit_error_q[commit_gen] <= 1'b0;
				end
				else begin
					if(commit_valid_q[commit_gen] && endpoint_commit_ready_i[commit_gen])begin
						commit_valid_q[commit_gen] <= 1'b0;
					end
					if(write_fire_w[commit_gen])begin
						commit_valid_q[commit_gen] <= 1'b1;
						commit_error_q[commit_gen] <= write_error_w[commit_gen];
					end
				end
			end
		end
	endgenerate

	// Schedule Cycle 0 becomes visible on the accepted START edge.
	always_ff @(posedge clk_i or negedge rst_ni) begin
		if(!rst_ni)begin
			started_q <= 1'b0;
			schedule_cycle_q <= '0;
		end
		else if(program_reset_i)begin
			started_q <= 1'b0;
			schedule_cycle_q <= '0;
		end
		else begin
			if(program_start_i && program_start_ready_o)begin
				started_q <= 1'b1;
			end
			if(started_q)begin
				schedule_cycle_q <= schedule_cycle_q + 1'b1;
			end
		end
	end

	always_ff @(posedge clk_i or negedge rst_ni) begin
		if(!rst_ni)begin
			route_fault_q <= 1'b0;
		end
		else if(program_reset_i)begin
			route_fault_q <= 1'b0;
		end
		else if(!route_fault_q && ((|write_error_w) || (|route_error_fire_w)))begin
			route_fault_q <= 1'b1;
		end
	end

	generate
		for(genvar hemisphere_gen = 0; hemisphere_gen < 2; hemisphere_gen = hemisphere_gen + 1)begin : gen_hemisphere
			localparam integer HEMISPHERE_INDEX = hemisphere_gen;
			logic [4*32-1:0] mem_east_valid;
			logic [4*32*64-1:0] mem_east_data;
			logic [4*32-1:0] mem_west_valid;
			logic [4*32*64-1:0] mem_west_data;
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
			logic mem_stream_conflict;
			logic sxm_stream_conflict;
			logic sxm_fault;
			logic mxm_stream_conflict;
			logic mxm_fault;

			lpu_mem_subsystem #(
				.HEMISPHERE_INDEX(HEMISPHERE_INDEX),
				.IMEM_DEPTH(MEM_IMEM_DEPTH),
				.ACTIVE_CONTEXTS(ACTIVE_CONTEXTS),
				.DEPTH_ROWS(MEM_DEPTH_ROWS),
				.ACTIVE_COLUMNS(ACTIVE_MEM_COLUMNS),
				.USE_SRAM_MACRO(USE_SRAM_MACRO),
				.USE_NATIVE_MEM(USE_NATIVE_MEM)
			) u_mem_subsystem (
				.clk_i, .rst_ni, .program_reset_i, .local_frontend_enable_i,
				.run_i(execution_run), .schedule_cycle_i(schedule_cycle_q),
				.qctl_active_i(qctl_queue_active_o[
					HEMISPHERE_INDEX*lpu_pkg::MEM_BANKS_PER_HEMISPHERE+:lpu_pkg::MEM_BANKS_PER_HEMISPHERE]),
				.qctl_scheduler_enable_i(qctl_scheduler_enable[
					HEMISPHERE_INDEX*lpu_pkg::MEM_BANKS_PER_HEMISPHERE+:lpu_pkg::MEM_BANKS_PER_HEMISPHERE]),
				.qctl_schedule_cycle_i(qctl_queue_cycle[
					HEMISPHERE_INDEX*lpu_pkg::MEM_BANKS_PER_HEMISPHERE*32+:
					lpu_pkg::MEM_BANKS_PER_HEMISPHERE*32]),
				.program_valid_i(mem_program_valid[HEMISPHERE_INDEX]),
				.program_ready_o(mem_program_ready[HEMISPHERE_INDEX]),
				.program_control_i(endpoint_load_control_i[HEMISPHERE_INDEX]),
				.program_destination_i(endpoint_load_destination_i[
					HEMISPHERE_INDEX*PROGRAM_DESTINATION_WIDTH+:PROGRAM_DESTINATION_WIDTH]),
				.program_address_i(endpoint_load_imem_address_i[HEMISPHERE_INDEX*17+:17]),
				.program_data_i(endpoint_load_data_i[HEMISPHERE_INDEX*128+:128]),
				.program_strb_i(endpoint_load_strb_i[HEMISPHERE_INDEX*4+:4]),
				.program_last_i(endpoint_load_last_i[HEMISPHERE_INDEX]),
				.program_error_o(mem_program_error[HEMISPHERE_INDEX]),
				.external_issue_valid_i(external_mem_issue_valid_i[
					HEMISPHERE_INDEX*lpu_pkg::MEM_BANKS_PER_HEMISPHERE+:lpu_pkg::MEM_BANKS_PER_HEMISPHERE]),
				.external_issue_ready_o(external_mem_issue_ready_o[
					HEMISPHERE_INDEX*lpu_pkg::MEM_BANKS_PER_HEMISPHERE+:lpu_pkg::MEM_BANKS_PER_HEMISPHERE]),
				.external_issue_instruction_i(external_mem_issue_instruction_i[
					HEMISPHERE_INDEX*lpu_pkg::MEM_BANKS_PER_HEMISPHERE*lpu_pkg::MEM_INSTRUCTION_WIDTH+:
					lpu_pkg::MEM_BANKS_PER_HEMISPHERE*lpu_pkg::MEM_INSTRUCTION_WIDTH]),
				.local_issue_valid_o(local_mem_issue_valid_o[
					HEMISPHERE_INDEX*lpu_pkg::MEM_BANKS_PER_HEMISPHERE+:lpu_pkg::MEM_BANKS_PER_HEMISPHERE]),
				.local_issue_instruction_o(local_mem_issue_instruction_o[
					HEMISPHERE_INDEX*lpu_pkg::MEM_BANKS_PER_HEMISPHERE*lpu_pkg::MEM_INSTRUCTION_WIDTH+:
					lpu_pkg::MEM_BANKS_PER_HEMISPHERE*lpu_pkg::MEM_INSTRUCTION_WIDTH]),
				.local_issue_cycle_o(local_mem_issue_cycle_o[
					HEMISPHERE_INDEX*lpu_pkg::MEM_BANKS_PER_HEMISPHERE*32+:
					lpu_pkg::MEM_BANKS_PER_HEMISPHERE*32]),
				.frontends_ready_o(mem_frontends_ready[HEMISPHERE_INDEX]),
				.frontends_idle_o(mem_frontends_idle[HEMISPHERE_INDEX]),
				.frontend_fault_o(mem_frontend_fault[HEMISPHERE_INDEX]),
				.frontend_fault_code_o(mem_frontend_fault_code[HEMISPHERE_INDEX*6+:6]),
				.east_edge_valid_i(vxm_to_mem_east_valid[HEMISPHERE_INDEX*4*32+:4*32]),
				.east_edge_data_i(vxm_to_mem_east_data[HEMISPHERE_INDEX*4*32*64+:4*32*64]),
				.east_edge_valid_o(mem_east_valid), .east_edge_data_o(mem_east_data),
				.west_edge_valid_i(sxm_west_valid), .west_edge_data_i(sxm_west_data),
				.west_edge_valid_o(mem_west_valid), .west_edge_data_o(mem_west_data),
				.mem_fault_o(mem_fault_o[
					HEMISPHERE_INDEX*lpu_pkg::MEM_BANKS_PER_HEMISPHERE+:
					lpu_pkg::MEM_BANKS_PER_HEMISPHERE]),
				.conflict_o(mem_stream_conflict)
			);

			lpu_sxm_subsystem u_sxm_subsystem (
				.clk_i, .rst_ni, .run_i(execution_run),
				.transpose_issue_valid_i(external_sxm_transpose_issue_valid_i[HEMISPHERE_INDEX]),
				.transpose_issue_instruction_i(external_sxm_transpose_issue_instruction_i[HEMISPHERE_INDEX*416+:416]),
				.permute_issue_valid_i(external_sxm_permute_issue_valid_i[HEMISPHERE_INDEX]),
				.permute_issue_instruction_i(external_sxm_permute_issue_instruction_i[HEMISPHERE_INDEX*416+:416]),
				.east_inner_valid_i(mem_east_valid), .east_inner_data_i(mem_east_data),
				.east_outer_valid_o(sxm_east_valid), .east_outer_data_o(sxm_east_data),
				.west_outer_valid_i(mxm_west_valid), .west_outer_data_i(mxm_west_data),
				.west_inner_valid_o(sxm_west_valid), .west_inner_data_o(sxm_west_data),
				.fault_o(sxm_fault), .conflict_o(sxm_stream_conflict)
			);
			for(genvar local_mxm_gen = 0; local_mxm_gen < 2; local_mxm_gen = local_mxm_gen + 1)begin : gen_mxm
				localparam integer MXM_INDEX = HEMISPHERE_INDEX*2 + local_mxm_gen;
				lpu_mxm_subsystem #(
					.HEMISPHERE_INDEX(HEMISPHERE_INDEX),
					.LOCAL_MXM_INDEX(local_mxm_gen),
					.IMEM_DEPTH(MXM_IMEM_DEPTH),
					.ACTIVE_CONTEXTS(ACTIVE_CONTEXTS),
					.ACCUMULATOR_BLOCK_COUNT(MXM_ACCUMULATOR_BLOCK_COUNT)
				) u_mxm_subsystem (
					.clk_i, .rst_ni, .program_reset_i, .local_frontend_enable_i,
					.run_i(execution_run), .schedule_cycle_i(schedule_cycle_q),
					.qctl_active_i({
						qctl_queue_active_o[QCTL_MXM_COMPUTE_BASE+MXM_INDEX],
						qctl_queue_active_o[QCTL_MXM_DEQUANT_BASE+MXM_INDEX],
						qctl_queue_active_o[QCTL_MXM_LOAD_BASE+MXM_INDEX]}),
					.qctl_scheduler_enable_i({
						qctl_scheduler_enable[QCTL_MXM_COMPUTE_BASE+MXM_INDEX],
						qctl_scheduler_enable[QCTL_MXM_DEQUANT_BASE+MXM_INDEX],
						qctl_scheduler_enable[QCTL_MXM_LOAD_BASE+MXM_INDEX]}),
					.qctl_schedule_cycle_i({
						qctl_queue_cycle[(QCTL_MXM_COMPUTE_BASE+MXM_INDEX)*32+:32],
						qctl_queue_cycle[(QCTL_MXM_DEQUANT_BASE+MXM_INDEX)*32+:32],
						qctl_queue_cycle[(QCTL_MXM_LOAD_BASE+MXM_INDEX)*32+:32]}),
					.program_valid_i(mxm_program_valid[MXM_INDEX]),
					.program_ready_o(mxm_program_ready[MXM_INDEX]),
					.program_control_i(endpoint_load_control_i[HEMISPHERE_INDEX]),
					.program_destination_i(endpoint_load_destination_i[
						HEMISPHERE_INDEX*PROGRAM_DESTINATION_WIDTH+:PROGRAM_DESTINATION_WIDTH]),
					.program_address_i(endpoint_load_imem_address_i[HEMISPHERE_INDEX*17+:17]),
					.program_data_i(endpoint_load_data_i[HEMISPHERE_INDEX*128+:128]),
					.program_strb_i(endpoint_load_strb_i[HEMISPHERE_INDEX*4+:4]),
					.program_last_i(endpoint_load_last_i[HEMISPHERE_INDEX]),
					.program_error_o(mxm_program_error[MXM_INDEX]),
					.external_load_valid_i(external_mxm_load_issue_valid_i[MXM_INDEX]),
					.external_load_instruction_i(external_mxm_load_issue_instruction_i[MXM_INDEX*48+:48]),
					.external_dequant_valid_i(external_mxm_dequant_issue_valid_i[MXM_INDEX]),
					.external_dequant_instruction_i(external_mxm_dequant_issue_instruction_i[MXM_INDEX*16+:16]),
					.external_compute_valid_i(external_mxm_compute_issue_valid_i[MXM_INDEX]),
					.external_compute_instruction_i(external_mxm_compute_issue_instruction_i[MXM_INDEX*48+:48]),
					.local_load_issue_valid_o(local_mxm_load_issue_valid_o[MXM_INDEX]),
					.local_load_issue_instruction_o(local_mxm_load_issue_instruction_o[MXM_INDEX*29+:29]),
					.local_load_issue_cycle_o(local_mxm_load_issue_cycle_o[MXM_INDEX*32+:32]),
					.local_dequant_issue_valid_o(local_mxm_dequant_issue_valid_o[MXM_INDEX]),
					.local_dequant_issue_instruction_o(local_mxm_dequant_issue_instruction_o[MXM_INDEX*16+:16]),
					.local_dequant_issue_cycle_o(local_mxm_dequant_issue_cycle_o[MXM_INDEX*32+:32]),
					.local_compute_issue_valid_o(local_mxm_compute_issue_valid_o[MXM_INDEX]),
					.local_compute_issue_instruction_o(local_mxm_compute_issue_instruction_o[MXM_INDEX*49+:49]),
					.local_compute_issue_cycle_o(local_mxm_compute_issue_cycle_o[MXM_INDEX*32+:32]),
					.frontends_ready_o(mxm_frontends_ready[MXM_INDEX]),
					.frontends_idle_o(mxm_frontends_idle[MXM_INDEX]),
					.frontend_fault_o(mxm_frontend_fault[MXM_INDEX]),
					.frontend_fault_code_o(mxm_frontend_fault_code[MXM_INDEX*6+:6]),
					.east_from_sxm_valid_i(sxm_east_valid), .east_from_sxm_data_i(sxm_east_data),
					.external_west_valid_i(local_mxm_gen == 0 ?
						mem_west_edge_valid_i[HEMISPHERE_INDEX*4*32+:4*32] : '0),
					.external_west_data_i(mem_west_edge_data_i[HEMISPHERE_INDEX*4*32*64+:4*32*64]),
					.east_external_valid_o(local_mxm_east_valid[local_mxm_gen*4*32+:4*32]),
					.east_external_data_o(local_mxm_east_data[local_mxm_gen*4*32*64+:4*32*64]),
					.west_to_sxm_valid_o(local_mxm_west_valid[local_mxm_gen*4*32+:4*32]),
					.west_to_sxm_data_o(local_mxm_west_data[local_mxm_gen*4*32*64+:4*32*64]),
					.fault_o(local_mxm_fault[local_mxm_gen]),
					.conflict_o(local_mxm_conflict[local_mxm_gen])
				);
			end

			always_comb begin
				mxm_east_valid = local_mxm_east_valid[0+:4*32] & local_mxm_east_valid[4*32+:4*32];
				mxm_east_data = local_mxm_east_data[0+:4*32*64];
				mxm_west_valid = local_mxm_west_valid[0+:4*32];
				mxm_west_data = local_mxm_west_data[0+:4*32*64];
				mxm_stream_conflict = |local_mxm_conflict;
				for(integer stream_cell = 0; stream_cell < 4*32; stream_cell = stream_cell + 1)begin
					if(local_mxm_west_valid[4*32+stream_cell])begin
						if(mxm_west_valid[stream_cell])begin
							mxm_stream_conflict = 1'b1;
						end
						else begin
							mxm_west_valid[stream_cell] = 1'b1;
							mxm_west_data[stream_cell*64+:64] =
								local_mxm_west_data[(4*32+stream_cell)*64+:64];
						end
					end
				end
				mxm_fault = |local_mxm_fault;
			end

			assign mem_east_edge_valid_o[HEMISPHERE_INDEX*4*32+:4*32] = mxm_east_valid;
			assign mem_east_edge_data_o[HEMISPHERE_INDEX*4*32*64+:4*32*64] = mxm_east_data;
			assign mem_west_edge_valid_o[HEMISPHERE_INDEX*4*32+:4*32] = mem_west_valid;
			assign mem_west_edge_data_o[HEMISPHERE_INDEX*4*32*64+:4*32*64] = mem_west_data;
			assign mem_to_vxm_west_valid[HEMISPHERE_INDEX*4*32+:4*32] = mem_west_valid;
			assign mem_to_vxm_west_data[HEMISPHERE_INDEX*4*32*64+:4*32*64] = mem_west_data;
			assign sxm_fault_o[HEMISPHERE_INDEX] = sxm_fault;
			assign mxm_fault_o[HEMISPHERE_INDEX] = mxm_fault;
			assign stream_conflict_o[HEMISPHERE_INDEX] = mem_stream_conflict |
				sxm_stream_conflict | mxm_stream_conflict | vxm_stream_conflict;
		end
	endgenerate

	lpu_vxm_subsystem u_vxm_subsystem (
		.clk_i, .rst_ni, .run_i(execution_run),
		.local_issue_valid_i(external_vxm_local_issue_valid_i),
		.local_issue_instruction_i(external_vxm_local_issue_instruction_i),
		.global_issue_valid_i(external_vxm_global_issue_valid_i),
		.global_issue_instruction_i(external_vxm_global_issue_instruction_i),
		.west_from_mem_valid_i(mem_to_vxm_west_valid),
		.west_from_mem_data_i(mem_to_vxm_west_data),
		.external_east_valid_i(mem_east_edge_valid_i),
		.external_east_data_i(mem_east_edge_data_i),
		.east_to_mem_valid_o(vxm_to_mem_east_valid),
		.east_to_mem_data_o(vxm_to_mem_east_data),
		.fault_o(vxm_fault_o),
		.conflict_o(vxm_stream_conflict)
	);
endmodule
