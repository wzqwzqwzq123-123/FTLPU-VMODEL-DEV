module lpu_mem_subsystem #(
	parameter integer IMEM_DEPTH = 131072,
	parameter integer ACTIVE_CONTEXTS = 4,
	parameter integer BANK_QUEUE_DEPTH = 16,
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
	input logic [52*2-1:0] qctl_active_i,
	input logic [52*2-1:0] qctl_scheduler_enable_i,
	input logic [52*2*32-1:0] qctl_schedule_cycle_i,

	input logic program_valid_i,
	output logic program_ready_o,
	input logic [2:0] program_command_i,
	input logic [7:0] program_queue_id_i,
	input logic [16:0] program_address_i,
	input logic [127:0] program_data_i,
	input logic [15:0] program_strb_i,
	input logic program_last_i,
	output logic program_error_o,

	input logic [52*2-1:0] external_issue_valid_i,
	input logic [52*2*47-1:0] external_issue_instruction_i,
	output logic [52*2-1:0] local_issue_valid_o,
	output logic [52*2*47-1:0] local_issue_instruction_o,
	output logic [52*2*32-1:0] local_issue_cycle_o,

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

	input logic host_write_valid_i,
	input logic [5:0] host_column_i,
	input logic host_bank_i,
	input logic [1:0] host_tile_i,
	input logic [15:0] host_address_i,
	input logic [63:0] host_write_data_i,
	output logic [63:0] host_read_data_o,

	output logic [52*2*4-1:0] mem_fault_o,
	output logic conflict_o
);
	import lpu_program_load_pkg::*;

	localparam integer BANK_COUNT = 52 * 2;

	logic clear_fire_w;
	logic write_fire_w;
	logic prime_fire_w;
	logic selected_load_ready_w;
	logic selected_prime_ready_w;
	logic [BANK_COUNT-1:0] load_ready;
	logic [BANK_COUNT-1:0] prime_ready;
	logic [BANK_COUNT-1:0] configured;
	logic [BANK_COUNT-1:0] frontend_ready;
	logic [BANK_COUNT-1:0] frontend_idle;
	logic [BANK_COUNT-1:0] frontend_fault;
	logic [BANK_COUNT*6-1:0] frontend_fault_code;
	logic [BANK_COUNT-1:0] frontend_issue_valid;
	logic [BANK_COUNT*47-1:0] frontend_issue_instruction;
	logic [BANK_COUNT*32-1:0] frontend_issue_cycle;
	logic [BANK_COUNT-1:0] bank_queue_ready;
	logic [BANK_COUNT-1:0] bank_queue_idle;
	logic [BANK_COUNT-1:0] bank_queue_fault;
	logic [BANK_COUNT-1:0] execution_issue_valid;
	logic [BANK_COUNT*47-1:0] execution_issue_instruction;
	logic frontend_rst_ni;

	assign clear_fire_w = program_valid_i && program_ready_o &&
		((program_command_i == PROGRAM_LOAD_CLEAR) || (program_command_i == PROGRAM_LOAD_ABORT));
	assign write_fire_w = program_valid_i && program_ready_o &&
		(program_command_i == PROGRAM_LOAD_WRITE);
	assign prime_fire_w = program_valid_i && program_ready_o &&
		(program_command_i == PROGRAM_LOAD_PRIME);
	assign frontend_rst_ni = rst_ni && !program_reset_i && !clear_fire_w;
	assign frontends_ready_o = &frontend_ready;
	assign frontends_idle_o = (&frontend_idle) && (&bank_queue_idle);
	assign frontend_fault_o = (|frontend_fault) || (|bank_queue_fault);
	assign frontend_fault_code_o = frontend_fault_o ? 6'd2 : 6'd0;
	assign execution_issue_valid = local_frontend_enable_i ? local_issue_valid_o : external_issue_valid_i;
	assign execution_issue_instruction = local_frontend_enable_i ?
		local_issue_instruction_o : external_issue_instruction_i;

	// Only the selected Bank frontend participates in the Program Load handshake.
	always_comb begin
		selected_load_ready_w = 1'b0;
		selected_prime_ready_w = 1'b0;
		if(program_queue_id_i < BANK_COUNT)begin
			selected_load_ready_w = load_ready[program_queue_id_i];
			selected_prime_ready_w = prime_ready[program_queue_id_i];
		end
		case(program_command_i)
			PROGRAM_LOAD_WRITE: program_ready_o = selected_load_ready_w;
			PROGRAM_LOAD_PRIME: program_ready_o = selected_prime_ready_w;
			PROGRAM_LOAD_CLEAR,
			PROGRAM_LOAD_ABORT: program_ready_o = 1'b1;
			default: program_ready_o = 1'b1;
		endcase
		program_error_o = program_valid_i && program_ready_o &&
			((program_queue_id_i >= BANK_COUNT) ||
			 ((program_command_i == PROGRAM_LOAD_WRITE) &&
			  ((program_strb_i != 16'h0fff) || (program_address_i >= IMEM_DEPTH))) ||
			 (program_command_i > PROGRAM_LOAD_ABORT));
	end

	generate
		for(genvar bank_gen = 0; bank_gen < BANK_COUNT; bank_gen = bank_gen + 1)begin : gen_bank_frontend
			logic [$clog2(BANK_QUEUE_DEPTH+1)-1:0] bank_queue_level;
			logic frontend_run;
			logic [31:0] frontend_schedule_cycle;

			// An active QCTL lane owns this Bank Queue's logical time. Unconfigured
			// lanes retain the original chip-wide schedule cycle without alteration.
			assign frontend_run = local_frontend_enable_i &&
				(qctl_active_i[bank_gen] ? qctl_scheduler_enable_i[bank_gen] : run_i);
			assign frontend_schedule_cycle = qctl_active_i[bank_gen] ?
				qctl_schedule_cycle_i[bank_gen*32+:32] : schedule_cycle_i;

			lpu_mem_local_imem_frontend #(
				.IMEM_DEPTH(IMEM_DEPTH),
				.ACTIVE_CONTEXTS(ACTIVE_CONTEXTS)
			) u_frontend (
				.clk_i,
				.rst_ni,
				.program_reset_i,
				.clear_i(clear_fire_w),
				.load_valid_i(write_fire_w && (program_queue_id_i == bank_gen)),
				.load_ready_o(load_ready[bank_gen]),
				.load_address_i(program_address_i),
				.load_data_i(program_data_i),
				.load_strb_i(program_strb_i),
				.load_last_i(program_last_i),
				.prime_valid_i(prime_fire_w && (program_queue_id_i == bank_gen)),
				.prime_ready_o(prime_ready[bank_gen]),
				.run_i(frontend_run),
				.schedule_cycle_i(frontend_schedule_cycle),
				.issue_valid_o(frontend_issue_valid[bank_gen]),
				.issue_ready_i(bank_queue_ready[bank_gen]),
				.issue_instruction_o(frontend_issue_instruction[bank_gen*47+:47]),
				.issue_cycle_o(frontend_issue_cycle[bank_gen*32+:32]),
				.configured_o(configured[bank_gen]),
				.frontend_ready_o(frontend_ready[bank_gen]),
				.frontend_idle_o(frontend_idle[bank_gen]),
				.fault_o(frontend_fault[bank_gen]),
				.fault_code_o(frontend_fault_code[bank_gen*6+:6])
			);

			// The Subsystem owns the only sequential base-instruction buffer for this Bank.
			lpu_mem_bank_queue #(.DEPTH(BANK_QUEUE_DEPTH)) u_timed_queue (
				.clk_i,
				.rst_ni(frontend_rst_ni),
				.run_i(frontend_run),
				.schedule_cycle_i(frontend_schedule_cycle),
				.enqueue_valid_i(frontend_issue_valid[bank_gen]),
				.enqueue_ready_o(bank_queue_ready[bank_gen]),
				.enqueue_instruction_i(frontend_issue_instruction[bank_gen*47+:47]),
				.enqueue_cycle_i(frontend_issue_cycle[bank_gen*32+:32]),
				.issue_valid_o(local_issue_valid_o[bank_gen]),
				.issue_ready_i(1'b1),
				.issue_instruction_o(local_issue_instruction_o[bank_gen*47+:47]),
				.issue_cycle_o(local_issue_cycle_o[bank_gen*32+:32]),
				.level_o(bank_queue_level),
				.fault_o(bank_queue_fault[bank_gen])
			);

			assign bank_queue_idle[bank_gen] = bank_queue_level == '0;
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
		.host_write_valid_i,
		.host_column_i,
		.host_bank_i,
		.host_tile_i,
		.host_address_i,
		.host_write_data_i,
		.host_read_data_o,
		.mem_fault_o,
		.conflict_o
	);
endmodule
