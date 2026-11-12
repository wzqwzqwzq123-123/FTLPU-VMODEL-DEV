module lpu_program_load_controller #(
	parameter integer COMMAND_DEPTH = 32,
	parameter integer DMA_DATA_WIDTH = 256,
	parameter integer MEM_IMEM_DEPTH = 131072,
	parameter integer MXM_IMEM_DEPTH = 65536,
	parameter integer COMMAND_ADDRESS_WIDTH = COMMAND_DEPTH <= 1 ? 1 : $clog2(COMMAND_DEPTH)
) (
	input logic clk_i,
	input logic rst_ni,
	input logic program_reset_i,

	// A LOAD_IMEM command carries the ProgramImage descriptor. Other opcodes sequence the request.
	input logic command_write_valid_i,
	output logic command_write_ready_o,
	input logic [COMMAND_ADDRESS_WIDTH-1:0] command_write_address_i,
	input logic [2:0] command_write_opcode_i,
	input logic [63:0] command_write_source_address_i,
	input logic [31:0] command_write_byte_count_i,
	input logic [11:0] command_write_destination_i,
	input logic [1:0] command_write_format_i,
	input logic [1:0] command_write_encoding_mode_i,
	input logic [16:0] command_write_imem_base_address_i,
	input logic command_write_image_first_i,
	input logic command_write_image_last_i,
	input logic [15:0] command_write_expected_word_count_i,
	input logic [COMMAND_ADDRESS_WIDTH-1:0] command_write_jump_address_i,

	input logic load_start_valid_i,
	output logic load_start_ready_o,
	input logic [COMMAND_ADDRESS_WIDTH:0] load_start_command_count_i,

	// External DDR/C2C fabric boundary. The RTL owns request ordering and response reassembly.
	output logic dma_cmd_valid_o,
	input logic dma_cmd_ready_i,
	output logic [63:0] dma_cmd_address_o,
	output logic [31:0] dma_cmd_length_o,
	output logic [7:0] dma_cmd_id_o,
	input logic dma_rsp_valid_i,
	output logic dma_rsp_ready_o,
	input logic [DMA_DATA_WIDTH-1:0] dma_rsp_data_i,
	input logic [DMA_DATA_WIDTH/8-1:0] dma_rsp_keep_i,
	input logic dma_rsp_last_i,
	input logic [7:0] dma_rsp_id_i,
	input logic dma_rsp_error_i,

	input logic program_start_request_i,
	input logic dependencies_ready_i,
	output logic program_start_ack_o,
	output logic program_load_complete_o,
	output logic program_ready_o,
	output logic program_running_o,
	output logic program_done_o,
	output logic program_fault_o,
	output logic [5:0] program_fault_code_o,
	output logic [31:0] schedule_cycle_o,

	// ICU owns DMA/reassembly/routing; FU subsystems own every local iMEM and execution frontend.
	output logic [1:0] endpoint_load_valid_o,
	input logic [1:0] endpoint_load_ready_i,
	output logic [2*lpu_program_load_pkg::PROGRAM_LOAD_CONTROL_WIDTH-1:0] endpoint_load_control_o,
	output logic [255:0] endpoint_load_data_o,
	output logic [7:0] endpoint_load_strb_o,
	output logic [23:0] endpoint_load_destination_o,
	output logic [33:0] endpoint_load_imem_address_o,
	output logic [1:0] endpoint_load_last_o,
	input logic [1:0] endpoint_commit_valid_i,
	output logic [1:0] endpoint_commit_ready_o,
	input logic [1:0] endpoint_commit_error_i,
	output logic endpoint_program_start_o,
	input logic endpoint_program_start_ready_i,
	input logic endpoint_started_i,
	input logic endpoint_frontends_ready_i,
	input logic endpoint_frontends_idle_i,
	input logic endpoint_fault_i,
	input logic [5:0] endpoint_fault_code_i,
	input logic [31:0] endpoint_schedule_cycle_i
);
	import lpu_program_load_pkg::*;

	// The integrated RTL frontend accepts Macro-packed Program Images only.
	localparam logic [1:0] PROGRAM_ENCODING_MACRO = 2'd0;
	localparam logic [5:0] FRONTEND_FAULT_OFFSET = 6'd16;

	logic [1:0] command_scope_w;
	logic [2:0] command_target_kind_w;
	logic [7:0] command_target_index_w;
	logic [7:0] command_global_target_w;
	logic command_target_valid_w;
	logic command_write_fire;
	logic descriptor_invalid_w;
	logic descriptor_duplicate_w;
	logic descriptor_fault_q;

	logic [lpu_pkg::MEM_BANK_COUNT-1:0] mem_target_seen_q;
	logic [3:0] mxm_load_target_seen_q;
	logic [3:0] mxm_dequant_target_seen_q;
	logic [3:0] mxm_compute_target_seen_q;

	logic west_load_valid;
	logic west_load_ready;
	logic [PROGRAM_LOAD_CONTROL_WIDTH-1:0] west_load_control;
	logic [127:0] west_load_data;
	logic [3:0] west_load_strb;
	logic [11:0] west_load_destination;
	logic [16:0] west_load_imem_address;
	logic west_load_last;
	logic east_load_valid;
	logic east_load_ready;
	logic [PROGRAM_LOAD_CONTROL_WIDTH-1:0] east_load_control;
	logic [127:0] east_load_data;
	logic [3:0] east_load_strb;
	logic [11:0] east_load_destination;
	logic [16:0] east_load_imem_address;
	logic east_load_last;

	logic [1:0] cluster_load_valid;
	logic [1:0] cluster_load_ready;
	logic [2*PROGRAM_LOAD_CONTROL_WIDTH-1:0] cluster_load_control;
	logic [255:0] cluster_load_data;
	logic [7:0] cluster_load_strb;
	logic [23:0] cluster_load_destination;
	logic [33:0] cluster_load_imem_address;
	logic [1:0] cluster_load_last;
	logic [1:0] cluster_commit_valid;
	logic [1:0] cluster_commit_ready;
	logic [1:0] cluster_commit_error;

	logic instruction_load_done;
	logic loader_program_start;
	logic loader_command_write_ready;
	logic loader_start_ready;
	logic loader_error;
	logic [5:0] loader_error_code;
	logic cluster_start_ready;
	logic cluster_started;
	logic cluster_frontends_ready;
	logic cluster_frontends_idle;
	logic cluster_fault;
	logic [5:0] cluster_fault_code;
	logic start_pending_q;
	logic load_request_active_q;
	logic program_done_q;
	logic west_commit_ready;
	logic east_commit_ready;
	logic internal_rst_ni;

	// Command Sequencer transaction and control-command outputs.
	logic command_transaction_valid;
	logic command_transaction_ready;
	logic [63:0] command_transaction_source_address;
	logic [31:0] command_transaction_byte_count;
	logic [1:0] command_transaction_scope;
	logic [11:0] command_transaction_destination;
	logic [1:0] command_transaction_format;
	logic [16:0] command_transaction_imem_base_address;
	logic command_transaction_image_first;
	logic command_transaction_image_last;
	logic [15:0] command_transaction_expected_word_count;
	logic [7:0] command_transaction_dma_id;
	logic command_commit_valid;
	logic command_commit_ready;
	logic [1:0] command_commit_scope;
	logic [11:0] command_commit_destination;
	logic command_done;
	logic command_fault;
	logic [5:0] command_fault_code;

	// Program Transfer emits complete Program Words into Distribution ingress.
	logic transfer_word_valid;
	logic transfer_word_ready;
	logic [127:0] transfer_word_data;
	logic [3:0] transfer_word_strb;
	logic [1:0] transfer_word_scope;
	logic [11:0] transfer_word_destination;
	logic [16:0] transfer_word_imem_address;
	logic transfer_word_last;
	logic transfer_idle;
	logic transfer_fault;
	logic [5:0] transfer_fault_code;

	// PRIME descriptors are retained by the lifecycle controller until all
	// Program Words and matching WRITE acknowledgements have retired.
	logic prime_enqueue_valid;
	logic prime_enqueue_ready;
	logic [13:0] prime_enqueue_data;
	logic prime_dequeue_valid;
	logic prime_dequeue_ready;
	logic [13:0] prime_dequeue_data;
	logic [1:0] prime_dequeue_scope;
	logic [11:0] prime_dequeue_destination;
	logic [$clog2(32+1)-1:0] prime_fifo_level;
	logic prime_select_w;

	logic distribution_west_valid;
	logic distribution_west_ready;
	logic [PROGRAM_LOAD_CONTROL_WIDTH-1:0] distribution_west_control;
	logic [127:0] distribution_west_data;
	logic [3:0] distribution_west_strb;
	logic [11:0] distribution_west_destination;
	logic [16:0] distribution_west_imem_address;
	logic distribution_west_last;
	logic distribution_east_valid;
	logic distribution_east_ready;
	logic [PROGRAM_LOAD_CONTROL_WIDTH-1:0] distribution_east_control;
	logic [127:0] distribution_east_data;
	logic [3:0] distribution_east_strb;
	logic [11:0] distribution_east_destination;
	logic [16:0] distribution_east_imem_address;
	logic distribution_east_last;
	logic distribution_idle;
	logic distribution_fault;
	logic [5:0] distribution_fault_code;

	logic west_commit_enqueue_ready;
	logic west_commit_expected_valid;
	logic west_commit_expected_pop;
	logic [$clog2(16+1)-1:0] west_commit_level;
	logic east_commit_enqueue_ready;
	logic east_commit_expected_valid;
	logic east_commit_expected_pop;
	logic [$clog2(16+1)-1:0] east_commit_level;
	logic west_bus_fire;
	logic east_bus_fire;
	logic west_commit_fire;
	logic east_commit_fire;
	logic west_commit_good_w;
	logic east_commit_good_w;
	logic commit_fault_w;
	logic load_pipeline_idle_w;
	logic instruction_load_done_q;
	logic controller_fault_q;
	logic [5:0] controller_fault_code_q;

	initial begin
		if(MEM_IMEM_DEPTH > 131072)begin
			$error("MEM subsystem iMEM exceeds the 17-bit Program Load address contract");
		end
		if(MXM_IMEM_DEPTH > 65536)begin
			$error("MXM subsystem iMEM exceeds the CMODEL capacity");
		end
	end

	assign internal_rst_ni = rst_ni && !program_reset_i;

	// Destination already uses the physical endpoint namespace: 0 is East and 1 is West.
	// The loader scope remains two bits only so the lower-level BOTH path can be preserved.
	always_comb begin
		command_scope_w = command_write_destination_i[PROGRAM_DESTINATION_HEMISPHERE_BIT] ?
			PROGRAM_SCOPE_WEST : PROGRAM_SCOPE_EAST;
		command_target_kind_w = command_write_destination_i[
			PROGRAM_DESTINATION_KIND_MSB:PROGRAM_DESTINATION_KIND_LSB];
		command_target_index_w = command_write_destination_i[
			PROGRAM_DESTINATION_INDEX_MSB:PROGRAM_DESTINATION_INDEX_LSB];
		command_global_target_w = command_target_index_w;
		command_target_valid_w = 1'b0;
		case(command_target_kind_w)
			PROGRAM_TARGET_MEM: begin
				if(command_target_index_w < lpu_pkg::MEM_BANKS_PER_HEMISPHERE)begin
					command_target_valid_w = 1'b1;
					if(command_write_destination_i[PROGRAM_DESTINATION_HEMISPHERE_BIT] ==
						PROGRAM_HEMISPHERE_WEST)begin
						command_global_target_w = command_target_index_w +
							lpu_pkg::MEM_BANKS_PER_HEMISPHERE;
					end
				end
			end
			PROGRAM_TARGET_MXM_LOAD,
			PROGRAM_TARGET_MXM_DEQUANT,
			PROGRAM_TARGET_MXM_COMPUTE: begin
				if(command_target_index_w < 8'd2)begin
					command_target_valid_w = 1'b1;
					if(command_write_destination_i[PROGRAM_DESTINATION_HEMISPHERE_BIT] ==
						PROGRAM_HEMISPHERE_WEST)begin
						command_global_target_w = command_target_index_w + 8'd2;
					end
				end
			end
			default: command_target_valid_w = 1'b0;
		endcase
	end

	assign command_write_ready_o = loader_command_write_ready && !load_request_active_q &&
		!descriptor_fault_q;
	assign command_write_fire = command_write_valid_i && command_write_ready_o;
	assign descriptor_invalid_w = command_write_fire &&
		(command_write_opcode_i == PROGRAM_LOADER_LOAD_IMEM) &&
		(!command_target_valid_w || (command_write_encoding_mode_i != PROGRAM_ENCODING_MACRO) ||
		 (command_write_byte_count_i == 0) ||
		 ((command_target_kind_w == PROGRAM_TARGET_MEM) &&
		  ((command_write_format_i != PROGRAM_FORMAT_96) ||
		   ((command_write_byte_count_i % 12) != 0) ||
		   (command_write_expected_word_count_i != command_write_byte_count_i / 12) ||
		   ({1'b0, command_write_imem_base_address_i} + command_write_expected_word_count_i > MEM_IMEM_DEPTH))) ||
		 (((command_target_kind_w == PROGRAM_TARGET_MXM_LOAD) ||
		   (command_target_kind_w == PROGRAM_TARGET_MXM_DEQUANT) ||
		   (command_target_kind_w == PROGRAM_TARGET_MXM_COMPUTE)) &&
		  ((command_write_format_i != PROGRAM_FORMAT_128) ||
		   ((command_write_byte_count_i % 16) != 0) ||
		   (command_write_expected_word_count_i != command_write_byte_count_i / 16) ||
		   ({1'b0, command_write_imem_base_address_i} + command_write_expected_word_count_i > MXM_IMEM_DEPTH))));

	always_comb begin
		descriptor_duplicate_w = 1'b0;
		if(command_write_fire && (command_write_opcode_i == PROGRAM_LOADER_LOAD_IMEM) && command_target_valid_w)begin
			case(command_target_kind_w)
				PROGRAM_TARGET_MEM: descriptor_duplicate_w = mem_target_seen_q[command_global_target_w];
				PROGRAM_TARGET_MXM_LOAD: descriptor_duplicate_w = mxm_load_target_seen_q[command_global_target_w[1:0]];
				PROGRAM_TARGET_MXM_DEQUANT: descriptor_duplicate_w = mxm_dequant_target_seen_q[command_global_target_w[1:0]];
				PROGRAM_TARGET_MXM_COMPUTE: descriptor_duplicate_w = mxm_compute_target_seen_q[command_global_target_w[1:0]];
				default: descriptor_duplicate_w = 1'b0;
			endcase
		end
	end

	assign cluster_load_valid = {west_load_valid, east_load_valid};
	assign {west_load_ready, east_load_ready} = cluster_load_ready;
	assign cluster_load_control = {west_load_control, east_load_control};
	assign cluster_load_data = {west_load_data, east_load_data};
	assign cluster_load_strb = {west_load_strb, east_load_strb};
	assign cluster_load_destination = {west_load_destination, east_load_destination};
	assign cluster_load_imem_address = {west_load_imem_address, east_load_imem_address};
	assign cluster_load_last = {west_load_last, east_load_last};
	assign cluster_commit_ready = {west_commit_ready, east_commit_ready};
	assign endpoint_load_valid_o = cluster_load_valid;
	assign cluster_load_ready = endpoint_load_ready_i;
	assign endpoint_load_control_o = cluster_load_control;
	assign endpoint_load_data_o = cluster_load_data;
	assign endpoint_load_strb_o = cluster_load_strb;
	assign endpoint_load_destination_o = cluster_load_destination;
	assign endpoint_load_imem_address_o = cluster_load_imem_address;
	assign endpoint_load_last_o = cluster_load_last;
	assign cluster_commit_valid = endpoint_commit_valid_i;
	assign endpoint_commit_ready_o = cluster_commit_ready;
	assign cluster_commit_error = endpoint_commit_error_i;
	assign endpoint_program_start_o = loader_program_start;
	assign cluster_start_ready = endpoint_program_start_ready_i;
	assign cluster_started = endpoint_started_i;
	assign cluster_frontends_ready = endpoint_frontends_ready_i;
	assign cluster_frontends_idle = endpoint_frontends_idle_i;
	assign cluster_fault = endpoint_fault_i;
	assign cluster_fault_code = endpoint_fault_code_i;
	assign schedule_cycle_o = endpoint_schedule_cycle_i;

	assign program_start_ack_o = loader_program_start && cluster_start_ready;
	assign load_start_ready_o = loader_start_ready && !load_request_active_q && !descriptor_fault_q;
	assign program_load_complete_o = instruction_load_done;
	assign program_ready_o = instruction_load_done && cluster_frontends_ready && !program_fault_o;
	assign program_running_o = cluster_started && !program_done_q && !program_fault_o;
	assign program_done_o = program_done_q;
	assign program_fault_o = descriptor_fault_q || loader_error || cluster_fault;
	assign program_fault_code_o = descriptor_fault_q ? PROGRAM_FAULT_DESCRIPTOR :
		(loader_error ? loader_error_code :
		(cluster_fault ? FRONTEND_FAULT_OFFSET + cluster_fault_code : PROGRAM_FAULT_NONE));

	lpu_program_command_sequencer #(
		.COMMAND_DEPTH(COMMAND_DEPTH),
		.COMMAND_ADDRESS_WIDTH(COMMAND_ADDRESS_WIDTH)
	) u_command_sequencer (
		.clk_i,
		.rst_ni(internal_rst_ni),
		.command_write_valid_i,
		.command_write_ready_o(loader_command_write_ready),
		.command_write_address_i,
		.command_write_opcode_i,
		.command_write_source_address_i,
		.command_write_byte_count_i,
		.command_write_scope_i(command_scope_w),
		.command_write_destination_i,
		.command_write_format_i,
		.command_write_imem_base_address_i,
		.command_write_image_first_i,
		.command_write_image_last_i,
		.command_write_expected_word_count_i,
		.command_write_jump_address_i,
		.start_valid_i(load_start_valid_i && load_start_ready_o),
		.start_ready_o(loader_start_ready),
		.start_command_count_i(load_start_command_count_i),
		.transaction_valid_o(command_transaction_valid),
		.transaction_ready_i(command_transaction_ready),
		.transaction_source_address_o(command_transaction_source_address),
		.transaction_byte_count_o(command_transaction_byte_count),
		.transaction_scope_o(command_transaction_scope),
		.transaction_destination_o(command_transaction_destination),
		.transaction_format_o(command_transaction_format),
		.transaction_imem_base_address_o(command_transaction_imem_base_address),
		.transaction_image_first_o(command_transaction_image_first),
		.transaction_image_last_o(command_transaction_image_last),
		.transaction_expected_word_count_o(command_transaction_expected_word_count),
		.transaction_dma_id_o(command_transaction_dma_id),
		.commit_valid_o(command_commit_valid),
		.commit_ready_i(command_commit_ready),
		.commit_scope_o(command_commit_scope),
		.commit_destination_o(command_commit_destination),
		.load_pipeline_idle_i(load_pipeline_idle_w),
		.command_pc_o(),
		.busy_o(),
		.done_o(command_done),
		.fault_o(command_fault),
		.fault_code_o(command_fault_code)
	);

	lpu_program_transfer_path #(
		.DMA_DATA_WIDTH(DMA_DATA_WIDTH),
		.IMEM_DEPTH(MEM_IMEM_DEPTH)
	) u_program_transfer (
		.clk_i,
		.rst_ni,
		.clear_i(program_reset_i),
		.transaction_valid_i(command_transaction_valid),
		.transaction_ready_o(command_transaction_ready),
		.transaction_source_address_i(command_transaction_source_address),
		.transaction_byte_count_i(command_transaction_byte_count),
		.transaction_scope_i(command_transaction_scope),
		.transaction_destination_i(command_transaction_destination),
		.transaction_format_i(command_transaction_format),
		.transaction_imem_base_address_i(command_transaction_imem_base_address),
		.transaction_image_first_i(command_transaction_image_first),
		.transaction_image_last_i(command_transaction_image_last),
		.transaction_expected_word_count_i(command_transaction_expected_word_count),
		.transaction_dma_id_i(command_transaction_dma_id),
		.dma_cmd_valid_o,
		.dma_cmd_ready_i,
		.dma_cmd_address_o,
		.dma_cmd_length_o,
		.dma_cmd_id_o,
		.dma_rsp_valid_i,
		.dma_rsp_ready_o,
		.dma_rsp_data_i,
		.dma_rsp_keep_i,
		.dma_rsp_last_i,
		.dma_rsp_id_i,
		.dma_rsp_error_i,
		.word_valid_o(transfer_word_valid),
		.word_ready_i(transfer_word_ready),
		.word_data_o(transfer_word_data),
		.word_strb_o(transfer_word_strb),
		.word_scope_o(transfer_word_scope),
		.word_destination_o(transfer_word_destination),
		.word_imem_address_o(transfer_word_imem_address),
		.word_last_o(transfer_word_last),
		.idle_o(transfer_idle),
		.generated_word_count_o(),
		.fault_o(transfer_fault),
		.fault_code_o(transfer_fault_code)
	);

	assign prime_enqueue_valid = command_commit_valid && load_pipeline_idle_w;
	assign command_commit_ready = prime_enqueue_valid && prime_enqueue_ready;
	assign prime_enqueue_data = {command_commit_scope, command_commit_destination};

	lpu_queue_fifo #(
		.DATA_WIDTH(14),
		.DEPTH(32)
	) u_prime_fifo (
		.clk_i,
		.rst_ni(internal_rst_ni),
		.enqueue_valid_i(prime_enqueue_valid),
		.enqueue_ready_o(prime_enqueue_ready),
		.enqueue_data_i(prime_enqueue_data),
		.dequeue_valid_o(prime_dequeue_valid),
		.dequeue_ready_i(prime_dequeue_ready),
		.dequeue_data_o(prime_dequeue_data),
		.level_o(prime_fifo_level)
	);

	assign {prime_dequeue_scope, prime_dequeue_destination} = prime_dequeue_data;
	assign prime_select_w = instruction_load_done_q && prime_dequeue_valid;

	lpu_program_distribution_ingress u_program_distribution_ingress (
		.clk_i,
		.rst_ni,
		.clear_i(program_reset_i),
		.word_valid_i(transfer_word_valid),
		.word_ready_o(transfer_word_ready),
		.word_data_i(transfer_word_data),
		.word_strb_i(transfer_word_strb),
		.word_scope_i(transfer_word_scope),
		.word_destination_i(transfer_word_destination),
		.word_imem_address_i(transfer_word_imem_address),
		.word_last_i(transfer_word_last),
		.prime_valid_i(prime_select_w),
		.prime_ready_o(prime_dequeue_ready),
		.prime_scope_i(prime_dequeue_scope),
		.prime_destination_i(prime_dequeue_destination),
		.west_valid_o(distribution_west_valid),
		.west_ready_i(distribution_west_ready),
		.west_control_o(distribution_west_control),
		.west_data_o(distribution_west_data),
		.west_strb_o(distribution_west_strb),
		.west_destination_o(distribution_west_destination),
		.west_imem_address_o(distribution_west_imem_address),
		.west_last_o(distribution_west_last),
		.east_valid_o(distribution_east_valid),
		.east_ready_i(distribution_east_ready),
		.east_control_o(distribution_east_control),
		.east_data_o(distribution_east_data),
		.east_strb_o(distribution_east_strb),
		.east_destination_o(distribution_east_destination),
		.east_imem_address_o(distribution_east_imem_address),
		.east_last_o(distribution_east_last),
		.idle_o(distribution_idle),
		.fault_o(distribution_fault),
		.fault_code_o(distribution_fault_code)
	);

	// Commit capacity is part of lifecycle control, so WRITE Records cannot
	// leave the ingress unless the matching expected-response token is stored.
	assign west_load_valid = distribution_west_valid &&
		((distribution_west_control != PROGRAM_LOAD_WRITE) || west_commit_enqueue_ready);
	assign distribution_west_ready = west_load_ready &&
		((distribution_west_control != PROGRAM_LOAD_WRITE) || west_commit_enqueue_ready);
	assign west_load_control = distribution_west_control;
	assign west_load_data = distribution_west_data;
	assign west_load_strb = distribution_west_strb;
	assign west_load_destination = distribution_west_destination;
	assign west_load_imem_address = distribution_west_imem_address;
	assign west_load_last = distribution_west_last;
	assign west_bus_fire = west_load_valid && west_load_ready;

	assign east_load_valid = distribution_east_valid &&
		((distribution_east_control != PROGRAM_LOAD_WRITE) || east_commit_enqueue_ready);
	assign distribution_east_ready = east_load_ready &&
		((distribution_east_control != PROGRAM_LOAD_WRITE) || east_commit_enqueue_ready);
	assign east_load_control = distribution_east_control;
	assign east_load_data = distribution_east_data;
	assign east_load_strb = distribution_east_strb;
	assign east_load_destination = distribution_east_destination;
	assign east_load_imem_address = distribution_east_imem_address;
	assign east_load_last = distribution_east_last;
	assign east_bus_fire = east_load_valid && east_load_ready;

	lpu_queue_fifo #(
		.DATA_WIDTH(1),
		.DEPTH(16)
	) u_west_commit_fifo (
		.clk_i,
		.rst_ni(internal_rst_ni),
		.enqueue_valid_i(west_bus_fire && (west_load_control == PROGRAM_LOAD_WRITE)),
		.enqueue_ready_o(west_commit_enqueue_ready),
		.enqueue_data_i(1'b1),
		.dequeue_valid_o(west_commit_expected_valid),
		.dequeue_ready_i(west_commit_expected_pop),
		.dequeue_data_o(),
		.level_o(west_commit_level)
	);

	lpu_queue_fifo #(
		.DATA_WIDTH(1),
		.DEPTH(16)
	) u_east_commit_fifo (
		.clk_i,
		.rst_ni(internal_rst_ni),
		.enqueue_valid_i(east_bus_fire && (east_load_control == PROGRAM_LOAD_WRITE)),
		.enqueue_ready_o(east_commit_enqueue_ready),
		.enqueue_data_i(1'b1),
		.dequeue_valid_o(east_commit_expected_valid),
		.dequeue_ready_i(east_commit_expected_pop),
		.dequeue_data_o(),
		.level_o(east_commit_level)
	);

	assign west_commit_ready = internal_rst_ni && !controller_fault_q;
	assign east_commit_ready = internal_rst_ni && !controller_fault_q;
	assign west_commit_fire = cluster_commit_valid[1] && west_commit_ready;
	assign east_commit_fire = cluster_commit_valid[0] && east_commit_ready;
	assign west_commit_good_w = west_commit_fire && west_commit_expected_valid &&
		!cluster_commit_error[1];
	assign east_commit_good_w = east_commit_fire && east_commit_expected_valid &&
		!cluster_commit_error[0];
	assign west_commit_expected_pop = west_commit_good_w;
	assign east_commit_expected_pop = east_commit_good_w;
	assign commit_fault_w = (west_commit_fire && !west_commit_good_w) ||
		(east_commit_fire && !east_commit_good_w);

	assign load_pipeline_idle_w = transfer_idle && distribution_idle &&
		(west_commit_level == '0) && (east_commit_level == '0);
	assign instruction_load_done = instruction_load_done_q;
	assign loader_program_start = instruction_load_done_q &&
		(start_pending_q && dependencies_ready_i) && cluster_frontends_ready && !loader_error;
	assign loader_error = controller_fault_q || command_fault || transfer_fault ||
		distribution_fault || commit_fault_w;
	assign loader_error_code = controller_fault_q ? controller_fault_code_q :
		(command_fault ? command_fault_code :
		(transfer_fault ? transfer_fault_code :
		(distribution_fault ? distribution_fault_code :
		(commit_fault_w ? PROGRAM_FAULT_COMMIT : PROGRAM_FAULT_NONE))));

	// Completion is reached only after END and every buffered WRITE/acknowledgement retires.
	always_ff @(posedge clk_i or negedge internal_rst_ni) begin
		if(!internal_rst_ni)begin
			instruction_load_done_q <= 1'b0;
		end
		else if(command_done && load_pipeline_idle_w && !loader_error)begin
			instruction_load_done_q <= 1'b1;
		end
	end

	// Retain the first lifecycle fault so a later ready transition cannot hide it.
	always_ff @(posedge clk_i or negedge internal_rst_ni) begin
		if(!internal_rst_ni)begin
			controller_fault_q <= 1'b0;
			controller_fault_code_q <= PROGRAM_FAULT_NONE;
		end
		else if(!controller_fault_q)begin
			if(command_fault)begin
				controller_fault_q <= 1'b1;
				controller_fault_code_q <= command_fault_code;
			end
			else if(transfer_fault)begin
				controller_fault_q <= 1'b1;
				controller_fault_code_q <= transfer_fault_code;
			end
			else if(distribution_fault)begin
				controller_fault_q <= 1'b1;
				controller_fault_code_q <= distribution_fault_code;
			end
			else if(commit_fault_w)begin
				controller_fault_q <= 1'b1;
				controller_fault_code_q <= PROGRAM_FAULT_COMMIT;
			end
		end
	end

	// Early START is sticky, matching CMODEL; dependencies must still be high on the acceptance cycle.
	always_ff @(posedge clk_i or negedge rst_ni) begin
		if(!rst_ni)begin
			start_pending_q <= 1'b0;
			load_request_active_q <= 1'b0;
			program_done_q <= 1'b0;
		end
		else if(program_reset_i)begin
			start_pending_q <= 1'b0;
			load_request_active_q <= 1'b0;
			program_done_q <= 1'b0;
		end
		else begin
			if(load_start_valid_i && load_start_ready_o)begin
				load_request_active_q <= 1'b1;
			end
			if(program_start_request_i && !program_done_q)begin
				start_pending_q <= 1'b1;
			end
			if(program_start_ack_o)begin
				start_pending_q <= 1'b0;
			end
			if(cluster_started && cluster_frontends_idle)begin
				program_done_q <= 1'b1;
			end
		end
	end

	always_ff @(posedge clk_i or negedge rst_ni) begin
		if(!rst_ni)begin
			descriptor_fault_q <= 1'b0;
			mem_target_seen_q <= '0;
			mxm_load_target_seen_q <= '0;
			mxm_dequant_target_seen_q <= '0;
			mxm_compute_target_seen_q <= '0;
		end
		else if(program_reset_i)begin
			descriptor_fault_q <= 1'b0;
			mem_target_seen_q <= '0;
			mxm_load_target_seen_q <= '0;
			mxm_dequant_target_seen_q <= '0;
			mxm_compute_target_seen_q <= '0;
		end
		else begin
			if(descriptor_invalid_w || descriptor_duplicate_w)begin
				descriptor_fault_q <= 1'b1;
			end
			if(command_write_fire && (command_write_opcode_i == PROGRAM_LOADER_LOAD_IMEM) &&
				command_target_valid_w && !descriptor_invalid_w && !descriptor_duplicate_w)begin
				case(command_target_kind_w)
					PROGRAM_TARGET_MEM: mem_target_seen_q[command_global_target_w] <= 1'b1;
					PROGRAM_TARGET_MXM_LOAD: mxm_load_target_seen_q[command_global_target_w[1:0]] <= 1'b1;
					PROGRAM_TARGET_MXM_DEQUANT: mxm_dequant_target_seen_q[command_global_target_w[1:0]] <= 1'b1;
					PROGRAM_TARGET_MXM_COMPUTE: mxm_compute_target_seen_q[command_global_target_w[1:0]] <= 1'b1;
					default: mem_target_seen_q <= mem_target_seen_q;
				endcase
			end
		end
	end
endmodule
