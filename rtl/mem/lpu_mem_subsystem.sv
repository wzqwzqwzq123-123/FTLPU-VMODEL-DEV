module lpu_mem_subsystem #(
	parameter integer HEMISPHERE_INDEX = lpu_program_load_pkg::PROGRAM_HEMISPHERE_EAST,
	parameter integer IMEM_DEPTH = 131072,
	parameter integer ACTIVE_CONTEXTS = 4,
	parameter integer FU_QUEUE_DEPTH = 16,
	parameter integer PROGRAM_PORT_COUNT = lpu_program_load_pkg::PROGRAM_RELAY_COUNT,
	parameter integer PROGRAM_BANKS_PER_PORT = lpu_program_load_pkg::PROGRAM_RELAY_BANKS_PER_STAGE,
	parameter integer DEPTH_ROWS = lpu_pkg::SRAM_DEPTH_ROWS,
	parameter integer ACTIVE_COLUMNS = 52,
	parameter bit USE_SRAM_MACRO = 1'b0,
	parameter bit USE_NATIVE_MEM = 1'b1
) (
	input logic clk_i,
	input logic rst_ni,
	input logic program_reset_i,
	input logic local_frontend_enable_i,
	input logic run_i,
	input logic [31:0] schedule_cycle_i,
	input logic [lpu_pkg::MEM_BANKS_PER_HEMISPHERE-1:0] qctl_active_i,
	input logic [lpu_pkg::MEM_BANKS_PER_HEMISPHERE-1:0] qctl_scheduler_enable_i,
	input logic [lpu_pkg::MEM_BANKS_PER_HEMISPHERE*32-1:0] qctl_schedule_cycle_i,

	input logic [PROGRAM_PORT_COUNT-1:0] program_valid_i,
	output logic [PROGRAM_PORT_COUNT-1:0] program_ready_o,
	input logic [PROGRAM_PORT_COUNT*lpu_program_load_pkg::PROGRAM_LOAD_CONTROL_WIDTH-1:0]
		program_control_i,
	input logic [PROGRAM_PORT_COUNT*lpu_program_load_pkg::PROGRAM_DESTINATION_WIDTH-1:0]
		program_destination_i,
	input logic [PROGRAM_PORT_COUNT*17-1:0] program_address_i,
	input logic [PROGRAM_PORT_COUNT*128-1:0] program_data_i,
	input logic [PROGRAM_PORT_COUNT*4-1:0] program_strb_i,
	input logic [PROGRAM_PORT_COUNT-1:0] program_last_i,
	output logic [PROGRAM_PORT_COUNT-1:0] program_error_o,

	input logic [lpu_pkg::MEM_BANKS_PER_HEMISPHERE-1:0] external_issue_valid_i,
	output logic [lpu_pkg::MEM_BANKS_PER_HEMISPHERE-1:0] external_issue_ready_o,
	input logic [lpu_pkg::MEM_BANKS_PER_HEMISPHERE*lpu_pkg::MEM_INSTRUCTION_WIDTH-1:0] external_issue_instruction_i,
	output logic [lpu_pkg::MEM_BANKS_PER_HEMISPHERE-1:0] local_issue_valid_o,
	output logic [lpu_pkg::MEM_BANKS_PER_HEMISPHERE*lpu_pkg::MEM_INSTRUCTION_WIDTH-1:0] local_issue_instruction_o,
	output logic [lpu_pkg::MEM_BANKS_PER_HEMISPHERE*32-1:0] local_issue_cycle_o,

	output logic frontends_ready_o,
	output logic frontends_idle_o,
	output logic frontend_fault_o,
	output logic [5:0] frontend_fault_code_o,

	input logic [4*32-1:0] east_edge_valid_i,
	input logic [4*32*64-1:0] east_edge_data_i,
	output logic [4*32-1:0] east_edge_valid_o,
	output logic [4*32*64-1:0] east_edge_data_o,
	input logic [4*32-1:0] west_edge_valid_i,
	input logic [4*32*64-1:0] west_edge_data_i,
	output logic [4*32-1:0] west_edge_valid_o,
	output logic [4*32*64-1:0] west_edge_data_o,

	output logic [lpu_pkg::MEM_BANKS_PER_HEMISPHERE-1:0] mem_fault_o,
	output logic conflict_o
);
	import lpu_program_load_pkg::*;
	localparam integer QUEUE_COUNT = lpu_pkg::MEM_BANKS_PER_HEMISPHERE;

	logic [PROGRAM_PORT_COUNT-1:0] write_fire_w;
	logic [PROGRAM_PORT_COUNT-1:0] prime_fire_w;
	logic [PROGRAM_PORT_COUNT-1:0] destination_valid_w;
	logic [PROGRAM_PORT_COUNT*PROGRAM_TARGET_KIND_WIDTH-1:0] program_target_kind_w;
	logic [PROGRAM_PORT_COUNT*PROGRAM_TARGET_INDEX_WIDTH-1:0] program_queue_id_w;
	logic [QUEUE_COUNT-1:0] load_ready;
	logic [QUEUE_COUNT-1:0] prime_ready;
	logic [QUEUE_COUNT-1:0] frontend_ready;
	logic [QUEUE_COUNT-1:0] frontend_idle;
	logic [QUEUE_COUNT-1:0] frontend_fault;
	logic [QUEUE_COUNT*6-1:0] frontend_fault_code;
	logic [QUEUE_COUNT-1:0] frontend_issue_valid;
	logic [QUEUE_COUNT*lpu_pkg::MEM_INSTRUCTION_WIDTH-1:0] frontend_issue_instruction;
	logic [QUEUE_COUNT*32-1:0] frontend_issue_cycle;
	logic [QUEUE_COUNT-1:0] timed_queue_ready;
	logic [QUEUE_COUNT-1:0] timed_queue_idle;
	logic [QUEUE_COUNT-1:0] timed_queue_fault;
	logic [QUEUE_COUNT-1:0] execution_issue_valid;
	logic [QUEUE_COUNT-1:0] execution_issue_ready;
	logic [QUEUE_COUNT*lpu_pkg::MEM_INSTRUCTION_WIDTH-1:0] execution_issue_instruction;
	logic frontend_rst_ni;

	initial begin
		if(PROGRAM_PORT_COUNT < 1 || PROGRAM_BANKS_PER_PORT < 1)begin
			$error("MEM Program port organization must be positive");
		end
		if((PROGRAM_PORT_COUNT * PROGRAM_BANKS_PER_PORT) < QUEUE_COUNT ||
			((PROGRAM_PORT_COUNT - 1) * PROGRAM_BANKS_PER_PORT) >= QUEUE_COUNT)begin
			$error("MEM Program ports must cover every Bank exactly once");
		end
	end

	assign frontend_rst_ni = rst_ni && !program_reset_i;
	assign frontends_ready_o = &frontend_ready;
	assign frontends_idle_o = (&frontend_idle) && (&timed_queue_idle);
	assign frontend_fault_o = (|frontend_fault) || (|timed_queue_fault) || (|mem_fault_o);
	assign frontend_fault_code_o = (|mem_fault_o) ? 6'd3 :
		(((|frontend_fault) || (|timed_queue_fault)) ? 6'd2 : 6'd0);
	assign execution_issue_valid = local_frontend_enable_i ? local_issue_valid_o : external_issue_valid_i;
	assign execution_issue_instruction = local_frontend_enable_i ?
		local_issue_instruction_o : external_issue_instruction_i;
	assign external_issue_ready_o = local_frontend_enable_i ? '0 : execution_issue_ready;

	// Every Program port is owned by one Relay and can address only that Relay's
	// disjoint Bank range. Invalid destinations are consumed with an error.
	generate
		for(genvar program_port_gen = 0; program_port_gen < PROGRAM_PORT_COUNT;
			program_port_gen = program_port_gen + 1)begin : gen_program_port
			localparam integer LOCAL_BANK_BASE = program_port_gen * PROGRAM_BANKS_PER_PORT;
			localparam integer LOCAL_BANK_COUNT =
				((QUEUE_COUNT - LOCAL_BANK_BASE) > PROGRAM_BANKS_PER_PORT) ?
				PROGRAM_BANKS_PER_PORT : (QUEUE_COUNT - LOCAL_BANK_BASE);
			logic selected_load_ready;
			logic selected_prime_ready;

			assign program_target_kind_w[program_port_gen*PROGRAM_TARGET_KIND_WIDTH+:
				PROGRAM_TARGET_KIND_WIDTH] = program_destination_i[
				program_port_gen*PROGRAM_DESTINATION_WIDTH+PROGRAM_DESTINATION_KIND_LSB+:
				PROGRAM_TARGET_KIND_WIDTH];
			assign program_queue_id_w[program_port_gen*PROGRAM_TARGET_INDEX_WIDTH+:
				PROGRAM_TARGET_INDEX_WIDTH] = program_destination_i[
				program_port_gen*PROGRAM_DESTINATION_WIDTH+PROGRAM_DESTINATION_INDEX_LSB+:
				PROGRAM_TARGET_INDEX_WIDTH];
			assign destination_valid_w[program_port_gen] =
				(program_destination_i[program_port_gen*PROGRAM_DESTINATION_WIDTH+
				 PROGRAM_DESTINATION_HEMISPHERE_BIT] == HEMISPHERE_INDEX) &&
				(program_target_kind_w[program_port_gen*PROGRAM_TARGET_KIND_WIDTH+:
				 PROGRAM_TARGET_KIND_WIDTH] == PROGRAM_TARGET_MEM) &&
				(program_queue_id_w[program_port_gen*PROGRAM_TARGET_INDEX_WIDTH+:
				 PROGRAM_TARGET_INDEX_WIDTH] >= LOCAL_BANK_BASE) &&
				(program_queue_id_w[program_port_gen*PROGRAM_TARGET_INDEX_WIDTH+:
				 PROGRAM_TARGET_INDEX_WIDTH] < LOCAL_BANK_BASE + LOCAL_BANK_COUNT);
			assign selected_load_ready = destination_valid_w[program_port_gen] ?
				load_ready[program_queue_id_w[program_port_gen*PROGRAM_TARGET_INDEX_WIDTH+:
				 PROGRAM_TARGET_INDEX_WIDTH]] : 1'b1;
			assign selected_prime_ready = destination_valid_w[program_port_gen] ?
				prime_ready[program_queue_id_w[program_port_gen*PROGRAM_TARGET_INDEX_WIDTH+:
				 PROGRAM_TARGET_INDEX_WIDTH]] : 1'b1;
			assign program_ready_o[program_port_gen] =
				(program_control_i[program_port_gen*PROGRAM_LOAD_CONTROL_WIDTH+:
				 PROGRAM_LOAD_CONTROL_WIDTH] == PROGRAM_LOAD_WRITE) ?
				selected_load_ready : selected_prime_ready;
			assign program_error_o[program_port_gen] = program_valid_i[program_port_gen] &&
				program_ready_o[program_port_gen] &&
				(!destination_valid_w[program_port_gen] ||
				 ((program_control_i[program_port_gen*PROGRAM_LOAD_CONTROL_WIDTH+:
				   PROGRAM_LOAD_CONTROL_WIDTH] == PROGRAM_LOAD_WRITE) &&
				  ((program_strb_i[program_port_gen*4+:4] != 4'b0111) ||
				   (program_address_i[program_port_gen*17+:17] >= IMEM_DEPTH))));
			assign write_fire_w[program_port_gen] = program_valid_i[program_port_gen] &&
				program_ready_o[program_port_gen] &&
				(program_control_i[program_port_gen*PROGRAM_LOAD_CONTROL_WIDTH+:
				 PROGRAM_LOAD_CONTROL_WIDTH] == PROGRAM_LOAD_WRITE) &&
				destination_valid_w[program_port_gen] &&
				(program_strb_i[program_port_gen*4+:4] == 4'b0111) &&
				(program_address_i[program_port_gen*17+:17] < IMEM_DEPTH);
			assign prime_fire_w[program_port_gen] = program_valid_i[program_port_gen] &&
				program_ready_o[program_port_gen] &&
				(program_control_i[program_port_gen*PROGRAM_LOAD_CONTROL_WIDTH+:
				 PROGRAM_LOAD_CONTROL_WIDTH] == PROGRAM_LOAD_PRIME) &&
				destination_valid_w[program_port_gen];
		end
	endgenerate

	// Instantiate one independent iMEM Frontend and Timed Queue per MEM Bank.
	// Each Bank selects the Program port that owns its fixed Bank range.
	generate
		for(genvar queue_gen = 0; queue_gen < QUEUE_COUNT; queue_gen++)begin : gen_bank_frontend
			localparam integer PROGRAM_PORT_INDEX = queue_gen / PROGRAM_BANKS_PER_PORT;
			logic [$clog2(FU_QUEUE_DEPTH+1)-1:0] timed_queue_level;
			logic frontend_run;
			logic [31:0] frontend_schedule_cycle;

			// QCTL controls only the selected Bank. The adjacent Bank retains its
			// own local time and can continue independently.
			assign frontend_run = local_frontend_enable_i &&
				(qctl_active_i[queue_gen] ? qctl_scheduler_enable_i[queue_gen] : run_i);
			assign frontend_schedule_cycle = qctl_active_i[queue_gen] ?
				qctl_schedule_cycle_i[queue_gen*32+:32] : schedule_cycle_i;

			lpu_mem_local_imem_frontend #(
				.IMEM_DEPTH(IMEM_DEPTH),
				.ACTIVE_CONTEXTS(ACTIVE_CONTEXTS)
			) u_frontend (
				.clk_i, .rst_ni, .program_reset_i, .clear_i(1'b0),
				.load_valid_i(write_fire_w[PROGRAM_PORT_INDEX] &&
					(program_queue_id_w[PROGRAM_PORT_INDEX*PROGRAM_TARGET_INDEX_WIDTH+:
					 PROGRAM_TARGET_INDEX_WIDTH] == queue_gen)),
				.load_ready_o(load_ready[queue_gen]),
				.load_address_i(program_address_i[PROGRAM_PORT_INDEX*17+:17]),
				.load_data_i(program_data_i[PROGRAM_PORT_INDEX*128+:128]),
				.load_strb_i(program_strb_i[PROGRAM_PORT_INDEX*4+:4]),
				.load_last_i(program_last_i[PROGRAM_PORT_INDEX]),
				.prime_valid_i(prime_fire_w[PROGRAM_PORT_INDEX] &&
					(program_queue_id_w[PROGRAM_PORT_INDEX*PROGRAM_TARGET_INDEX_WIDTH+:
					 PROGRAM_TARGET_INDEX_WIDTH] == queue_gen)),
				.prime_ready_o(prime_ready[queue_gen]), .run_i(frontend_run),
				.schedule_cycle_i(frontend_schedule_cycle),
				.issue_valid_o(frontend_issue_valid[queue_gen]),
				.issue_ready_i(timed_queue_ready[queue_gen]),
				.issue_instruction_o(frontend_issue_instruction[
					queue_gen*lpu_pkg::MEM_INSTRUCTION_WIDTH+:lpu_pkg::MEM_INSTRUCTION_WIDTH]),
				.issue_cycle_o(frontend_issue_cycle[queue_gen*32+:32]),
				.configured_o(), .frontend_ready_o(frontend_ready[queue_gen]),
				.frontend_idle_o(frontend_idle[queue_gen]),
				.fault_o(frontend_fault[queue_gen]),
				.fault_code_o(frontend_fault_code[queue_gen*6+:6])
			);

			// Timed Queue is the sequential ownership boundary between Macro
			// scheduling and the selected MEM implementation.
			lpu_mem_bank_queue #(.DEPTH(FU_QUEUE_DEPTH)) u_timed_queue (
				.clk_i, .rst_ni(frontend_rst_ni), .run_i(frontend_run),
				.schedule_cycle_i(frontend_schedule_cycle),
				.enqueue_valid_i(frontend_issue_valid[queue_gen]),
				.enqueue_ready_o(timed_queue_ready[queue_gen]),
				.enqueue_instruction_i(frontend_issue_instruction[
					queue_gen*lpu_pkg::MEM_INSTRUCTION_WIDTH+:lpu_pkg::MEM_INSTRUCTION_WIDTH]),
				.enqueue_cycle_i(frontend_issue_cycle[queue_gen*32+:32]),
				.issue_valid_o(local_issue_valid_o[queue_gen]),
				.issue_ready_i(execution_issue_ready[queue_gen]),
				.issue_instruction_o(local_issue_instruction_o[
					queue_gen*lpu_pkg::MEM_INSTRUCTION_WIDTH+:lpu_pkg::MEM_INSTRUCTION_WIDTH]),
				.issue_cycle_o(local_issue_cycle_o[queue_gen*32+:32]),
				.level_o(timed_queue_level), .fault_o(timed_queue_fault[queue_gen])
			);

			assign timed_queue_idle[queue_gen] = timed_queue_level == '0;
		end
	endgenerate

	// Select the native MEM command path or the legacy Slice-compatible path
	// while preserving the same Bank-local issue ownership at this boundary.
	generate
		if(USE_NATIVE_MEM)begin : gen_native_execution
			logic [QUEUE_COUNT-1:0] native_issue_valid;
			logic [QUEUE_COUNT*lpu_pkg::MEM_NATIVE_COMMAND_WIDTH-1:0] native_command;
			logic [QUEUE_COUNT-1:0] command_fault;
			logic [QUEUE_COUNT-1:0] command_unsupported;
			logic [QUEUE_COUNT-1:0] native_bank_fault;
			logic [2*4*32-1:0] boundary_valid_out;
			logic [2*4*32*64-1:0] boundary_data_out;
			logic [2*16*4-1:0] srf_collision;
			logic [52*8-1:0] internal_collision;

			assign execution_issue_ready = '1;
			assign mem_fault_o = command_fault | native_bank_fault;
			assign east_edge_valid_o = boundary_valid_out[0+:4*32];
			assign east_edge_data_o = boundary_data_out[0+:4*32*64];
			assign west_edge_valid_o = boundary_valid_out[4*32+:4*32];
			assign west_edge_data_o = boundary_data_out[4*32*64+:4*32*64];
			assign conflict_o = (|srf_collision) || (|internal_collision);

			lpu_mem_srf_command_integration #(
				.MEM_SLICES(lpu_pkg::MEM_SLICES_PER_HEMISPHERE),
				.MEM_SLICES_PER_GROUP(lpu_pkg::MEM_SLICES_PER_GROUP),
				.MEM_DEPTH_ROWS(DEPTH_ROWS)
			) u_native_mem (
				.clk_i, .rst_ni,
				.vmodel_issue_valid_i(execution_issue_valid),
				.vmodel_issue_instruction_i(execution_issue_instruction),
				.native_issue_valid_o(native_issue_valid), .native_issue_o(native_command),
				.command_fault_o(command_fault), .command_unsupported_o(command_unsupported),
				.boundary_valid_i({west_edge_valid_i, east_edge_valid_i}),
				.boundary_data_i({west_edge_data_i, east_edge_data_i}),
				.boundary_valid_o(boundary_valid_out), .boundary_data_o(boundary_data_out),
				.state_valid_o(), .state_data_o(), .mem_boundary_consume_o(),
				.mem_producer_valid_o(), .mem_producer_data_o(),
				.mem_producer_direction_o(), .mem_producer_stream_o(),
				.mem_producer_boundary_o(), .srf_collision_o(srf_collision),
				.srf_invalid_consume_o(), .mem_internal_collision_o(internal_collision),
				.mem_bank_fault_valid_o(native_bank_fault), .mem_fault_valid_o(),
				.mem_busy_o()
			);
		end
		else begin : gen_legacy_execution
			logic [51:0] legacy_issue_valid;
			logic [52*lpu_pkg::MEM_INSTRUCTION_WIDTH-1:0] legacy_issue_instruction;
			logic [52*4-1:0] legacy_tile_fault;
			logic [51:0] bank1_fault_q;

			assign execution_issue_ready = '1;
			for(genvar slice_gen = 0; slice_gen < 52; slice_gen++)begin : gen_legacy_bank_map
				assign legacy_issue_valid[slice_gen] = execution_issue_valid[slice_gen*2];
				assign legacy_issue_instruction[
					slice_gen*lpu_pkg::MEM_INSTRUCTION_WIDTH+:lpu_pkg::MEM_INSTRUCTION_WIDTH] =
					execution_issue_instruction[
					(slice_gen*2)*lpu_pkg::MEM_INSTRUCTION_WIDTH+:lpu_pkg::MEM_INSTRUCTION_WIDTH];
				assign mem_fault_o[slice_gen*2] = |legacy_tile_fault[slice_gen*4+:4];
				assign mem_fault_o[slice_gen*2+1] = bank1_fault_q[slice_gen];
				always_ff @(posedge clk_i or negedge frontend_rst_ni) begin
					if(!frontend_rst_ni)begin
						bank1_fault_q[slice_gen] <= 1'b0;
					end
					else if(execution_issue_valid[slice_gen*2+1])begin
						bank1_fault_q[slice_gen] <= 1'b1;
					end
				end
			end

			// Legacy has one physical issue path per Slice. Bank 1 therefore
			// produces an explicit compatibility fault instead of being aliased.
			lpu_mem_hemisphere #(
				.DEPTH_ROWS(DEPTH_ROWS), .ACTIVE_COLUMNS(ACTIVE_COLUMNS),
				.USE_SRAM_MACRO(USE_SRAM_MACRO)
			) u_legacy_mem (
				.clk_i, .rst_ni, .run_i, .issue_valid_i(legacy_issue_valid),
				.issue_instruction_i(legacy_issue_instruction),
				.east_edge_valid_i, .east_edge_data_i, .east_edge_valid_o, .east_edge_data_o,
				.west_edge_valid_i, .west_edge_data_i, .west_edge_valid_o, .west_edge_data_o,
				.mem_fault_o(legacy_tile_fault), .conflict_o
			);
		end
	endgenerate
endmodule
