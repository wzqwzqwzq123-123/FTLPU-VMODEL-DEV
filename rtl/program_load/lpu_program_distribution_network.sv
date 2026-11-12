// Program Distribution Network owns both physical seven-Relay chains, endpoint
// routing, arbitration and one-cycle WRITE commit responses. It deliberately
// adds no pipeline stage beyond the existing Relay buffers.
module lpu_program_distribution_network (
	input logic clk_i,
	input logic rst_ni,
	input logic program_reset_i,

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

	output logic [1:0] mem_program_valid_o,
	input logic [1:0] mem_program_ready_i,
	output logic [2*lpu_program_load_pkg::PROGRAM_LOAD_CONTROL_WIDTH-1:0] mem_program_control_o,
	output logic [23:0] mem_program_destination_o,
	output logic [33:0] mem_program_address_o,
	output logic [255:0] mem_program_data_o,
	output logic [7:0] mem_program_strb_o,
	output logic [1:0] mem_program_last_o,
	input logic [1:0] mem_program_error_i,

	output logic [3:0] mxm_program_valid_o,
	input logic [3:0] mxm_program_ready_i,
	input logic [3:0] mxm_program_error_i,
	output logic [1:0] sxm_program_valid_o,
	input logic [1:0] sxm_program_ready_i,
	input logic [1:0] sxm_program_error_i,
	output logic [2*lpu_program_load_pkg::PROGRAM_LOAD_CONTROL_WIDTH-1:0] outer_program_control_o,
	output logic [23:0] outer_program_destination_o,
	output logic [33:0] outer_program_address_o,
	output logic [255:0] outer_program_data_o,
	output logic [7:0] outer_program_strb_o,
	output logic [1:0] outer_program_last_o,

	output logic vxm_program_valid_o,
	input logic vxm_program_ready_i,
	input logic vxm_program_error_i,
	output logic [lpu_program_load_pkg::PROGRAM_LOAD_CONTROL_WIDTH-1:0] vxm_program_control_o,
	output logic [lpu_program_load_pkg::PROGRAM_DESTINATION_WIDTH-1:0] vxm_program_destination_o,
	output logic [16:0] vxm_program_address_o,
	output logic [127:0] vxm_program_data_o,
	output logic [3:0] vxm_program_strb_o,
	output logic vxm_program_last_o,

	output logic idle_o,
	output logic fault_o,
	output logic [5:0] fault_code_o
);
	import lpu_program_load_pkg::*;

	localparam logic [5:0] FAULT_NONE = 6'd0;
	localparam logic [5:0] FAULT_ROUTE = 6'd1;
	localparam integer PROGRAM_RELAY_GROUP_SLICES = 4;
	localparam integer PROGRAM_RELAY_GROUPS_PER_STAGE = 2;
	localparam integer PROGRAM_RELAY_BANKS_PER_STAGE =
		PROGRAM_RELAY_GROUP_SLICES * lpu_pkg::MEM_BANKS_PER_SLICE *
		PROGRAM_RELAY_GROUPS_PER_STAGE;
	localparam integer PROGRAM_RELAY_COUNT =
		((lpu_pkg::MEM_SLICES_PER_HEMISPHERE + PROGRAM_RELAY_GROUP_SLICES - 1) /
		 PROGRAM_RELAY_GROUP_SLICES + PROGRAM_RELAY_GROUPS_PER_STAGE - 1) /
		PROGRAM_RELAY_GROUPS_PER_STAGE;
	localparam integer PROGRAM_RELAY_SOURCE_COUNT = PROGRAM_RELAY_COUNT + 1;
	localparam integer PROGRAM_RELAY_SOURCE_WIDTH = $clog2(PROGRAM_RELAY_SOURCE_COUNT);

	logic program_transport_rst_ni;
	logic route_fault_q;
	logic [1:0] selected_ready_w;
	logic [1:0] selected_valid_w;
	logic [1:0] destination_hemisphere_match_w;
	logic [5:0] destination_target_kind_w;
	logic [15:0] destination_target_index_w;
	logic [1:0] write_fire_w;
	logic [1:0] write_error_w;
	logic [1:0] route_error_fire_w;
	logic [1:0] completion_slot_ready_w;
	logic [1:0] commit_valid_q;
	logic [1:0] commit_error_q;

	logic [1:0] mem_program_valid;
	logic [1:0] mem_program_ready;
	logic [1:0] mem_program_error;
	logic [2*PROGRAM_LOAD_CONTROL_WIDTH-1:0] mem_program_control;
	logic [23:0] mem_program_destination;
	logic [33:0] mem_program_address;
	logic [255:0] mem_program_data;
	logic [7:0] mem_program_strb;
	logic [1:0] mem_program_last;
	logic [3:0] mxm_program_valid;
	logic [3:0] mxm_program_ready;
	logic [3:0] mxm_program_error;
	logic [2*PROGRAM_LOAD_CONTROL_WIDTH-1:0] outer_program_control;
	logic [23:0] outer_program_destination;
	logic [33:0] outer_program_address;
	logic [255:0] outer_program_data;
	logic [7:0] outer_program_strb;
	logic [1:0] outer_program_last;
	logic [1:0] sxm_program_valid;
	logic [1:0] sxm_program_ready;
	logic [1:0] sxm_program_error;
	logic vxm_program_valid;
	logic vxm_program_ready;
	logic vxm_program_error;
	logic [PROGRAM_LOAD_CONTROL_WIDTH-1:0] vxm_program_control;
	logic [PROGRAM_DESTINATION_WIDTH-1:0] vxm_program_destination;
	logic [16:0] vxm_program_address;
	logic [127:0] vxm_program_data;
	logic [3:0] vxm_program_strb;
	logic vxm_program_last;

	logic [1:0] relay_chain_input_valid;
	logic [1:0] relay_chain_input_ready;
	logic [2*lpu_pkg::MEM_BANKS_PER_HEMISPHERE-1:0] relay_mem_valid;
	logic [2*lpu_pkg::MEM_BANKS_PER_HEMISPHERE-1:0] relay_mem_ready;
	logic [2*PROGRAM_RELAY_COUNT*PROGRAM_LOAD_CONTROL_WIDTH-1:0] relay_mem_control;
	logic [2*PROGRAM_RELAY_COUNT*128-1:0] relay_mem_data;
	logic [2*PROGRAM_RELAY_COUNT*4-1:0] relay_mem_strb;
	logic [2*PROGRAM_RELAY_COUNT*2-1:0] relay_mem_scope;
	logic [2*PROGRAM_RELAY_COUNT*12-1:0] relay_mem_destination;
	logic [2*PROGRAM_RELAY_COUNT*17-1:0] relay_mem_address;
	logic [2*PROGRAM_RELAY_COUNT-1:0] relay_mem_last;
	logic [1:0] relay_outer_valid;
	logic [1:0] relay_outer_ready;
	logic [2*PROGRAM_LOAD_CONTROL_WIDTH-1:0] relay_outer_control;
	logic [255:0] relay_outer_data;
	logic [7:0] relay_outer_strb;
	logic [3:0] relay_outer_scope;
	logic [23:0] relay_outer_destination;
	logic [33:0] relay_outer_address;
	logic [1:0] relay_outer_last;
	logic [1:0] relay_chain_idle;
	logic [1:0] relay_chain_fault;
	logic [11:0] relay_chain_fault_code;
	logic [2*PROGRAM_RELAY_SOURCE_COUNT-1:0] relay_source_valid_w;
	logic [1:0] relay_source_selected_w;
	logic [2*PROGRAM_RELAY_SOURCE_WIDTH-1:0] relay_source_index_w;
	logic [2*PROGRAM_RELAY_SOURCE_WIDTH-1:0] relay_round_robin_q;
	logic [1:0] relay_source_fire_w;

	assign program_transport_rst_ni = rst_ni && !program_reset_i;
	assign endpoint_commit_valid_o = commit_valid_q;
	assign endpoint_commit_error_o = commit_error_q;
	assign mem_program_ready = mem_program_ready_i;
	assign mem_program_error = mem_program_error_i;
	assign mxm_program_ready = mxm_program_ready_i;
	assign mxm_program_error = mxm_program_error_i;
	assign sxm_program_ready = sxm_program_ready_i;
	assign sxm_program_error = sxm_program_error_i;
	assign vxm_program_ready = vxm_program_ready_i;
	assign vxm_program_error = vxm_program_error_i;

	assign mem_program_valid_o = mem_program_valid;
	assign mem_program_control_o = mem_program_control;
	assign mem_program_destination_o = mem_program_destination;
	assign mem_program_address_o = mem_program_address;
	assign mem_program_data_o = mem_program_data;
	assign mem_program_strb_o = mem_program_strb;
	assign mem_program_last_o = mem_program_last;
	assign mxm_program_valid_o = mxm_program_valid;
	assign sxm_program_valid_o = sxm_program_valid;
	assign outer_program_control_o = outer_program_control;
	assign outer_program_destination_o = outer_program_destination;
	assign outer_program_address_o = outer_program_address;
	assign outer_program_data_o = outer_program_data;
	assign outer_program_strb_o = outer_program_strb;
	assign outer_program_last_o = outer_program_last;
	assign vxm_program_valid_o = vxm_program_valid;
	assign vxm_program_control_o = vxm_program_control;
	assign vxm_program_destination_o = vxm_program_destination;
	assign vxm_program_address_o = vxm_program_address;
	assign vxm_program_data_o = vxm_program_data;
	assign vxm_program_strb_o = vxm_program_strb;
	assign vxm_program_last_o = vxm_program_last;
	assign idle_o = &relay_chain_idle;
	assign fault_o = route_fault_q || (|relay_chain_fault);
	assign fault_code_o = fault_o ? FAULT_ROUTE : FAULT_NONE;
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

	// One physical chain is placed beside each Hemisphere. VXM requests are
	// filtered before this boundary and therefore never enter either chain.
	generate
		for(genvar chain_gen = 0; chain_gen < 2; chain_gen = chain_gen + 1)begin : gen_program_relay_chain
			lpu_program_load_relay_chain #(
				.HEMISPHERE_ID(chain_gen),
				.MEM_SLICES_PER_HEMISPHERE(lpu_pkg::MEM_SLICES_PER_HEMISPHERE),
				.MEM_SLICES_PER_GROUP(PROGRAM_RELAY_GROUP_SLICES),
				.BANKS_PER_SLICE(lpu_pkg::MEM_BANKS_PER_SLICE),
				.MEM_GROUPS_PER_RELAY(PROGRAM_RELAY_GROUPS_PER_STAGE),
				.MXM_INSTANCES_PER_HEMISPHERE(2),
				.SXM_INSTANCES_PER_HEMISPHERE(1)
			) u_program_relay_chain (
				.clk_i,
				.rst_ni(program_transport_rst_ni),
				.input_valid_i(relay_chain_input_valid[chain_gen]),
				.input_ready_o(relay_chain_input_ready[chain_gen]),
				.input_control_i(endpoint_load_control_i[
					chain_gen*PROGRAM_LOAD_CONTROL_WIDTH+:PROGRAM_LOAD_CONTROL_WIDTH]),
				.input_data_i(endpoint_load_data_i[chain_gen*128+:128]),
				.input_strb_i(endpoint_load_strb_i[chain_gen*4+:4]),
				.input_scope_i(chain_gen == 0 ? PROGRAM_SCOPE_EAST : PROGRAM_SCOPE_WEST),
				.input_destination_i(endpoint_load_destination_i[chain_gen*12+:12]),
				.input_imem_address_i(endpoint_load_imem_address_i[chain_gen*17+:17]),
				.input_last_i(endpoint_load_last_i[chain_gen]),
				.mem_local_valid_o(relay_mem_valid[
					chain_gen*lpu_pkg::MEM_BANKS_PER_HEMISPHERE+:
					lpu_pkg::MEM_BANKS_PER_HEMISPHERE]),
				.mem_local_ready_i(relay_mem_ready[
					chain_gen*lpu_pkg::MEM_BANKS_PER_HEMISPHERE+:
					lpu_pkg::MEM_BANKS_PER_HEMISPHERE]),
				.mem_local_control_o(relay_mem_control[
					chain_gen*PROGRAM_RELAY_COUNT*PROGRAM_LOAD_CONTROL_WIDTH+:
					PROGRAM_RELAY_COUNT*PROGRAM_LOAD_CONTROL_WIDTH]),
				.mem_local_data_o(relay_mem_data[
					chain_gen*PROGRAM_RELAY_COUNT*128+:PROGRAM_RELAY_COUNT*128]),
				.mem_local_strb_o(relay_mem_strb[
					chain_gen*PROGRAM_RELAY_COUNT*4+:PROGRAM_RELAY_COUNT*4]),
				.mem_local_scope_o(relay_mem_scope[
					chain_gen*PROGRAM_RELAY_COUNT*2+:PROGRAM_RELAY_COUNT*2]),
				.mem_local_destination_o(relay_mem_destination[
					chain_gen*PROGRAM_RELAY_COUNT*12+:PROGRAM_RELAY_COUNT*12]),
				.mem_local_imem_address_o(relay_mem_address[
					chain_gen*PROGRAM_RELAY_COUNT*17+:PROGRAM_RELAY_COUNT*17]),
				.mem_local_last_o(relay_mem_last[
					chain_gen*PROGRAM_RELAY_COUNT+:PROGRAM_RELAY_COUNT]),
				.outer_local_valid_o(relay_outer_valid[chain_gen]),
				.outer_local_ready_i(relay_outer_ready[chain_gen]),
				.outer_local_control_o(relay_outer_control[
					chain_gen*PROGRAM_LOAD_CONTROL_WIDTH+:PROGRAM_LOAD_CONTROL_WIDTH]),
				.outer_local_data_o(relay_outer_data[chain_gen*128+:128]),
				.outer_local_strb_o(relay_outer_strb[chain_gen*4+:4]),
				.outer_local_scope_o(relay_outer_scope[chain_gen*2+:2]),
				.outer_local_destination_o(relay_outer_destination[chain_gen*12+:12]),
				.outer_local_imem_address_o(relay_outer_address[chain_gen*17+:17]),
				.outer_local_last_o(relay_outer_last[chain_gen]),
				.relay_level_o(),
				.idle_o(relay_chain_idle[chain_gen]),
				.fault_o(relay_chain_fault[chain_gen]),
				.fault_code_o(relay_chain_fault_code[chain_gen*6+:6])
			);
		end
	endgenerate

	// The chains can hold Local requests at different physical stages. A small
	// round-robin selector preserves the existing single Program port on each FU
	// Subsystem while guaranteeing that no Relay stage can starve indefinitely.
	always_comb begin
		endpoint_load_ready_o = '0;
		selected_ready_w = '0;
		selected_valid_w = '0;
		write_fire_w = '0;
		write_error_w = '0;
		route_error_fire_w = '0;
		completion_slot_ready_w = '0;
		relay_chain_input_valid = '0;
		relay_mem_ready = '0;
		relay_outer_ready = '0;
		relay_source_valid_w = '0;
		relay_source_selected_w = '0;
		relay_source_index_w = '0;
		relay_source_fire_w = '0;
		mem_program_valid = '0;
		mem_program_control = '0;
		mem_program_destination = '0;
		mem_program_address = '0;
		mem_program_data = '0;
		mem_program_strb = '0;
		mem_program_last = '0;
		mxm_program_valid = '0;
		sxm_program_valid = '0;
		vxm_program_valid = 1'b0;
		vxm_program_control = '0;
		vxm_program_destination = '0;
		vxm_program_address = '0;
		vxm_program_data = '0;
		vxm_program_strb = '0;
		vxm_program_last = 1'b0;
		outer_program_control = '0;
		outer_program_destination = '0;
		outer_program_address = '0;
		outer_program_data = '0;
		outer_program_strb = '0;
		outer_program_last = '0;

		for(integer hemisphere = 0; hemisphere < 2; hemisphere = hemisphere + 1)begin
			integer selected_source;
			integer candidate_source;
			integer selected_bank;
			logic [2:0] endpoint_kind;
			logic [7:0] endpoint_index;
			logic [2:0] selected_outer_kind;
			logic [7:0] selected_outer_index;
			logic selected_control;
			logic selected_can_complete;

			completion_slot_ready_w[hemisphere] = !commit_valid_q[hemisphere] ||
				endpoint_commit_ready_i[hemisphere];

			for(integer local_bank = 0;
				local_bank < lpu_pkg::MEM_BANKS_PER_HEMISPHERE;
				local_bank = local_bank + 1)begin
				relay_source_valid_w[hemisphere*PROGRAM_RELAY_SOURCE_COUNT+
					(local_bank / PROGRAM_RELAY_BANKS_PER_STAGE)] |=
					relay_mem_valid[hemisphere*lpu_pkg::MEM_BANKS_PER_HEMISPHERE+local_bank];
			end
			relay_source_valid_w[hemisphere*PROGRAM_RELAY_SOURCE_COUNT+
				PROGRAM_RELAY_COUNT] = relay_outer_valid[hemisphere];

			selected_source = 0;
			for(integer source_offset = 0; source_offset < PROGRAM_RELAY_SOURCE_COUNT;
				source_offset = source_offset + 1)begin
				candidate_source = relay_round_robin_q[
					hemisphere*PROGRAM_RELAY_SOURCE_WIDTH+:PROGRAM_RELAY_SOURCE_WIDTH] +
					source_offset;
				if(candidate_source >= PROGRAM_RELAY_SOURCE_COUNT)begin
					candidate_source = candidate_source - PROGRAM_RELAY_SOURCE_COUNT;
				end
				if(!relay_source_selected_w[hemisphere] && relay_source_valid_w[
					hemisphere*PROGRAM_RELAY_SOURCE_COUNT+candidate_source])begin
					relay_source_selected_w[hemisphere] = 1'b1;
					selected_source = candidate_source;
					relay_source_index_w[hemisphere*PROGRAM_RELAY_SOURCE_WIDTH+:
						PROGRAM_RELAY_SOURCE_WIDTH] = candidate_source[PROGRAM_RELAY_SOURCE_WIDTH-1:0];
				end
			end

			endpoint_kind = destination_target_kind_w[
				hemisphere*PROGRAM_TARGET_KIND_WIDTH+:PROGRAM_TARGET_KIND_WIDTH];
			endpoint_index = destination_target_index_w[
				hemisphere*PROGRAM_TARGET_INDEX_WIDTH+:PROGRAM_TARGET_INDEX_WIDTH];
			case(endpoint_kind)
				PROGRAM_TARGET_MEM: selected_valid_w[hemisphere] =
					destination_hemisphere_match_w[hemisphere] &&
					(endpoint_index < lpu_pkg::MEM_BANKS_PER_HEMISPHERE);
				PROGRAM_TARGET_MXM_LOAD,
				PROGRAM_TARGET_MXM_DEQUANT,
				PROGRAM_TARGET_MXM_COMPUTE: selected_valid_w[hemisphere] =
					destination_hemisphere_match_w[hemisphere] && (endpoint_index < 2);
				PROGRAM_TARGET_SXM_TRANSPOSE,
				PROGRAM_TARGET_SXM_PERMUTE: selected_valid_w[hemisphere] =
					destination_hemisphere_match_w[hemisphere] && (endpoint_index == 0);
				PROGRAM_TARGET_VXM: selected_valid_w[hemisphere] =
					(hemisphere == 0) && destination_hemisphere_match_w[hemisphere] &&
					(endpoint_index <= 8);
				default: selected_valid_w[hemisphere] = 1'b0;
			endcase

			if(!selected_valid_w[hemisphere])begin
				selected_ready_w[hemisphere] =
					(endpoint_load_control_i[hemisphere] != PROGRAM_LOAD_WRITE) ||
					completion_slot_ready_w[hemisphere];
			end
			else if(endpoint_kind == PROGRAM_TARGET_VXM)begin
				// The shared VXM bypasses both Relay chains. The Subsystem boundary
				// currently holds Ready low until its resident-config adapter exists.
				selected_can_complete =
					(endpoint_load_control_i[hemisphere] != PROGRAM_LOAD_WRITE) ||
					completion_slot_ready_w[hemisphere];
				vxm_program_valid = endpoint_load_valid_i[hemisphere] && selected_can_complete;
				vxm_program_control = endpoint_load_control_i[
					hemisphere*PROGRAM_LOAD_CONTROL_WIDTH+:PROGRAM_LOAD_CONTROL_WIDTH];
				vxm_program_destination = endpoint_load_destination_i[hemisphere*12+:12];
				vxm_program_address = endpoint_load_imem_address_i[hemisphere*17+:17];
				vxm_program_data = endpoint_load_data_i[hemisphere*128+:128];
				vxm_program_strb = endpoint_load_strb_i[hemisphere*4+:4];
				vxm_program_last = endpoint_load_last_i[hemisphere];
				selected_ready_w[hemisphere] = vxm_program_ready && selected_can_complete;
				if(vxm_program_valid && vxm_program_ready &&
					(endpoint_load_control_i[hemisphere] == PROGRAM_LOAD_WRITE))begin
					write_fire_w[hemisphere] = 1'b1;
					write_error_w[hemisphere] = vxm_program_error;
				end
			end
			else begin
				// SXM requests enter the physical Relay chain and remain stalled at
				// R6 until the Subsystem exposes a real local-iMEM receiver.
				selected_ready_w[hemisphere] = relay_chain_input_ready[hemisphere];
				relay_chain_input_valid[hemisphere] = endpoint_load_valid_i[hemisphere];
			end
			endpoint_load_ready_o[hemisphere] = selected_ready_w[hemisphere];

			if(endpoint_load_valid_i[hemisphere] && endpoint_load_ready_o[hemisphere] &&
				!selected_valid_w[hemisphere])begin
				if(endpoint_load_control_i[hemisphere] == PROGRAM_LOAD_WRITE)begin
					write_fire_w[hemisphere] = 1'b1;
					write_error_w[hemisphere] = 1'b1;
				end
				else begin
					route_error_fire_w[hemisphere] = 1'b1;
				end
			end
			if(endpoint_load_valid_i[hemisphere] && endpoint_load_ready_o[hemisphere] &&
				(endpoint_load_control_i[hemisphere] == PROGRAM_LOAD_PRIME) &&
				((endpoint_load_data_i[hemisphere*128+:128] != '0) ||
				 (endpoint_load_strb_i[hemisphere*4+:4] != '0)))begin
				route_error_fire_w[hemisphere] = 1'b1;
			end

			if(relay_source_selected_w[hemisphere] &&
				(selected_source < PROGRAM_RELAY_COUNT))begin
				selected_control = relay_mem_control[
					(hemisphere*PROGRAM_RELAY_COUNT+selected_source)*PROGRAM_LOAD_CONTROL_WIDTH+:
					PROGRAM_LOAD_CONTROL_WIDTH];
				selected_can_complete = (selected_control != PROGRAM_LOAD_WRITE) ||
					completion_slot_ready_w[hemisphere];
				mem_program_control[hemisphere*PROGRAM_LOAD_CONTROL_WIDTH+:
					PROGRAM_LOAD_CONTROL_WIDTH] = selected_control;
				mem_program_destination[hemisphere*12+:12] = relay_mem_destination[
					(hemisphere*PROGRAM_RELAY_COUNT+selected_source)*12+:12];
				mem_program_address[hemisphere*17+:17] = relay_mem_address[
					(hemisphere*PROGRAM_RELAY_COUNT+selected_source)*17+:17];
				mem_program_data[hemisphere*128+:128] = relay_mem_data[
					(hemisphere*PROGRAM_RELAY_COUNT+selected_source)*128+:128];
				mem_program_strb[hemisphere*4+:4] = relay_mem_strb[
					(hemisphere*PROGRAM_RELAY_COUNT+selected_source)*4+:4];
				mem_program_last[hemisphere] = relay_mem_last[
					hemisphere*PROGRAM_RELAY_COUNT+selected_source];
				selected_bank = mem_program_destination[hemisphere*12+
					PROGRAM_DESTINATION_INDEX_LSB+:PROGRAM_TARGET_INDEX_WIDTH];
				mem_program_valid[hemisphere] = selected_can_complete;
				relay_mem_ready[hemisphere*lpu_pkg::MEM_BANKS_PER_HEMISPHERE+
					selected_bank] = mem_program_ready[hemisphere] && selected_can_complete;
				relay_source_fire_w[hemisphere] = mem_program_valid[hemisphere] &&
					mem_program_ready[hemisphere];
				if(relay_source_fire_w[hemisphere] &&
					(selected_control == PROGRAM_LOAD_WRITE))begin
					write_fire_w[hemisphere] = 1'b1;
					write_error_w[hemisphere] = mem_program_error[hemisphere];
				end
			end
			else if(relay_source_selected_w[hemisphere])begin
				selected_outer_kind = relay_outer_destination[
					hemisphere*12+PROGRAM_DESTINATION_KIND_LSB+:PROGRAM_TARGET_KIND_WIDTH];
				selected_outer_index = relay_outer_destination[
					hemisphere*12+PROGRAM_DESTINATION_INDEX_LSB+:PROGRAM_TARGET_INDEX_WIDTH];
				selected_control = relay_outer_control[
					hemisphere*PROGRAM_LOAD_CONTROL_WIDTH+:PROGRAM_LOAD_CONTROL_WIDTH];
				selected_can_complete = (selected_control != PROGRAM_LOAD_WRITE) ||
					completion_slot_ready_w[hemisphere];
				outer_program_control[hemisphere*PROGRAM_LOAD_CONTROL_WIDTH+:
					PROGRAM_LOAD_CONTROL_WIDTH] = selected_control;
				outer_program_destination[hemisphere*12+:12] =
					relay_outer_destination[hemisphere*12+:12];
				outer_program_address[hemisphere*17+:17] =
					relay_outer_address[hemisphere*17+:17];
				outer_program_data[hemisphere*128+:128] =
					relay_outer_data[hemisphere*128+:128];
				outer_program_strb[hemisphere*4+:4] = relay_outer_strb[hemisphere*4+:4];
				outer_program_last[hemisphere] = relay_outer_last[hemisphere];

				if((selected_outer_kind >= PROGRAM_TARGET_MXM_LOAD) &&
					(selected_outer_kind <= PROGRAM_TARGET_MXM_COMPUTE) &&
					(selected_outer_index < 2))begin
					mxm_program_valid[hemisphere*2+selected_outer_index] =
						relay_outer_valid[hemisphere] && selected_can_complete;
					relay_outer_ready[hemisphere] =
						mxm_program_ready[hemisphere*2+selected_outer_index] &&
						selected_can_complete;
					relay_source_fire_w[hemisphere] = relay_outer_valid[hemisphere] &&
						relay_outer_ready[hemisphere];
					if(relay_source_fire_w[hemisphere] &&
						(selected_control == PROGRAM_LOAD_WRITE))begin
						write_fire_w[hemisphere] = 1'b1;
						write_error_w[hemisphere] =
							mxm_program_error[hemisphere*2+selected_outer_index];
					end
				end
				else if(((selected_outer_kind == PROGRAM_TARGET_SXM_TRANSPOSE) ||
					(selected_outer_kind == PROGRAM_TARGET_SXM_PERMUTE)) &&
					(selected_outer_index == 0))begin
					sxm_program_valid[hemisphere] = relay_outer_valid[hemisphere] &&
						selected_can_complete;
					relay_outer_ready[hemisphere] = sxm_program_ready[hemisphere] &&
						selected_can_complete;
					relay_source_fire_w[hemisphere] = relay_outer_valid[hemisphere] &&
						relay_outer_ready[hemisphere];
					if(relay_source_fire_w[hemisphere] &&
						(selected_control == PROGRAM_LOAD_WRITE))begin
						write_fire_w[hemisphere] = 1'b1;
						write_error_w[hemisphere] = sxm_program_error[hemisphere];
					end
				end
			end
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

	// Advance only when the selected FU endpoint accepts the Record. This keeps
	// all stalled Relay heads stable and prevents a busy near stage from starving R6.
	generate
		for(genvar relay_rr_gen = 0; relay_rr_gen < 2; relay_rr_gen = relay_rr_gen + 1)begin : gen_relay_round_robin
			always_ff @(posedge clk_i or negedge rst_ni) begin
				if(!rst_ni)begin
					relay_round_robin_q[relay_rr_gen*PROGRAM_RELAY_SOURCE_WIDTH+:
						PROGRAM_RELAY_SOURCE_WIDTH] <= '0;
				end
				else if(program_reset_i)begin
					relay_round_robin_q[relay_rr_gen*PROGRAM_RELAY_SOURCE_WIDTH+:
						PROGRAM_RELAY_SOURCE_WIDTH] <= '0;
				end
				else if(relay_source_fire_w[relay_rr_gen])begin
					if(relay_source_index_w[relay_rr_gen*PROGRAM_RELAY_SOURCE_WIDTH+:
						PROGRAM_RELAY_SOURCE_WIDTH] == PROGRAM_RELAY_SOURCE_COUNT - 1)begin
						relay_round_robin_q[relay_rr_gen*PROGRAM_RELAY_SOURCE_WIDTH+:
							PROGRAM_RELAY_SOURCE_WIDTH] <= '0;
					end
					else begin
						relay_round_robin_q[relay_rr_gen*PROGRAM_RELAY_SOURCE_WIDTH+:
							PROGRAM_RELAY_SOURCE_WIDTH] <=
							relay_source_index_w[relay_rr_gen*PROGRAM_RELAY_SOURCE_WIDTH+:
							PROGRAM_RELAY_SOURCE_WIDTH] + 1'b1;
					end
				end
			end
		end
	endgenerate

	always_ff @(posedge clk_i or negedge rst_ni) begin
		if(!rst_ni)begin
			route_fault_q <= 1'b0;
		end
		else if(program_reset_i)begin
			route_fault_q <= 1'b0;
		end
		else if(!route_fault_q && ((|write_error_w) || (|route_error_fire_w) ||
			(|relay_chain_fault)))begin
			route_fault_q <= 1'b1;
		end
	end

endmodule
