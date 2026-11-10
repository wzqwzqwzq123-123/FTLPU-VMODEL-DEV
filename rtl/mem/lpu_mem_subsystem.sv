module lpu_mem_subsystem #(
	parameter integer IMEM_DEPTH = 131072,
	parameter integer ACTIVE_CONTEXTS = 4,
	parameter integer FU_QUEUE_DEPTH = 16,
	parameter integer DEPTH_ROWS = lpu_pkg::SRAM_DEPTH_ROWS,
	parameter integer ACTIVE_COLUMNS = 52,
	parameter bit USE_SRAM_MACRO = 1'b0
) (
	input logic clk_i,
	input logic rst_ni,
	input logic program_reset_i,
	input logic local_frontend_enable_i,
	input logic run_i,
	input logic [31:0] schedule_cycle_i,
	input logic [51:0] qctl_active_i,
	input logic [51:0] qctl_scheduler_enable_i,
	input logic [52*32-1:0] qctl_schedule_cycle_i,

	input logic program_valid_i,
	output logic program_ready_o,
	input logic [2:0] program_control_i,
	input logic [7:0] program_queue_id_i,
	input logic [16:0] program_address_i,
	input logic [127:0] program_data_i,
	input logic [3:0] program_strb_i,
	input logic program_last_i,
	output logic program_error_o,

	input logic [51:0] external_issue_valid_i,
	input logic [52*47-1:0] external_issue_instruction_i,
	output logic [51:0] local_issue_valid_o,
	output logic [52*47-1:0] local_issue_instruction_o,
	output logic [52*32-1:0] local_issue_cycle_o,

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

	output logic [52*4-1:0] mem_fault_o,
	output logic conflict_o
);
	import lpu_program_load_pkg::*;

	localparam integer QUEUE_COUNT = 52;

	logic clear_fire_w;
	logic write_fire_w;
	logic prime_fire_w;
	logic selected_load_ready_w;
	logic selected_prime_ready_w;
	logic [QUEUE_COUNT-1:0] load_ready;
	logic [QUEUE_COUNT-1:0] prime_ready;
	logic [QUEUE_COUNT-1:0] configured;
	logic [QUEUE_COUNT-1:0] frontend_ready;
	logic [QUEUE_COUNT-1:0] frontend_idle;
	logic [QUEUE_COUNT-1:0] frontend_fault;
	logic [QUEUE_COUNT*6-1:0] frontend_fault_code;
	logic [QUEUE_COUNT-1:0] frontend_issue_valid;
	logic [QUEUE_COUNT*47-1:0] frontend_issue_instruction;
	logic [QUEUE_COUNT*32-1:0] frontend_issue_cycle;
	logic [QUEUE_COUNT-1:0] fu_queue_ready;
	logic [QUEUE_COUNT-1:0] fu_queue_idle;
	logic [QUEUE_COUNT-1:0] fu_queue_fault;
	logic [QUEUE_COUNT-1:0] execution_issue_valid;
	logic [QUEUE_COUNT*47-1:0] execution_issue_instruction;
	logic frontend_rst_ni;

	assign clear_fire_w = program_valid_i && program_ready_o &&
		((program_control_i == PROGRAM_LOAD_CLEAR) || (program_control_i == PROGRAM_LOAD_ABORT));
	assign write_fire_w = program_valid_i && program_ready_o &&
		(program_control_i == PROGRAM_LOAD_WRITE) &&
		(program_strb_i == 4'b0111) && (program_address_i < IMEM_DEPTH);
	assign prime_fire_w = program_valid_i && program_ready_o &&
		(program_control_i == PROGRAM_LOAD_PRIME);
	assign frontend_rst_ni = rst_ni && !program_reset_i && !clear_fire_w;
	assign frontends_ready_o = &frontend_ready;
	assign frontends_idle_o = (&frontend_idle) && (&fu_queue_idle);
	assign frontend_fault_o = (|frontend_fault) || (|fu_queue_fault);
	assign frontend_fault_code_o = frontend_fault_o ? 6'd2 : 6'd0;
	assign execution_issue_valid = local_frontend_enable_i ? local_issue_valid_o : external_issue_valid_i;
	assign execution_issue_instruction = local_frontend_enable_i ?
		local_issue_instruction_o : external_issue_instruction_i;

	// Only the selected Column-local frontend participates in Program Load.
	always_comb begin
		selected_load_ready_w = 1'b0;
		selected_prime_ready_w = 1'b0;
		if(program_queue_id_i < QUEUE_COUNT)begin
			selected_load_ready_w = load_ready[program_queue_id_i];
			selected_prime_ready_w = prime_ready[program_queue_id_i];
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
		for(genvar queue_gen = 0; queue_gen < QUEUE_COUNT; queue_gen = queue_gen + 1)begin : gen_queue_frontend
			logic [$clog2(FU_QUEUE_DEPTH+1)-1:0] fu_queue_level;
			logic frontend_run;
			logic [31:0] frontend_schedule_cycle;

			// An active QCTL lane owns this Queue's logical time. Unconfigured
			// lanes retain the original chip-wide schedule cycle without alteration.
			assign frontend_run = local_frontend_enable_i &&
				(qctl_active_i[queue_gen] ? qctl_scheduler_enable_i[queue_gen] : run_i);
			assign frontend_schedule_cycle = qctl_active_i[queue_gen] ?
				qctl_schedule_cycle_i[queue_gen*32+:32] : schedule_cycle_i;

			lpu_mem_local_imem_frontend #(
				.IMEM_DEPTH(IMEM_DEPTH),
				.ACTIVE_CONTEXTS(ACTIVE_CONTEXTS)
			) u_frontend (
				.clk_i,
				.rst_ni,
				.program_reset_i,
				.clear_i(clear_fire_w),
				.load_valid_i(write_fire_w && (program_queue_id_i == queue_gen)),
				.load_ready_o(load_ready[queue_gen]),
				.load_address_i(program_address_i),
				.load_data_i(program_data_i),
				.load_strb_i(program_strb_i),
				.load_last_i(program_last_i),
				.prime_valid_i(prime_fire_w && (program_queue_id_i == queue_gen)),
				.prime_ready_o(prime_ready[queue_gen]),
				.run_i(frontend_run),
				.schedule_cycle_i(frontend_schedule_cycle),
				.issue_valid_o(frontend_issue_valid[queue_gen]),
				.issue_ready_i(fu_queue_ready[queue_gen]),
				.issue_instruction_o(frontend_issue_instruction[queue_gen*47+:47]),
				.issue_cycle_o(frontend_issue_cycle[queue_gen*32+:32]),
				.configured_o(configured[queue_gen]),
				.frontend_ready_o(frontend_ready[queue_gen]),
				.frontend_idle_o(frontend_idle[queue_gen]),
				.fault_o(frontend_fault[queue_gen]),
				.fault_code_o(frontend_fault_code[queue_gen*6+:6])
			);

			// The Subsystem owns the sequential deadline queue after Macro expansion.
			lpu_mem_bank_queue #(.DEPTH(FU_QUEUE_DEPTH)) u_timed_queue (
				.clk_i,
				.rst_ni(frontend_rst_ni),
				.run_i(frontend_run),
				.schedule_cycle_i(frontend_schedule_cycle),
				.enqueue_valid_i(frontend_issue_valid[queue_gen]),
				.enqueue_ready_o(fu_queue_ready[queue_gen]),
				.enqueue_instruction_i(frontend_issue_instruction[queue_gen*47+:47]),
				.enqueue_cycle_i(frontend_issue_cycle[queue_gen*32+:32]),
				.issue_valid_o(local_issue_valid_o[queue_gen]),
				.issue_ready_i(1'b1),
				.issue_instruction_o(local_issue_instruction_o[queue_gen*47+:47]),
				.issue_cycle_o(local_issue_cycle_o[queue_gen*32+:32]),
				.level_o(fu_queue_level),
				.fault_o(fu_queue_fault[queue_gen])
			);

			assign fu_queue_idle[queue_gen] = fu_queue_level == '0;
		end
	endgenerate

	lpu_mem_hemisphere #(
		.DEPTH_ROWS(DEPTH_ROWS),
		.ACTIVE_COLUMNS(ACTIVE_COLUMNS),
		.USE_SRAM_MACRO(USE_SRAM_MACRO)
	) u_execution (
		.clk_i,
		.rst_ni,
		.run_i,
		.issue_valid_i(execution_issue_valid),
		.issue_instruction_i(execution_issue_instruction),
		.east_edge_valid_i,
		.east_edge_data_i,
		.east_edge_valid_o,
		.east_edge_data_o,
		.west_edge_valid_i,
		.west_edge_data_i,
		.west_edge_valid_o,
		.west_edge_data_o,
		.mem_fault_o,
		.conflict_o
	);
endmodule
