module lpu_mem_subsystem #(
	parameter integer IMEM_DEPTH = 131072,
	parameter integer ACTIVE_CONTEXTS = 4,
	parameter integer FU_QUEUE_DEPTH = 16,
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

	input logic program_valid_i,
	output logic program_ready_o,
	input logic [2:0] program_control_i,
	input logic [7:0] program_queue_id_i,
	input logic [16:0] program_address_i,
	input logic [127:0] program_data_i,
	input logic [3:0] program_strb_i,
	input logic program_last_i,
	output logic program_error_o,

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

	logic clear_fire_w;
	logic write_fire_w;
	logic prime_fire_w;
	logic selected_load_ready_w;
	logic selected_prime_ready_w;
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

	assign clear_fire_w = program_valid_i && program_ready_o &&
		((program_control_i == PROGRAM_LOAD_CLEAR) || (program_control_i == PROGRAM_LOAD_ABORT));
	assign write_fire_w = program_valid_i && program_ready_o &&
		(program_control_i == PROGRAM_LOAD_WRITE) && (program_strb_i == 4'b0111) &&
		(program_address_i < IMEM_DEPTH);
	assign prime_fire_w = program_valid_i && program_ready_o &&
		(program_control_i == PROGRAM_LOAD_PRIME);
	assign frontend_rst_ni = rst_ni && !program_reset_i && !clear_fire_w;
	assign frontends_ready_o = &frontend_ready;
	assign frontends_idle_o = (&frontend_idle) && (&timed_queue_idle);
	assign frontend_fault_o = (|frontend_fault) || (|timed_queue_fault) || (|mem_fault_o);
	assign frontend_fault_code_o = (|mem_fault_o) ? 6'd3 :
		(((|frontend_fault) || (|timed_queue_fault)) ? 6'd2 : 6'd0);
	assign execution_issue_valid = local_frontend_enable_i ? local_issue_valid_o : external_issue_valid_i;
	assign execution_issue_instruction = local_frontend_enable_i ?
		local_issue_instruction_o : external_issue_instruction_i;
	assign external_issue_ready_o = local_frontend_enable_i ? '0 : execution_issue_ready;

	// Queue ID is bank-local within one Hemisphere: slice*2+bank, 0..103.
	always_comb begin
		selected_load_ready_w = 1'b0;
		selected_prime_ready_w = 1'b0;
		if(program_queue_id_i < QUEUE_COUNT)begin
			selected_load_ready_w = load_ready[program_queue_id_i];
			selected_prime_ready_w = prime_ready[program_queue_id_i];
		end
		else begin
			// Invalid destinations are consumed and reported instead of holding
			// Program Load in permanent backpressure.
			selected_load_ready_w = 1'b1;
			selected_prime_ready_w = 1'b1;
		end
		case(program_control_i)
			PROGRAM_LOAD_WRITE: program_ready_o = selected_load_ready_w;
			PROGRAM_LOAD_PRIME: program_ready_o = selected_prime_ready_w;
			PROGRAM_LOAD_CLEAR,
			PROGRAM_LOAD_ABORT: program_ready_o = 1'b1;
			default: program_ready_o = 1'b1;
		endcase
		program_error_o = program_valid_i && program_ready_o &&
			((program_queue_id_i >= QUEUE_COUNT) ||
			 ((program_control_i == PROGRAM_LOAD_WRITE) &&
			  ((program_strb_i != 4'b0111) || (program_address_i >= IMEM_DEPTH))) ||
			 (program_control_i > PROGRAM_LOAD_ABORT));
	end

	generate
		for(genvar queue_gen = 0; queue_gen < QUEUE_COUNT; queue_gen++)begin : gen_bank_frontend
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
				.clk_i, .rst_ni, .program_reset_i, .clear_i(clear_fire_w),
				.load_valid_i(write_fire_w && (program_queue_id_i == queue_gen)),
				.load_ready_o(load_ready[queue_gen]), .load_address_i(program_address_i),
				.load_data_i(program_data_i), .load_strb_i(program_strb_i),
				.load_last_i(program_last_i),
				.prime_valid_i(prime_fire_w && (program_queue_id_i == queue_gen)),
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
