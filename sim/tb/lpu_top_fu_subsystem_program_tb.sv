`timescale 1ns/1ps

module lpu_top_fu_subsystem_program_tb;
	import lpu_program_load_pkg::*;

	localparam integer COMMAND_DEPTH = 64;
	localparam integer COMMAND_ADDRESS_WIDTH = $clog2(COMMAND_DEPTH);
	localparam integer DMA_DATA_WIDTH = 256;
	localparam integer DMA_BYTES = DMA_DATA_WIDTH / 8;
	localparam logic [1:0] PROGRAM_ENCODING_MACRO = 2'd0;
	localparam logic [1:0] PROGRAM_ENCODING_FU3D = 2'd1;
	localparam logic [95:0] MEM_WORD_0 = 96'h00000000_00000000_00000025;
	localparam logic [95:0] MEM_WORD_1 = 96'h00303200_00000180_02000021;
	localparam logic [95:0] MEM_WORD_2 = 96'h00000000_00000000_00000400;
	localparam logic [127:0] MXM_CONTROL = 128'h00000000000000000000000000000015;
	localparam logic [127:0] MXM_LOAD = 128'h00000000000000000000008000000018;
	localparam logic [127:0] MXM_COMPUTE = 128'h00000000000000000000380000000020;
	localparam logic [127:0] MXM_DEQUANT = 128'h00000000000000000000004000000028;

	logic clk;
	logic rst_n;
	logic program_reset;
	logic program_cmd_write_valid;
	logic program_cmd_write_ready;
	logic [COMMAND_ADDRESS_WIDTH-1:0] program_cmd_write_address;
	logic [2:0] program_cmd_write_opcode;
	logic [63:0] program_cmd_write_source_address;
	logic [31:0] program_cmd_write_byte_count;
	logic [PROGRAM_DESTINATION_WIDTH-1:0] program_cmd_write_destination;
	logic [1:0] program_cmd_write_format;
	logic [1:0] program_cmd_write_encoding_mode;
	logic [16:0] program_cmd_write_imem_base_address;
	logic program_cmd_write_image_first;
	logic program_cmd_write_image_last;
	logic [15:0] program_cmd_write_expected_word_count;
	logic [COMMAND_ADDRESS_WIDTH-1:0] program_cmd_write_jump_address;
	logic program_load_start_valid;
	logic program_load_start_ready;
	logic [COMMAND_ADDRESS_WIDTH:0] program_load_start_command_count;
	logic program_ddr_read_req_valid;
	logic program_ddr_read_req_ready;
	logic [63:0] program_ddr_read_req_address;
	logic [31:0] program_ddr_read_req_length;
	logic [7:0] program_ddr_read_req_id;
	logic program_ddr_read_rsp_valid;
	logic program_ddr_read_rsp_ready;
	logic [DMA_DATA_WIDTH-1:0] program_ddr_read_rsp_data;
	logic [DMA_BYTES-1:0] program_ddr_read_rsp_keep;
	logic program_ddr_read_rsp_last;
	logic [7:0] program_ddr_read_rsp_id;
	logic program_ddr_read_rsp_error;
	logic program_start_request;
	logic program_dependencies_ready;
	logic program_start_ack;
	logic program_load_complete;
	logic program_ready;
	logic program_running;
	logic program_done;
	logic program_fault;
	logic [5:0] program_fault_code;
	logic [31:0] program_schedule_cycle;
	logic [63:0] physical_cycle;

	// Canonical trace aliases. PRE_POSEDGE samples the transfer selected for the
	// current cycle; POST_POSEDGE samples registered state after NBA updates;
	// POST_COMB samples combinational outputs after they settle.
	logic program_cmd_write_fire;
	logic ddr_read_req_fire;
	logic ddr_read_rsp_fire;
	logic load_distribute_fire;
	logic mem_program_fire;
	logic imem_load_fire;
	logic imem_read_req_fire;
	logic imem_read_rsp_fire;
	logic word_fifo_enqueue_fire;
	logic word_fifo_dequeue_fire;
	logic [2:0] word_fifo_level;
	logic context_fifo_enqueue_fire;
	logic context_fifo_dequeue_fire;
	logic [2:0] context_fifo_level;
	logic macro_context_fire;
	logic mem_issue_valid;
	logic mem_issue_ready;
	logic mem_issue_fire;
	logic [lpu_pkg::MEM_INSTRUCTION_WIDTH-1:0] mem_issue_instruction;
	logic [31:0] mem_issue_cycle;
	logic mem_fault;

	integer next_command;
	integer checks;
	integer timeout;
	integer start_ack_count;
	integer physical_clock_edges;
	integer trace_fd;
	integer stimulus_fd;
	integer diagnostic_fd;
	integer r1_trace_fd;
	integer r1_stimulus_fd;
	string trace_path;
	string stimulus_path;
	string diagnostic_path;
	string r1_trace_path;
	string r1_stimulus_path;
	string case_id;
	bit r1_only;
	bit r2_only;
	bit r3_only;
	bit r4_only;
	bit r1_trace_enable;
	integer r1_expected_rows;
	integer r1_cycle;
	integer r1_trace_rows;
	integer r1_command_write_count;
	integer r1_load_start_count;
	integer r1_load_txn_count;
	integer r1_prime_count;
	integer r1_config_enqueue_count;
	integer r1_config_dequeue_count;
	integer r1_dma_request_count;
	integer r1_dma_final_response_count;
	integer r1_mem_program_count;
	integer r1_mem_fetched_words;
	integer r1_mem_decoded_contexts;
	integer r1_mem_issued_count;
	logic [7:0] r1_dma_request_id;
	logic [63:0] r1_dma_request_address;
	logic [31:0] r1_dma_request_length;
	logic r1_load_hold_valid;
	logic r1_config_hold_valid;
	logic [154:0] r1_load_hold_payload;
	logic [154:0] r1_config_hold_payload;
	logic [154:0] r1_load_txn_payload;
	logic [154:0] r1_config_dequeue_payload;
	logic r1_load_start_fire;
	logic r1_load_txn_fire;
	logic r1_prime_fire;
	logic r1_config_enqueue_fire;
	logic r1_config_dequeue_fire;
	logic r1_dma_final_response;
	logic r1_mem_program_write_valid;
	logic r1_mem_program_write_fire;
	logic r2_dma_rsp_fire;
	logic r2_reasm_word_fire;
	logic r2_word_fifo_dequeue_fire;
	logic r2_reasm_image_complete;

	assign program_cmd_write_fire = program_cmd_write_valid && program_cmd_write_ready;
	assign ddr_read_req_fire = program_ddr_read_req_valid && program_ddr_read_req_ready;
	assign ddr_read_rsp_fire = program_ddr_read_rsp_valid && program_ddr_read_rsp_ready;
	assign load_distribute_fire = u_dut.load_distribute_valid && u_dut.load_distribute_ready;
	assign mem_program_fire = u_dut.mem_program_valid[0] && u_dut.mem_program_ready[0];
	assign imem_load_fire = u_dut.u_fu_subsystems.gen_hemisphere[0].u_mem_subsystem.
		gen_bank_frontend[0].u_frontend.load_fire;
	assign imem_read_req_fire =
		u_dut.u_fu_subsystems.gen_hemisphere[0].u_mem_subsystem.
		gen_bank_frontend[0].u_frontend.imem_read_req_valid &&
		u_dut.u_fu_subsystems.gen_hemisphere[0].u_mem_subsystem.
		gen_bank_frontend[0].u_frontend.imem_read_req_ready;
	assign imem_read_rsp_fire =
		u_dut.u_fu_subsystems.gen_hemisphere[0].u_mem_subsystem.
		gen_bank_frontend[0].u_frontend.imem_read_rsp_valid &&
		u_dut.u_fu_subsystems.gen_hemisphere[0].u_mem_subsystem.
		gen_bank_frontend[0].u_frontend.imem_read_rsp_ready;
	assign word_fifo_enqueue_fire =
		u_dut.u_fu_subsystems.gen_hemisphere[0].u_mem_subsystem.
		gen_bank_frontend[0].u_frontend.u_macro_frontend.word_fifo_enqueue_valid &&
		u_dut.u_fu_subsystems.gen_hemisphere[0].u_mem_subsystem.
		gen_bank_frontend[0].u_frontend.u_macro_frontend.word_fifo_enqueue_ready;
	assign word_fifo_dequeue_fire =
		u_dut.u_fu_subsystems.gen_hemisphere[0].u_mem_subsystem.
		gen_bank_frontend[0].u_frontend.u_macro_frontend.word_fifo_valid &&
		u_dut.u_fu_subsystems.gen_hemisphere[0].u_mem_subsystem.
		gen_bank_frontend[0].u_frontend.u_macro_frontend.word_fifo_ready;
	assign word_fifo_level = u_dut.u_fu_subsystems.gen_hemisphere[0].u_mem_subsystem.
		gen_bank_frontend[0].u_frontend.u_macro_frontend.word_fifo_level_o;
	assign context_fifo_enqueue_fire =
		u_dut.u_fu_subsystems.gen_hemisphere[0].u_mem_subsystem.
		gen_bank_frontend[0].u_frontend.u_macro_frontend.decoder_context_valid &&
		u_dut.u_fu_subsystems.gen_hemisphere[0].u_mem_subsystem.
		gen_bank_frontend[0].u_frontend.u_macro_frontend.decoder_context_ready;
	assign context_fifo_dequeue_fire =
		u_dut.u_fu_subsystems.gen_hemisphere[0].u_mem_subsystem.
		gen_bank_frontend[0].u_frontend.u_macro_frontend.context_fifo_valid &&
		u_dut.u_fu_subsystems.gen_hemisphere[0].u_mem_subsystem.
		gen_bank_frontend[0].u_frontend.u_macro_frontend.context_fifo_ready;
	assign context_fifo_level = u_dut.u_fu_subsystems.gen_hemisphere[0].u_mem_subsystem.
		gen_bank_frontend[0].u_frontend.u_macro_frontend.context_fifo_level_o;
	assign macro_context_fire = context_fifo_dequeue_fire;
	assign mem_issue_valid = u_dut.local_mem_issue_valid[0];
	assign mem_issue_ready = u_dut.u_fu_subsystems.gen_hemisphere[0].u_mem_subsystem.
		execution_issue_ready[0];
	assign mem_issue_fire = mem_issue_valid && mem_issue_ready;
	assign mem_issue_instruction = u_dut.local_mem_issue_instruction[
		0+:lpu_pkg::MEM_INSTRUCTION_WIDTH];
	assign mem_issue_cycle = u_dut.local_mem_issue_cycle[0+:32];
	assign mem_fault = u_dut.u_fu_subsystems.gen_hemisphere[0].u_mem_subsystem.
		gen_bank_frontend[0].u_frontend.fault_o;
	assign r1_load_start_fire = program_load_start_valid && program_load_start_ready;
	assign r1_load_txn_fire = u_dut.u_program_load_system.ctrl_load_txn_valid &&
		u_dut.u_program_load_system.ctrl_load_txn_ready;
	assign r1_prime_fire = u_dut.u_program_load_system.ctrl_prime_valid &&
		u_dut.u_program_load_system.ctrl_prime_ready;
	assign r1_config_enqueue_fire =
		u_dut.u_program_load_system.u_program_load_path.config_enqueue_valid &&
		u_dut.u_program_load_system.u_program_load_path.config_enqueue_ready;
	assign r1_config_dequeue_fire =
		u_dut.u_program_load_system.u_program_load_path.config_dequeue_valid &&
		u_dut.u_program_load_system.u_program_load_path.config_dequeue_ready;
	assign r1_dma_final_response =
		u_dut.u_program_load_system.u_program_load_path.reasm_rsp_valid &&
		u_dut.u_program_load_system.u_program_load_path.reasm_rsp_ready &&
		u_dut.u_program_load_system.u_program_load_path.reasm_rsp_last;
	assign r2_dma_rsp_fire =
		u_dut.u_program_load_system.u_program_load_path.reasm_rsp_valid &&
		u_dut.u_program_load_system.u_program_load_path.reasm_rsp_ready;
	assign r2_reasm_word_fire =
		u_dut.u_program_load_system.u_program_load_path.word_fifo_enqueue_valid &&
		u_dut.u_program_load_system.u_program_load_path.word_fifo_enqueue_ready;
	assign r2_word_fifo_dequeue_fire =
		u_dut.u_program_load_system.u_program_load_path.load_word_valid_o &&
		u_dut.u_program_load_system.u_program_load_path.load_word_ready_i;
	assign r2_reasm_image_complete = r2_reasm_word_fire &&
		u_dut.u_program_load_system.u_program_load_path.word_fifo_enqueue_last;
	assign r1_mem_program_write_valid = u_dut.mem_program_valid[0] &&
		(u_dut.mem_program_control[0+:PROGRAM_LOAD_CONTROL_WIDTH] == PROGRAM_LOAD_WRITE);
	assign r1_mem_program_write_fire = r1_mem_program_write_valid && u_dut.mem_program_ready[0];
	assign r1_load_txn_payload = {
		u_dut.u_program_load_system.ctrl_load_txn_source_address,
		u_dut.u_program_load_system.ctrl_load_txn_byte_count,
		u_dut.u_program_load_system.ctrl_load_txn_scope,
		u_dut.u_program_load_system.ctrl_load_txn_destination,
		u_dut.u_program_load_system.ctrl_load_txn_format,
		u_dut.u_program_load_system.ctrl_load_txn_imem_base_address,
		u_dut.u_program_load_system.ctrl_load_txn_image_first,
		u_dut.u_program_load_system.ctrl_load_txn_image_last,
		u_dut.u_program_load_system.ctrl_load_txn_expected_word_count,
		u_dut.u_program_load_system.ctrl_load_txn_dma_id
	};
	assign r1_config_dequeue_payload = {
		u_dut.u_program_load_system.u_program_load_path.u_config_fifo.dequeue_source_address_o,
		u_dut.u_program_load_system.u_program_load_path.config_byte_count,
		u_dut.u_program_load_system.u_program_load_path.config_scope,
		u_dut.u_program_load_system.u_program_load_path.config_destination,
		u_dut.u_program_load_system.u_program_load_path.config_format,
		u_dut.u_program_load_system.u_program_load_path.config_imem_base_address,
		u_dut.u_program_load_system.u_program_load_path.config_image_first,
		u_dut.u_program_load_system.u_program_load_path.config_image_last,
		u_dut.u_program_load_system.u_program_load_path.config_expected_word_count,
		u_dut.u_program_load_system.u_program_load_path.config_dma_id
	};

	function automatic bit known_high(input logic value);
		known_high = value === 1'b1;
	endfunction

	// Append one complete Program Distribution channel to the shared CSV schema.
	task automatic write_r3_channel_header(input string prefix);
		begin
			$fwrite(r1_trace_fd, "%s_valid,%s_ready,%s_fire,%s_control,%s_data,%s_strb,%s_scope,%s_destination,%s_address,%s_last,",
				prefix, prefix, prefix, prefix, prefix, prefix, prefix, prefix, prefix, prefix);
		end
	endtask

	// Append one PRE_POSEDGE Program Distribution channel sample.
	task automatic write_r3_channel_row(
		input logic valid,
		input logic ready,
		input logic [PROGRAM_LOAD_CONTROL_WIDTH-1:0] control,
		input logic [127:0] data,
		input logic [3:0] strb,
		input logic [1:0] scope,
		input logic [PROGRAM_DESTINATION_WIDTH-1:0] destination,
		input logic [16:0] address,
		input logic last
	);
		begin
			$fwrite(r1_trace_fd, "%0d,%0d,%0d,%0d,%032h,%0d,%0d,%0d,%0d,%0d,",
				known_high(valid), known_high(ready), known_high(valid && ready), control,
				data, strb, scope, destination, address, known_high(last));
		end
	endtask

	// Append the MEM Bank-0 Program Endpoint and local-iMEM effect contract.
	task automatic write_r4_mem_header;
		begin
			$fdisplay(r1_trace_fd, "r4_mem0_endpoint_valid,r4_mem0_endpoint_ready,r4_mem0_endpoint_fire,r4_mem0_endpoint_control,r4_mem0_endpoint_data,r4_mem0_endpoint_strb,r4_mem0_endpoint_destination,r4_mem0_endpoint_address,r4_mem0_endpoint_last,r4_mem0_endpoint_error,r4_mem0_destination_legal,r4_mem0_write_fire,r4_mem0_prime_fire,r4_mem0_frontend_load_valid,r4_mem0_frontend_load_ready,r4_mem0_frontend_load_fire,r4_mem0_frontend_prime_valid,r4_mem0_frontend_prime_ready,r4_mem0_frontend_prime_fire,r4_mem0_imem_write_fire,r4_mem0_imem_write_address,r4_mem0_imem_write_data,r4_mem0_configured,r4_mem0_last_seen,r4_mem0_load_base,r4_mem0_next_address,r4_mem0_word_count,r4_mem0_prime_started");
		end
	endtask

	// Sample the accepted Endpoint record and the same-cycle local-iMEM write effect.
	task automatic write_r4_mem_row;
		begin
			$fdisplay(r1_trace_fd, "%0d,%0d,%0d,%0d,%032h,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%024h,%0d,%0d,%0d,%0d,%0d,%0d",
				known_high(u_dut.mem_program_valid[0]),
				known_high(u_dut.mem_program_ready[0]),
				known_high(u_dut.mem_program_valid[0] && u_dut.mem_program_ready[0]),
				u_dut.mem_program_control[0+:PROGRAM_LOAD_CONTROL_WIDTH],
				u_dut.mem_program_data[0+:128], u_dut.mem_program_strb[0+:4],
				u_dut.mem_program_destination[0+:PROGRAM_DESTINATION_WIDTH],
				u_dut.mem_program_imem_address[0+:17], known_high(u_dut.mem_program_last[0]),
				known_high(u_dut.mem_program_error[0]),
				known_high(u_dut.u_fu_subsystems.gen_hemisphere[0].u_mem_subsystem.destination_legal_w[0]),
				known_high(u_dut.u_fu_subsystems.gen_hemisphere[0].u_mem_subsystem.write_fire_w[0]),
				known_high(u_dut.u_fu_subsystems.gen_hemisphere[0].u_mem_subsystem.prime_fire_w[0]),
				known_high(u_dut.u_fu_subsystems.gen_hemisphere[0].u_mem_subsystem.gen_bank_frontend[0].u_frontend.load_valid_i),
				known_high(u_dut.u_fu_subsystems.gen_hemisphere[0].u_mem_subsystem.gen_bank_frontend[0].u_frontend.load_ready_o),
				known_high(u_dut.u_fu_subsystems.gen_hemisphere[0].u_mem_subsystem.gen_bank_frontend[0].u_frontend.load_fire),
				known_high(u_dut.u_fu_subsystems.gen_hemisphere[0].u_mem_subsystem.gen_bank_frontend[0].u_frontend.prime_valid_i),
				known_high(u_dut.u_fu_subsystems.gen_hemisphere[0].u_mem_subsystem.gen_bank_frontend[0].u_frontend.prime_ready_o),
				known_high(u_dut.u_fu_subsystems.gen_hemisphere[0].u_mem_subsystem.gen_bank_frontend[0].u_frontend.prime_fire),
				known_high(u_dut.u_fu_subsystems.gen_hemisphere[0].u_mem_subsystem.gen_bank_frontend[0].u_frontend.u_imem.load_valid_i &&
					u_dut.u_fu_subsystems.gen_hemisphere[0].u_mem_subsystem.gen_bank_frontend[0].u_frontend.u_imem.load_ready_o),
				u_dut.u_fu_subsystems.gen_hemisphere[0].u_mem_subsystem.gen_bank_frontend[0].u_frontend.u_imem.load_address_i,
				u_dut.u_fu_subsystems.gen_hemisphere[0].u_mem_subsystem.gen_bank_frontend[0].u_frontend.u_imem.load_data_i,
				known_high(u_dut.u_fu_subsystems.gen_hemisphere[0].u_mem_subsystem.gen_bank_frontend[0].u_frontend.configured_q),
				known_high(u_dut.u_fu_subsystems.gen_hemisphere[0].u_mem_subsystem.gen_bank_frontend[0].u_frontend.load_last_seen_q),
				u_dut.u_fu_subsystems.gen_hemisphere[0].u_mem_subsystem.gen_bank_frontend[0].u_frontend.load_base_q,
				u_dut.u_fu_subsystems.gen_hemisphere[0].u_mem_subsystem.gen_bank_frontend[0].u_frontend.next_load_address_q,
				u_dut.u_fu_subsystems.gen_hemisphere[0].u_mem_subsystem.gen_bank_frontend[0].u_frontend.load_word_count_q,
				known_high(u_dut.u_fu_subsystems.gen_hemisphere[0].u_mem_subsystem.gen_bank_frontend[0].u_frontend.prime_started_q));
		end
	endtask

	// Emit the canonical R1/R2 columns plus the R3 Program Distribution boundaries.
	task automatic write_r1_header;
		begin
			$fwrite(r1_trace_fd, "cycle,phase,cmd_write_valid,cmd_write_ready,cmd_write_fire,cmd_write_address,cmd_write_opcode,cmd_write_source,cmd_write_bytes,cmd_write_destination,cmd_write_format,cmd_write_encoding,cmd_write_imem_base,cmd_write_first,cmd_write_last,cmd_write_expected_words,cmd_write_jump,");
			$fwrite(r1_trace_fd, "load_start_valid,load_start_ready,load_start_fire,load_start_count,load_txn_valid,load_txn_ready,load_txn_fire,load_txn_source,load_txn_bytes,load_txn_scope,load_txn_destination,load_txn_format,load_txn_imem_base,load_txn_first,load_txn_last,load_txn_expected_words,load_txn_dma_id,prime_valid,prime_ready,prime_fire,prime_scope,prime_destination,");
			$fwrite(r1_trace_fd, "command_pc,command_busy,command_done,command_fault,command_fault_code,config_enq_valid,config_enq_ready,config_enq_fire,config_enq_source,config_enq_bytes,config_enq_scope,config_enq_destination,config_enq_format,config_enq_imem_base,config_enq_first,config_enq_last,config_enq_expected_words,config_enq_dma_id,");
			$fwrite(r1_trace_fd, "config_deq_valid,config_deq_ready,config_deq_fire,config_deq_source,config_deq_bytes,config_deq_scope,config_deq_destination,config_deq_format,config_deq_imem_base,config_deq_first,config_deq_last,config_deq_expected_words,config_deq_dma_id,config_level,config_empty,config_full,");
			$fwrite(r1_trace_fd, "canonical_path,load_request_active,load_pipeline_idle,distribution_idle,load_complete,program_ready,program_running,program_done,program_fault,program_fault_code,dma_final_response,dma_response_id,");
			$fwrite(r1_trace_fd, "ddr_rsp_valid,ddr_rsp_ready,ddr_rsp_fire,ddr_rsp_keep,ddr_rsp_last,ddr_rsp_id,ddr_rsp_error,ddr_rsp_data,dma_rsp_valid,dma_rsp_ready,dma_rsp_fire,dma_rsp_keep,dma_rsp_last,dma_rsp_id,dma_rsp_error,dma_rsp_data,dma_response_fifo_level,");
			$fwrite(r1_trace_fd, "reasm_buffer_count,reasm_image_active,reasm_image_last_seen,reasm_transaction_received,reasm_image_received,reasm_generated_word_count,reasm_word_valid,reasm_word_ready,reasm_word_fire,reasm_image_complete,reasm_word_address,reasm_word_strb,reasm_word_last,reasm_word_data,");
			$fwrite(r1_trace_fd, "word_fifo_enq_valid,word_fifo_enq_ready,word_fifo_enq_fire,word_fifo_deq_valid,word_fifo_deq_ready,word_fifo_deq_fire,word_fifo_level,word_fifo_head_address,word_fifo_head_strb,word_fifo_head_last,word_fifo_head_data,");
			$fwrite(r1_trace_fd, "mem_program_valid,mem_program_ready,mem_program_fire,mem_program_address,mem_program_strb,mem_program_last,mem_program_error,mem_frontend_ready,mem_fetched_words,mem_decoded_contexts,mem_issued_count,mem_issue_delta,");
			write_r3_channel_header("r3_distributor_in");
			write_r3_channel_header("r3_elastic_out");
			$fwrite(r1_trace_fd, "r3_elastic_level,");
			write_r3_channel_header("r3_east_route");
			write_r3_channel_header("r3_west_route");
			for(integer relay = 0; relay < PROGRAM_RELAY_COUNT; relay = relay + 1)begin
				write_r3_channel_header($sformatf("r3_east_relay%0d_in", relay));
				write_r3_channel_header($sformatf("r3_east_relay%0d_forward", relay));
				write_r3_channel_header($sformatf("r3_east_relay%0d_local", relay));
				$fwrite(r1_trace_fd, "r3_east_relay%0d_level,", relay);
			end
			for(integer relay = 0; relay < PROGRAM_RELAY_COUNT; relay = relay + 1)begin
				write_r3_channel_header($sformatf("r3_west_relay%0d_in", relay));
				write_r3_channel_header($sformatf("r3_west_relay%0d_forward", relay));
				write_r3_channel_header($sformatf("r3_west_relay%0d_local", relay));
				$fwrite(r1_trace_fd, "r3_west_relay%0d_level,", relay);
			end
			write_r3_channel_header("r3_east_outer");
			write_r3_channel_header("r3_west_outer");
			write_r3_channel_header("r3_vxm");
			$fwrite(r1_trace_fd, "r3_east_done,r3_west_done,r3_idle,r3_fault,r3_fault_code,");
			write_r4_mem_header();
		end
	endtask

	// Write one PRE_POSEDGE R1 row from public ports and architecturally visible
	// handshake boundaries. No SRAM pins, array contents, or FIFO pointers are traced.
	task automatic write_r1_row;
		begin
			$fwrite(r1_trace_fd, "%0d,PRE_POSEDGE,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,",
				r1_cycle, known_high(program_cmd_write_valid), known_high(program_cmd_write_ready),
				known_high(program_cmd_write_fire), program_cmd_write_address, program_cmd_write_opcode,
				program_cmd_write_source_address, program_cmd_write_byte_count,
				program_cmd_write_destination, program_cmd_write_format,
				program_cmd_write_encoding_mode, program_cmd_write_imem_base_address,
				known_high(program_cmd_write_image_first), known_high(program_cmd_write_image_last),
				program_cmd_write_expected_word_count, program_cmd_write_jump_address);
			$fwrite(r1_trace_fd, "%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,",
				known_high(program_load_start_valid), known_high(program_load_start_ready),
				known_high(r1_load_start_fire), program_load_start_command_count,
				known_high(u_dut.u_program_load_system.ctrl_load_txn_valid),
				known_high(u_dut.u_program_load_system.ctrl_load_txn_ready), known_high(r1_load_txn_fire),
				u_dut.u_program_load_system.ctrl_load_txn_source_address,
				u_dut.u_program_load_system.ctrl_load_txn_byte_count,
				u_dut.u_program_load_system.ctrl_load_txn_scope,
				u_dut.u_program_load_system.ctrl_load_txn_destination,
				u_dut.u_program_load_system.ctrl_load_txn_format,
				u_dut.u_program_load_system.ctrl_load_txn_imem_base_address,
				known_high(u_dut.u_program_load_system.ctrl_load_txn_image_first),
				known_high(u_dut.u_program_load_system.ctrl_load_txn_image_last),
				u_dut.u_program_load_system.ctrl_load_txn_expected_word_count,
				u_dut.u_program_load_system.ctrl_load_txn_dma_id,
				known_high(u_dut.u_program_load_system.ctrl_prime_valid),
				known_high(u_dut.u_program_load_system.ctrl_prime_ready), known_high(r1_prime_fire),
				u_dut.u_program_load_system.ctrl_prime_scope,
				u_dut.u_program_load_system.ctrl_prime_destination);
			$fwrite(r1_trace_fd, "%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,",
				u_dut.u_program_load_system.u_program_load_controller.command_pc_o,
				known_high(u_dut.u_program_load_system.u_program_load_controller.busy_o),
				known_high(u_dut.u_program_load_system.u_program_load_controller.done_o),
				known_high(u_dut.u_program_load_system.u_program_load_controller.fault_o),
				u_dut.u_program_load_system.u_program_load_controller.fault_code_o,
				known_high(u_dut.u_program_load_system.u_program_load_path.config_enqueue_valid),
				known_high(u_dut.u_program_load_system.u_program_load_path.config_enqueue_ready),
				known_high(r1_config_enqueue_fire),
				u_dut.u_program_load_system.ctrl_load_txn_source_address,
				u_dut.u_program_load_system.ctrl_load_txn_byte_count,
				u_dut.u_program_load_system.ctrl_load_txn_scope,
				u_dut.u_program_load_system.ctrl_load_txn_destination,
				u_dut.u_program_load_system.ctrl_load_txn_format,
				u_dut.u_program_load_system.ctrl_load_txn_imem_base_address,
				known_high(u_dut.u_program_load_system.ctrl_load_txn_image_first),
				known_high(u_dut.u_program_load_system.ctrl_load_txn_image_last),
				u_dut.u_program_load_system.ctrl_load_txn_expected_word_count,
				u_dut.u_program_load_system.ctrl_load_txn_dma_id);
			$fwrite(r1_trace_fd, "%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,",
				known_high(u_dut.u_program_load_system.u_program_load_path.config_dequeue_valid),
				known_high(u_dut.u_program_load_system.u_program_load_path.config_dequeue_ready),
				known_high(r1_config_dequeue_fire),
				u_dut.u_program_load_system.u_program_load_path.u_config_fifo.dequeue_source_address_o,
				u_dut.u_program_load_system.u_program_load_path.config_byte_count,
				u_dut.u_program_load_system.u_program_load_path.config_scope,
				u_dut.u_program_load_system.u_program_load_path.config_destination,
				u_dut.u_program_load_system.u_program_load_path.config_format,
				u_dut.u_program_load_system.u_program_load_path.config_imem_base_address,
				known_high(u_dut.u_program_load_system.u_program_load_path.config_image_first),
				known_high(u_dut.u_program_load_system.u_program_load_path.config_image_last),
				u_dut.u_program_load_system.u_program_load_path.config_expected_word_count,
				u_dut.u_program_load_system.u_program_load_path.config_dma_id,
				u_dut.u_program_load_system.u_program_load_path.u_config_fifo.level_o,
				known_high(u_dut.u_program_load_system.u_program_load_path.u_config_fifo.empty_o),
				known_high(u_dut.u_program_load_system.u_program_load_path.u_config_fifo.full_o));
			$fwrite(r1_trace_fd, "1,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,",
				known_high(u_dut.u_program_load_system.load_request_active_q),
				known_high(u_dut.u_program_load_system.load_pipeline_idle_w),
				known_high(u_dut.load_distribute_idle), known_high(program_load_complete),
				known_high(program_ready), known_high(program_running), known_high(program_done),
				known_high(program_fault), program_fault_code, known_high(r1_dma_final_response),
				u_dut.u_program_load_system.u_program_load_path.reasm_rsp_id);
			$fwrite(r1_trace_fd, "%0d,%0d,%0d,%08h,%0d,%0d,%0d,%064h,%0d,%0d,%0d,%08h,%0d,%0d,%0d,%064h,%0d,",
				known_high(program_ddr_read_rsp_valid), known_high(program_ddr_read_rsp_ready),
				known_high(ddr_read_rsp_fire), program_ddr_read_rsp_keep,
				known_high(program_ddr_read_rsp_last), program_ddr_read_rsp_id,
				known_high(program_ddr_read_rsp_error), program_ddr_read_rsp_data,
				known_high(u_dut.u_program_load_system.u_program_load_path.reasm_rsp_valid),
				known_high(u_dut.u_program_load_system.u_program_load_path.reasm_rsp_ready),
				known_high(r2_dma_rsp_fire),
				u_dut.u_program_load_system.u_program_load_path.reasm_rsp_keep,
				known_high(u_dut.u_program_load_system.u_program_load_path.reasm_rsp_last),
				u_dut.u_program_load_system.u_program_load_path.reasm_rsp_id,
				known_high(u_dut.u_program_load_system.u_program_load_path.reasm_rsp_error),
				u_dut.u_program_load_system.u_program_load_path.reasm_rsp_data,
				u_dut.u_program_load_system.u_program_load_path.u_instruction_dma.response_level);
			$fwrite(r1_trace_fd, "%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%032h,",
				u_dut.u_program_load_system.u_program_load_path.u_reassembler.buffer_count_q,
				known_high(u_dut.u_program_load_system.u_program_load_path.u_reassembler.image_active_q),
				known_high(u_dut.u_program_load_system.u_program_load_path.u_reassembler.image_last_seen_q),
				u_dut.u_program_load_system.u_program_load_path.u_reassembler.transaction_received_q,
				u_dut.u_program_load_system.u_program_load_path.u_reassembler.image_received_q,
				u_dut.u_program_load_system.u_program_load_path.u_reassembler.generated_word_count_q,
				known_high(u_dut.u_program_load_system.u_program_load_path.word_fifo_enqueue_valid),
				known_high(u_dut.u_program_load_system.u_program_load_path.word_fifo_enqueue_ready),
				known_high(r2_reasm_word_fire), known_high(r2_reasm_image_complete),
				u_dut.u_program_load_system.u_program_load_path.word_fifo_enqueue_imem_address,
				u_dut.u_program_load_system.u_program_load_path.word_fifo_enqueue_strb,
				known_high(u_dut.u_program_load_system.u_program_load_path.word_fifo_enqueue_last),
				u_dut.u_program_load_system.u_program_load_path.word_fifo_enqueue_data);
			$fwrite(r1_trace_fd, "%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%032h,",
				known_high(u_dut.u_program_load_system.u_program_load_path.word_fifo_enqueue_valid),
				known_high(u_dut.u_program_load_system.u_program_load_path.word_fifo_enqueue_ready),
				known_high(r2_reasm_word_fire),
				known_high(u_dut.u_program_load_system.u_program_load_path.load_word_valid_o),
				known_high(u_dut.u_program_load_system.u_program_load_path.load_word_ready_i),
				known_high(r2_word_fifo_dequeue_fire),
				u_dut.u_program_load_system.u_program_load_path.u_word_fifo.level_o,
				u_dut.u_program_load_system.u_program_load_path.load_word_imem_address_o,
				u_dut.u_program_load_system.u_program_load_path.load_word_strb_o,
				known_high(u_dut.u_program_load_system.u_program_load_path.load_word_last_o),
				u_dut.u_program_load_system.u_program_load_path.load_word_data_o);
			$fwrite(r1_trace_fd, "%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,",
				known_high(r1_mem_program_write_valid), known_high(u_dut.mem_program_ready[0]),
				known_high(r1_mem_program_write_fire), u_dut.mem_program_imem_address[0+:17],
				u_dut.mem_program_strb[0+:4], known_high(u_dut.mem_program_last[0]),
				known_high(u_dut.mem_program_error[0]),
				known_high(u_dut.u_fu_subsystems.gen_hemisphere[0].u_mem_subsystem.gen_bank_frontend[0].u_frontend.frontend_ready_o),
				r1_mem_fetched_words, r1_mem_decoded_contexts, r1_mem_issued_count,
				known_high(mem_issue_fire));

			write_r3_channel_row(
				u_dut.load_distribute_valid, u_dut.load_distribute_ready,
				u_dut.load_distribute_control, u_dut.load_distribute_data,
				u_dut.load_distribute_strb, u_dut.load_distribute_scope,
				u_dut.load_distribute_destination, u_dut.load_distribute_imem_address,
				u_dut.load_distribute_last);
			write_r3_channel_row(
				u_dut.u_program_distribute_system.u_distributor.head_valid,
				u_dut.u_program_distribute_system.u_distributor.head_ready,
				u_dut.u_program_distribute_system.u_distributor.head_control,
				u_dut.u_program_distribute_system.u_distributor.head_data,
				u_dut.u_program_distribute_system.u_distributor.head_strb,
				u_dut.u_program_distribute_system.u_distributor.head_scope,
				u_dut.u_program_distribute_system.u_distributor.head_destination,
				u_dut.u_program_distribute_system.u_distributor.head_imem_address,
				u_dut.u_program_distribute_system.u_distributor.head_last);
			$fwrite(r1_trace_fd, "%0d,", u_dut.u_program_distribute_system.
				u_distributor.u_load_record_elastic.level_o);
			write_r3_channel_row(
				u_dut.u_program_distribute_system.endpoint_load_valid[0],
				u_dut.u_program_distribute_system.endpoint_load_ready[0],
				u_dut.u_program_distribute_system.endpoint_load_control[0+:PROGRAM_LOAD_CONTROL_WIDTH],
				u_dut.u_program_distribute_system.endpoint_load_data[0+:128],
				u_dut.u_program_distribute_system.endpoint_load_strb[0+:4],
				PROGRAM_SCOPE_EAST,
				u_dut.u_program_distribute_system.endpoint_load_destination[0+:PROGRAM_DESTINATION_WIDTH],
				u_dut.u_program_distribute_system.endpoint_load_imem_address[0+:17],
				u_dut.u_program_distribute_system.endpoint_load_last[0]);
			write_r3_channel_row(
				u_dut.u_program_distribute_system.endpoint_load_valid[1],
				u_dut.u_program_distribute_system.endpoint_load_ready[1],
				u_dut.u_program_distribute_system.endpoint_load_control[PROGRAM_LOAD_CONTROL_WIDTH+:PROGRAM_LOAD_CONTROL_WIDTH],
				u_dut.u_program_distribute_system.endpoint_load_data[128+:128],
				u_dut.u_program_distribute_system.endpoint_load_strb[4+:4],
				PROGRAM_SCOPE_WEST,
				u_dut.u_program_distribute_system.endpoint_load_destination[PROGRAM_DESTINATION_WIDTH+:PROGRAM_DESTINATION_WIDTH],
				u_dut.u_program_distribute_system.endpoint_load_imem_address[17+:17],
				u_dut.u_program_distribute_system.endpoint_load_last[1]);

			for(integer relay = 0; relay < PROGRAM_RELAY_COUNT; relay = relay + 1)begin
				write_r3_channel_row(
					u_dut.u_program_distribute_system.gen_program_relay_chain[0].u_program_relay_chain.relay_input_valid[relay],
					u_dut.u_program_distribute_system.gen_program_relay_chain[0].u_program_relay_chain.relay_input_ready[relay],
					u_dut.u_program_distribute_system.gen_program_relay_chain[0].u_program_relay_chain.relay_input_control[relay*PROGRAM_LOAD_CONTROL_WIDTH+:PROGRAM_LOAD_CONTROL_WIDTH],
					u_dut.u_program_distribute_system.gen_program_relay_chain[0].u_program_relay_chain.relay_input_data[relay*128+:128],
					u_dut.u_program_distribute_system.gen_program_relay_chain[0].u_program_relay_chain.relay_input_strb[relay*4+:4],
					u_dut.u_program_distribute_system.gen_program_relay_chain[0].u_program_relay_chain.relay_input_scope[relay*2+:2],
					u_dut.u_program_distribute_system.gen_program_relay_chain[0].u_program_relay_chain.relay_input_destination[relay*PROGRAM_DESTINATION_WIDTH+:PROGRAM_DESTINATION_WIDTH],
					u_dut.u_program_distribute_system.gen_program_relay_chain[0].u_program_relay_chain.relay_input_imem_address[relay*17+:17],
					u_dut.u_program_distribute_system.gen_program_relay_chain[0].u_program_relay_chain.relay_input_last[relay]);
				write_r3_channel_row(
					u_dut.u_program_distribute_system.gen_program_relay_chain[0].u_program_relay_chain.relay_forward_valid[relay],
					u_dut.u_program_distribute_system.gen_program_relay_chain[0].u_program_relay_chain.relay_forward_ready[relay],
					u_dut.u_program_distribute_system.gen_program_relay_chain[0].u_program_relay_chain.relay_forward_control[relay*PROGRAM_LOAD_CONTROL_WIDTH+:PROGRAM_LOAD_CONTROL_WIDTH],
					u_dut.u_program_distribute_system.gen_program_relay_chain[0].u_program_relay_chain.relay_forward_data[relay*128+:128],
					u_dut.u_program_distribute_system.gen_program_relay_chain[0].u_program_relay_chain.relay_forward_strb[relay*4+:4],
					u_dut.u_program_distribute_system.gen_program_relay_chain[0].u_program_relay_chain.relay_forward_scope[relay*2+:2],
					u_dut.u_program_distribute_system.gen_program_relay_chain[0].u_program_relay_chain.relay_forward_destination[relay*PROGRAM_DESTINATION_WIDTH+:PROGRAM_DESTINATION_WIDTH],
					u_dut.u_program_distribute_system.gen_program_relay_chain[0].u_program_relay_chain.relay_forward_imem_address[relay*17+:17],
					u_dut.u_program_distribute_system.gen_program_relay_chain[0].u_program_relay_chain.relay_forward_last[relay]);
				write_r3_channel_row(
					u_dut.mem_program_valid[relay], u_dut.mem_program_ready[relay],
					u_dut.mem_program_control[relay*PROGRAM_LOAD_CONTROL_WIDTH+:PROGRAM_LOAD_CONTROL_WIDTH],
					u_dut.mem_program_data[relay*128+:128],
					u_dut.mem_program_strb[relay*4+:4],
					u_dut.u_program_distribute_system.relay_mem_scope[relay*2+:2],
					u_dut.mem_program_destination[relay*PROGRAM_DESTINATION_WIDTH+:PROGRAM_DESTINATION_WIDTH],
					u_dut.mem_program_imem_address[relay*17+:17], u_dut.mem_program_last[relay]);
				$fwrite(r1_trace_fd, "%0d,", u_dut.u_program_distribute_system.
					gen_program_relay_chain[0].u_program_relay_chain.relay_level_o[relay*2+:2]);
			end

			for(integer relay = 0; relay < PROGRAM_RELAY_COUNT; relay = relay + 1)begin
				write_r3_channel_row(
					u_dut.u_program_distribute_system.gen_program_relay_chain[1].u_program_relay_chain.relay_input_valid[relay],
					u_dut.u_program_distribute_system.gen_program_relay_chain[1].u_program_relay_chain.relay_input_ready[relay],
					u_dut.u_program_distribute_system.gen_program_relay_chain[1].u_program_relay_chain.relay_input_control[relay*PROGRAM_LOAD_CONTROL_WIDTH+:PROGRAM_LOAD_CONTROL_WIDTH],
					u_dut.u_program_distribute_system.gen_program_relay_chain[1].u_program_relay_chain.relay_input_data[relay*128+:128],
					u_dut.u_program_distribute_system.gen_program_relay_chain[1].u_program_relay_chain.relay_input_strb[relay*4+:4],
					u_dut.u_program_distribute_system.gen_program_relay_chain[1].u_program_relay_chain.relay_input_scope[relay*2+:2],
					u_dut.u_program_distribute_system.gen_program_relay_chain[1].u_program_relay_chain.relay_input_destination[relay*PROGRAM_DESTINATION_WIDTH+:PROGRAM_DESTINATION_WIDTH],
					u_dut.u_program_distribute_system.gen_program_relay_chain[1].u_program_relay_chain.relay_input_imem_address[relay*17+:17],
					u_dut.u_program_distribute_system.gen_program_relay_chain[1].u_program_relay_chain.relay_input_last[relay]);
				write_r3_channel_row(
					u_dut.u_program_distribute_system.gen_program_relay_chain[1].u_program_relay_chain.relay_forward_valid[relay],
					u_dut.u_program_distribute_system.gen_program_relay_chain[1].u_program_relay_chain.relay_forward_ready[relay],
					u_dut.u_program_distribute_system.gen_program_relay_chain[1].u_program_relay_chain.relay_forward_control[relay*PROGRAM_LOAD_CONTROL_WIDTH+:PROGRAM_LOAD_CONTROL_WIDTH],
					u_dut.u_program_distribute_system.gen_program_relay_chain[1].u_program_relay_chain.relay_forward_data[relay*128+:128],
					u_dut.u_program_distribute_system.gen_program_relay_chain[1].u_program_relay_chain.relay_forward_strb[relay*4+:4],
					u_dut.u_program_distribute_system.gen_program_relay_chain[1].u_program_relay_chain.relay_forward_scope[relay*2+:2],
					u_dut.u_program_distribute_system.gen_program_relay_chain[1].u_program_relay_chain.relay_forward_destination[relay*PROGRAM_DESTINATION_WIDTH+:PROGRAM_DESTINATION_WIDTH],
					u_dut.u_program_distribute_system.gen_program_relay_chain[1].u_program_relay_chain.relay_forward_imem_address[relay*17+:17],
					u_dut.u_program_distribute_system.gen_program_relay_chain[1].u_program_relay_chain.relay_forward_last[relay]);
				write_r3_channel_row(
					u_dut.mem_program_valid[PROGRAM_RELAY_COUNT+relay],
					u_dut.mem_program_ready[PROGRAM_RELAY_COUNT+relay],
					u_dut.mem_program_control[(PROGRAM_RELAY_COUNT+relay)*PROGRAM_LOAD_CONTROL_WIDTH+:PROGRAM_LOAD_CONTROL_WIDTH],
					u_dut.mem_program_data[(PROGRAM_RELAY_COUNT+relay)*128+:128],
					u_dut.mem_program_strb[(PROGRAM_RELAY_COUNT+relay)*4+:4],
					u_dut.u_program_distribute_system.relay_mem_scope[(PROGRAM_RELAY_COUNT+relay)*2+:2],
					u_dut.mem_program_destination[(PROGRAM_RELAY_COUNT+relay)*PROGRAM_DESTINATION_WIDTH+:PROGRAM_DESTINATION_WIDTH],
					u_dut.mem_program_imem_address[(PROGRAM_RELAY_COUNT+relay)*17+:17],
					u_dut.mem_program_last[PROGRAM_RELAY_COUNT+relay]);
				$fwrite(r1_trace_fd, "%0d,", u_dut.u_program_distribute_system.
					gen_program_relay_chain[1].u_program_relay_chain.relay_level_o[relay*2+:2]);
			end

			write_r3_channel_row(
				u_dut.u_program_distribute_system.relay_outer_valid[0],
				u_dut.u_program_distribute_system.relay_outer_ready[0],
				u_dut.u_program_distribute_system.relay_outer_control[0+:PROGRAM_LOAD_CONTROL_WIDTH],
				u_dut.u_program_distribute_system.relay_outer_data[0+:128],
				u_dut.u_program_distribute_system.relay_outer_strb[0+:4],
				u_dut.u_program_distribute_system.relay_outer_scope[0+:2],
				u_dut.u_program_distribute_system.relay_outer_destination[0+:PROGRAM_DESTINATION_WIDTH],
				u_dut.u_program_distribute_system.relay_outer_address[0+:17],
				u_dut.u_program_distribute_system.relay_outer_last[0]);
			write_r3_channel_row(
				u_dut.u_program_distribute_system.relay_outer_valid[1],
				u_dut.u_program_distribute_system.relay_outer_ready[1],
				u_dut.u_program_distribute_system.relay_outer_control[PROGRAM_LOAD_CONTROL_WIDTH+:PROGRAM_LOAD_CONTROL_WIDTH],
				u_dut.u_program_distribute_system.relay_outer_data[128+:128],
				u_dut.u_program_distribute_system.relay_outer_strb[4+:4],
				u_dut.u_program_distribute_system.relay_outer_scope[2+:2],
				u_dut.u_program_distribute_system.relay_outer_destination[PROGRAM_DESTINATION_WIDTH+:PROGRAM_DESTINATION_WIDTH],
				u_dut.u_program_distribute_system.relay_outer_address[17+:17],
				u_dut.u_program_distribute_system.relay_outer_last[1]);
			write_r3_channel_row(
				u_dut.vxm_program_valid, u_dut.vxm_program_ready,
				u_dut.vxm_program_control, u_dut.vxm_program_data,
				u_dut.vxm_program_strb, PROGRAM_SCOPE_EAST,
				u_dut.vxm_program_destination, u_dut.vxm_program_address,
				u_dut.vxm_program_last);
			$fwrite(r1_trace_fd, "%0d,%0d,%0d,%0d,%0d,",
				known_high(u_dut.u_program_distribute_system.u_distributor.east_relay_done_q),
				known_high(u_dut.u_program_distribute_system.u_distributor.west_relay_done_q),
				known_high(u_dut.u_program_distribute_system.distributor_idle &&
					(&u_dut.u_program_distribute_system.relay_chain_idle)),
				known_high(u_dut.u_program_distribute_system.fault_o),
				u_dut.u_program_distribute_system.fault_code_o);
			write_r4_mem_row();
		end
	endtask

	always #5 clk = ~clk;

	// Canonical transfer samples are taken at the active clock edge before any
	// nonblocking state update. Testbench inputs have already been stable for a
	// half cycle, so each fire and payload belong to the same accepted transfer.
	always @(posedge clk) begin
		if(rst_n && (trace_fd != 0))begin
			$fdisplay(trace_fd,
				"{\"case_id\":\"%s\",\"cycle\":%0d,\"phase\":\"PRE_POSEDGE\",\"boundary\":\"program_command\",\"valid\":%0d,\"ready\":%0d,\"fire\":%0d,\"address\":%0d,\"opcode\":%0d,\"source_address\":\"0x%016h\",\"byte_count\":%0d,\"destination\":\"0x%03h\",\"format\":%0d,\"encoding_mode\":%0d,\"imem_base\":%0d,\"image_first\":%0d,\"image_last\":%0d,\"expected_words\":%0d}",
				case_id, physical_clock_edges, known_high(program_cmd_write_valid),
				known_high(program_cmd_write_ready), known_high(program_cmd_write_fire),
				program_cmd_write_address, program_cmd_write_opcode,
				program_cmd_write_source_address, program_cmd_write_byte_count,
				program_cmd_write_destination, program_cmd_write_format,
				program_cmd_write_encoding_mode, program_cmd_write_imem_base_address,
				program_cmd_write_image_first, program_cmd_write_image_last,
				program_cmd_write_expected_word_count);
			$fdisplay(trace_fd,
				"{\"case_id\":\"%s\",\"cycle\":%0d,\"phase\":\"PRE_POSEDGE\",\"boundary\":\"ddr_read_request\",\"valid\":%0d,\"ready\":%0d,\"fire\":%0d,\"address\":\"0x%016h\",\"length\":%0d,\"id\":%0d}",
				case_id, physical_clock_edges, known_high(program_ddr_read_req_valid),
				known_high(program_ddr_read_req_ready), known_high(ddr_read_req_fire), program_ddr_read_req_address,
				program_ddr_read_req_length, program_ddr_read_req_id);
			$fdisplay(trace_fd,
				"{\"case_id\":\"%s\",\"cycle\":%0d,\"phase\":\"PRE_POSEDGE\",\"boundary\":\"ddr_read_response\",\"valid\":%0d,\"ready\":%0d,\"fire\":%0d,\"data\":\"0x%0h\",\"keep\":\"0x%0h\",\"last\":%0d,\"id\":%0d,\"error\":%0d}",
				case_id, physical_clock_edges, known_high(program_ddr_read_rsp_valid),
				known_high(program_ddr_read_rsp_ready), known_high(ddr_read_rsp_fire), program_ddr_read_rsp_data,
				program_ddr_read_rsp_keep, program_ddr_read_rsp_last,
				program_ddr_read_rsp_id, program_ddr_read_rsp_error);
			$fdisplay(trace_fd,
				"{\"case_id\":\"%s\",\"cycle\":%0d,\"phase\":\"PRE_POSEDGE\",\"boundary\":\"dma_to_reassembler\",\"valid\":%0d,\"ready\":%0d,\"fire\":%0d,\"data\":\"0x%0h\",\"keep\":\"0x%0h\",\"last\":%0d,\"id\":\"0x%0h\",\"error\":%0d}",
				case_id, physical_clock_edges,
				known_high(u_dut.u_program_load_system.u_program_load_path.reasm_rsp_valid),
				known_high(u_dut.u_program_load_system.u_program_load_path.reasm_rsp_ready),
				known_high(u_dut.u_program_load_system.u_program_load_path.reasm_rsp_valid &&
					u_dut.u_program_load_system.u_program_load_path.reasm_rsp_ready),
				u_dut.u_program_load_system.u_program_load_path.reasm_rsp_data,
				u_dut.u_program_load_system.u_program_load_path.reasm_rsp_keep,
				known_high(u_dut.u_program_load_system.u_program_load_path.reasm_rsp_last),
				u_dut.u_program_load_system.u_program_load_path.reasm_rsp_id,
				known_high(u_dut.u_program_load_system.u_program_load_path.reasm_rsp_error));
			$fdisplay(trace_fd,
				"{\"case_id\":\"%s\",\"cycle\":%0d,\"phase\":\"PRE_POSEDGE\",\"boundary\":\"reassembler_to_word_fifo\",\"valid\":%0d,\"ready\":%0d,\"fire\":%0d,\"data\":\"0x%032h\",\"strb\":\"0x%01h\",\"destination\":\"0x%03h\",\"imem_address\":%0d,\"last\":%0d}",
				case_id, physical_clock_edges,
				known_high(u_dut.u_program_load_system.u_program_load_path.word_fifo_enqueue_valid),
				known_high(u_dut.u_program_load_system.u_program_load_path.word_fifo_enqueue_ready),
				known_high(u_dut.u_program_load_system.u_program_load_path.word_fifo_enqueue_valid &&
					u_dut.u_program_load_system.u_program_load_path.word_fifo_enqueue_ready),
				u_dut.u_program_load_system.u_program_load_path.word_fifo_enqueue_data,
				u_dut.u_program_load_system.u_program_load_path.word_fifo_enqueue_strb,
				u_dut.u_program_load_system.u_program_load_path.word_fifo_enqueue_destination,
				u_dut.u_program_load_system.u_program_load_path.word_fifo_enqueue_imem_address,
				known_high(u_dut.u_program_load_system.u_program_load_path.word_fifo_enqueue_last));
			$fdisplay(trace_fd,
				"{\"case_id\":\"%s\",\"cycle\":%0d,\"phase\":\"PRE_POSEDGE\",\"boundary\":\"load_to_distribution\",\"valid\":%0d,\"ready\":%0d,\"fire\":%0d,\"control\":\"0x%0h\",\"data\":\"0x%032h\",\"strb\":\"0x%01h\",\"scope\":\"0x%0h\",\"destination\":\"0x%03h\",\"imem_address\":\"0x%0h\",\"last\":%0d}",
				case_id, physical_clock_edges, known_high(u_dut.load_distribute_valid),
				known_high(u_dut.load_distribute_ready), known_high(load_distribute_fire),
				u_dut.load_distribute_control, u_dut.load_distribute_data,
				u_dut.load_distribute_strb, u_dut.load_distribute_scope,
				u_dut.load_distribute_destination, u_dut.load_distribute_imem_address,
				known_high(u_dut.load_distribute_last));
			$fdisplay(trace_fd,
				"{\"case_id\":\"%s\",\"cycle\":%0d,\"phase\":\"PRE_POSEDGE\",\"boundary\":\"mem_program_port_0\",\"valid\":%0d,\"ready\":%0d,\"fire\":%0d,\"control\":\"0x%0h\",\"destination\":\"0x%03h\",\"imem_address\":\"0x%0h\",\"data\":\"0x%032h\",\"strb\":\"0x%01h\",\"last\":%0d,\"error\":%0d}",
				case_id, physical_clock_edges, known_high(u_dut.mem_program_valid[0]),
				known_high(u_dut.mem_program_ready[0]), known_high(mem_program_fire),
				u_dut.mem_program_control[0+:PROGRAM_LOAD_CONTROL_WIDTH],
				u_dut.mem_program_destination[0+:PROGRAM_DESTINATION_WIDTH],
				u_dut.mem_program_imem_address[0+:17],
				u_dut.mem_program_data[0+:128], u_dut.mem_program_strb[0+:4],
				known_high(u_dut.mem_program_last[0]), known_high(u_dut.mem_program_error[0]));
			$fdisplay(trace_fd,
				"{\"case_id\":\"%s\",\"cycle\":%0d,\"phase\":\"PRE_POSEDGE\",\"boundary\":\"local_imem_read_request\",\"valid\":%0d,\"ready\":%0d,\"fire\":%0d,\"address\":%0d,\"last\":%0d}",
				case_id, physical_clock_edges,
				known_high(u_dut.u_fu_subsystems.gen_hemisphere[0].u_mem_subsystem.gen_bank_frontend[0].u_frontend.imem_read_req_valid),
				known_high(u_dut.u_fu_subsystems.gen_hemisphere[0].u_mem_subsystem.gen_bank_frontend[0].u_frontend.imem_read_req_ready),
				known_high(imem_read_req_fire),
				u_dut.u_fu_subsystems.gen_hemisphere[0].u_mem_subsystem.gen_bank_frontend[0].u_frontend.imem_read_req_address,
				known_high(u_dut.u_fu_subsystems.gen_hemisphere[0].u_mem_subsystem.gen_bank_frontend[0].u_frontend.imem_read_req_last));
			$fdisplay(trace_fd,
				"{\"case_id\":\"%s\",\"cycle\":%0d,\"phase\":\"PRE_POSEDGE\",\"boundary\":\"local_imem_read_response\",\"valid\":%0d,\"ready\":%0d,\"fire\":%0d,\"data\":\"0x%024h\",\"last\":%0d}",
				case_id, physical_clock_edges,
				known_high(u_dut.u_fu_subsystems.gen_hemisphere[0].u_mem_subsystem.gen_bank_frontend[0].u_frontend.imem_read_rsp_valid),
				known_high(u_dut.u_fu_subsystems.gen_hemisphere[0].u_mem_subsystem.gen_bank_frontend[0].u_frontend.imem_read_rsp_ready),
				known_high(imem_read_rsp_fire),
				u_dut.u_fu_subsystems.gen_hemisphere[0].u_mem_subsystem.gen_bank_frontend[0].u_frontend.imem_read_rsp_data,
				known_high(u_dut.u_fu_subsystems.gen_hemisphere[0].u_mem_subsystem.gen_bank_frontend[0].u_frontend.imem_read_rsp_last));
			$fdisplay(trace_fd,
				"{\"case_id\":\"%s\",\"cycle\":%0d,\"phase\":\"PRE_POSEDGE\",\"boundary\":\"macro_decoder_context\",\"valid\":%0d,\"ready\":%0d,\"fire\":%0d,\"instruction\":\"0x%08h\",\"start_cycle\":\"0x%08h\",\"inner_count\":\"0x%08h\",\"inner_interval\":\"0x%08h\",\"inner_stride\":\"0x%08h\",\"outer_count\":\"0x%08h\",\"outer_interval\":\"0x%08h\",\"outer_stride\":\"0x%08h\",\"induction_target\":\"0x%0h\",\"address\":\"0x%0h\"}",
				case_id, physical_clock_edges,
				known_high(u_dut.u_fu_subsystems.gen_hemisphere[0].u_mem_subsystem.gen_bank_frontend[0].u_frontend.u_macro_frontend.decoder_context_valid),
				known_high(u_dut.u_fu_subsystems.gen_hemisphere[0].u_mem_subsystem.gen_bank_frontend[0].u_frontend.u_macro_frontend.decoder_context_ready),
				known_high(context_fifo_enqueue_fire),
				u_dut.u_fu_subsystems.gen_hemisphere[0].u_mem_subsystem.gen_bank_frontend[0].u_frontend.u_macro_frontend.decoder_instruction,
				u_dut.u_fu_subsystems.gen_hemisphere[0].u_mem_subsystem.gen_bank_frontend[0].u_frontend.u_macro_frontend.decoder_start_cycle,
				u_dut.u_fu_subsystems.gen_hemisphere[0].u_mem_subsystem.gen_bank_frontend[0].u_frontend.u_macro_frontend.decoder_inner_count,
				u_dut.u_fu_subsystems.gen_hemisphere[0].u_mem_subsystem.gen_bank_frontend[0].u_frontend.u_macro_frontend.decoder_inner_interval,
				u_dut.u_fu_subsystems.gen_hemisphere[0].u_mem_subsystem.gen_bank_frontend[0].u_frontend.u_macro_frontend.decoder_inner_stride,
				u_dut.u_fu_subsystems.gen_hemisphere[0].u_mem_subsystem.gen_bank_frontend[0].u_frontend.u_macro_frontend.decoder_outer_count,
				u_dut.u_fu_subsystems.gen_hemisphere[0].u_mem_subsystem.gen_bank_frontend[0].u_frontend.u_macro_frontend.decoder_outer_interval,
				u_dut.u_fu_subsystems.gen_hemisphere[0].u_mem_subsystem.gen_bank_frontend[0].u_frontend.u_macro_frontend.decoder_outer_stride,
				u_dut.u_fu_subsystems.gen_hemisphere[0].u_mem_subsystem.gen_bank_frontend[0].u_frontend.u_macro_frontend.decoder_induction_target,
				u_dut.u_fu_subsystems.gen_hemisphere[0].u_mem_subsystem.gen_bank_frontend[0].u_frontend.u_macro_frontend.decoder_address);
			$fdisplay(trace_fd,
				"{\"case_id\":\"%s\",\"cycle\":%0d,\"phase\":\"PRE_POSEDGE\",\"boundary\":\"mem_issue\",\"valid\":%0d,\"ready\":%0d,\"fire\":%0d,\"instruction\":\"0x%012h\",\"issue_cycle\":\"0x%08h\",\"fault\":%0d}",
				case_id, physical_clock_edges, known_high(mem_issue_valid), known_high(mem_issue_ready),
				known_high(mem_issue_fire), mem_issue_instruction, mem_issue_cycle, known_high(mem_fault));
		end

		if(rst_n && (stimulus_fd != 0))begin
			if(program_cmd_write_fire)begin
				$fdisplay(stimulus_fd,
					"{\"case_id\":\"%s\",\"cycle\":%0d,\"action\":\"program_command_write\",\"address\":%0d,\"opcode\":%0d,\"source_address\":\"0x%016h\",\"byte_count\":%0d,\"destination\":\"0x%03h\",\"format\":%0d,\"encoding_mode\":%0d,\"imem_base\":%0d,\"image_first\":%0d,\"image_last\":%0d,\"expected_words\":%0d}",
					case_id, physical_clock_edges, program_cmd_write_address,
					program_cmd_write_opcode, program_cmd_write_source_address,
					program_cmd_write_byte_count, program_cmd_write_destination,
					program_cmd_write_format, program_cmd_write_encoding_mode,
					program_cmd_write_imem_base_address, program_cmd_write_image_first,
					program_cmd_write_image_last, program_cmd_write_expected_word_count);
			end
			if(program_load_start_valid && program_load_start_ready)begin
				$fdisplay(stimulus_fd,
					"{\"case_id\":\"%s\",\"cycle\":%0d,\"action\":\"program_load_start\",\"command_count\":%0d}",
					case_id, physical_clock_edges, program_load_start_command_count);
			end
			if(ddr_read_rsp_fire)begin
				$fdisplay(stimulus_fd,
					"{\"case_id\":\"%s\",\"cycle\":%0d,\"action\":\"ddr_response_beat\",\"data_width\":%0d,\"data\":\"0x%0h\",\"keep\":\"0x%0h\",\"last\":%0d,\"id\":%0d,\"error\":%0d}",
					case_id, physical_clock_edges, DMA_DATA_WIDTH,
					program_ddr_read_rsp_data, program_ddr_read_rsp_keep,
					program_ddr_read_rsp_last, program_ddr_read_rsp_id,
					program_ddr_read_rsp_error);
			end
		end
	end

	// R1 samples the same PRE_POSEDGE convention as CModel. The assertions in
	// this monitor prove payload stability whenever either internal boundary stalls.
	always @(posedge clk) begin
		if(!rst_n || !r1_trace_enable)begin
			r1_load_hold_valid = 1'b0;
			r1_config_hold_valid = 1'b0;
		end
		else begin
			if(r1_load_hold_valid && (r1_load_txn_payload !== r1_load_hold_payload))begin
				$fatal(1, "R1 load transaction payload changed under backpressure at cycle %0d", r1_cycle);
			end
			if(r1_config_hold_valid && (r1_config_dequeue_payload !== r1_config_hold_payload))begin
				$fatal(1, "R1 Config FIFO payload changed under backpressure at cycle %0d", r1_cycle);
			end
			if(u_dut.u_program_load_system.ctrl_load_txn_valid &&
				!u_dut.u_program_load_system.ctrl_load_txn_ready)begin
				r1_load_hold_valid = 1'b1;
				r1_load_hold_payload = r1_load_txn_payload;
			end
			else begin
				r1_load_hold_valid = 1'b0;
			end
			if(u_dut.u_program_load_system.u_program_load_path.config_dequeue_valid &&
				!u_dut.u_program_load_system.u_program_load_path.config_dequeue_ready)begin
				r1_config_hold_valid = 1'b1;
				r1_config_hold_payload = r1_config_dequeue_payload;
			end
			else begin
				r1_config_hold_valid = 1'b0;
			end

			if(u_dut.u_program_load_system.u_program_load_path.u_config_fifo.empty_o !==
				(u_dut.u_program_load_system.u_program_load_path.u_config_fifo.level_o == 0))begin
				$fatal(1, "R1 Config FIFO empty flag disagrees with level at cycle %0d", r1_cycle);
			end
			if(u_dut.u_program_load_system.u_program_load_path.u_config_fifo.full_o !==
				(u_dut.u_program_load_system.u_program_load_path.u_config_fifo.level_o == 16))begin
				$fatal(1, "R1 Config FIFO full flag disagrees with level at cycle %0d", r1_cycle);
			end

			r1_command_write_count = r1_command_write_count + known_high(program_cmd_write_fire);
			r1_load_start_count = r1_load_start_count + known_high(r1_load_start_fire);
			r1_load_txn_count = r1_load_txn_count + known_high(r1_load_txn_fire);
			r1_prime_count = r1_prime_count + known_high(r1_prime_fire);
			r1_config_enqueue_count = r1_config_enqueue_count + known_high(r1_config_enqueue_fire);
			r1_config_dequeue_count = r1_config_dequeue_count + known_high(r1_config_dequeue_fire);
			r1_dma_final_response_count = r1_dma_final_response_count + known_high(r1_dma_final_response);
			r1_mem_program_count = r1_mem_program_count + known_high(r1_mem_program_write_fire);
			r1_mem_fetched_words = r1_mem_fetched_words + known_high(imem_read_rsp_fire);
			r1_mem_decoded_contexts = r1_mem_decoded_contexts + known_high(context_fifo_enqueue_fire);
			r1_mem_issued_count = r1_mem_issued_count + known_high(mem_issue_fire);
			if(ddr_read_req_fire)begin
				r1_dma_request_count = r1_dma_request_count + 1;
				r1_dma_request_id = program_ddr_read_req_id;
				r1_dma_request_address = program_ddr_read_req_address;
				r1_dma_request_length = program_ddr_read_req_length;
			end

			if(r1_trace_fd != 0)begin
				write_r1_row();
			end
			if(r1_stimulus_fd != 0)begin
				if(r1_cycle == 0)begin
					$fdisplay(r1_stimulus_fd,
						"{\"cycle\":0,\"action\":\"program_control_setup\",\"program_start_request\":%0d,\"dependencies_ready\":%0d}",
						known_high(program_start_request), known_high(program_dependencies_ready));
				end
				if(program_cmd_write_fire)begin
					$fdisplay(r1_stimulus_fd,
						"{\"cycle\":%0d,\"action\":\"command_write\",\"address\":%0d,\"opcode\":%0d,\"source\":%0d,\"bytes\":%0d,\"destination\":%0d,\"format\":%0d,\"encoding\":%0d,\"imem_base\":%0d,\"first\":%0d,\"last\":%0d,\"expected_words\":%0d,\"jump\":%0d}",
						r1_cycle, program_cmd_write_address, program_cmd_write_opcode,
						program_cmd_write_source_address, program_cmd_write_byte_count,
						program_cmd_write_destination, program_cmd_write_format,
						program_cmd_write_encoding_mode, program_cmd_write_imem_base_address,
						known_high(program_cmd_write_image_first), known_high(program_cmd_write_image_last),
						program_cmd_write_expected_word_count, program_cmd_write_jump_address);
				end
				if(r1_load_start_fire)begin
					$fdisplay(r1_stimulus_fd,
						"{\"cycle\":%0d,\"action\":\"load_start\",\"command_count\":%0d}",
						r1_cycle, program_load_start_command_count);
				end
				if(ddr_read_rsp_fire)begin
					$fdisplay(r1_stimulus_fd,
						"{\"cycle\":%0d,\"action\":\"ddr_response\",\"data\":\"0x%064h\",\"keep\":\"0x%08h\",\"last\":%0d,\"id\":%0d,\"error\":%0d}",
						r1_cycle, program_ddr_read_rsp_data, program_ddr_read_rsp_keep,
						known_high(program_ddr_read_rsp_last), program_ddr_read_rsp_id,
						known_high(program_ddr_read_rsp_error));
				end
			end

			r1_trace_rows = r1_trace_rows + 1;
			r1_cycle = r1_cycle + 1;
		end
	end

	// Internal levels are diagnostic evidence only and never define the formal
	// transport contract used by the CMODEL comparison.
	always @(negedge clk) begin
		#1;
		if(rst_n && (diagnostic_fd != 0))begin
			$fdisplay(diagnostic_fd,
				"{\"case_id\":\"%s\",\"cycle\":%0d,\"phase\":\"POST_COMB\",\"class\":\"diagnostic\",\"word_fifo_level\":%0d,\"context_fifo_level\":%0d,\"load_path_idle\":%0d,\"distribution_idle\":%0d,\"frontend_ready\":%0d,\"program_fault\":%0d,\"fault_code\":%0d}",
				case_id, physical_clock_edges, word_fifo_level, context_fifo_level,
				u_dut.u_program_load_system.load_path_idle,
				u_dut.load_distribute_idle,
				u_dut.u_fu_subsystems.gen_hemisphere[0].u_mem_subsystem.gen_bank_frontend[0].u_frontend.frontend_ready_o,
				program_fault, program_fault_code);
		end
	end

	// This counter proves that Program Reset never stops or replaces the physical clock.
	always @(posedge clk) begin
		physical_clock_edges <= physical_clock_edges + 1;
		if(rst_n && program_start_ack)begin
			start_ack_count <= start_ack_count + 1;
		end
	end

	function automatic logic [287:0] make_mem_image(
		input logic [31:0] start_cycle,
		input logic [12:0] address,
		input logic [5:0] stream
	);
		logic [287:0] image;
		begin
			image = {MEM_WORD_2, MEM_WORD_1, MEM_WORD_0};
			image[135+:32] = start_cycle;
			image[167+:13] = address;
			image[201+:6] = stream;
			make_mem_image = image;
		end
	endfunction

	function automatic logic [287:0] make_mxm_image(
		input logic [127:0] instruction
	);
		logic [287:0] image;
		begin
			image = '0;
			image[0+:128] = MXM_CONTROL;
			image[128+:128] = instruction;
			make_mxm_image = image;
		end
	endfunction

	lpu_top #(
		.MEM_DEPTH_ROWS(256),
		.ACTIVE_MEM_COLUMNS(2),
		.PROGRAM_COMMAND_DEPTH(COMMAND_DEPTH),
		.PROGRAM_DMA_DATA_WIDTH(DMA_DATA_WIDTH),
		.PROGRAM_MEM_IMEM_DEPTH(16),
		.PROGRAM_MXM_IMEM_DEPTH(16),
		.PROGRAM_ACTIVE_CONTEXTS(4)
	) u_dut (
		.clk_i(clk),
		.rst_ni(rst_n),
		.program_reset_i(program_reset),
		.program_cmd_write_valid_i(program_cmd_write_valid),
		.program_cmd_write_ready_o(program_cmd_write_ready),
		.program_cmd_write_address_i(program_cmd_write_address),
		.program_cmd_write_opcode_i(program_cmd_write_opcode),
		.program_cmd_write_source_address_i(program_cmd_write_source_address),
		.program_cmd_write_byte_count_i(program_cmd_write_byte_count),
		.program_cmd_write_destination_i(program_cmd_write_destination),
		.program_cmd_write_format_i(program_cmd_write_format),
		.program_cmd_write_encoding_mode_i(program_cmd_write_encoding_mode),
		.program_cmd_write_imem_base_address_i(program_cmd_write_imem_base_address),
		.program_cmd_write_image_first_i(program_cmd_write_image_first),
		.program_cmd_write_image_last_i(program_cmd_write_image_last),
		.program_cmd_write_expected_word_count_i(program_cmd_write_expected_word_count),
		.program_cmd_write_jump_address_i(program_cmd_write_jump_address),
		.program_load_start_valid_i(program_load_start_valid),
		.program_load_start_ready_o(program_load_start_ready),
		.program_load_start_command_count_i(program_load_start_command_count),
		.program_ddr_read_req_valid_o(program_ddr_read_req_valid),
		.program_ddr_read_req_ready_i(program_ddr_read_req_ready),
		.program_ddr_read_req_address_o(program_ddr_read_req_address),
		.program_ddr_read_req_length_o(program_ddr_read_req_length),
		.program_ddr_read_req_id_o(program_ddr_read_req_id),
		.program_ddr_read_rsp_valid_i(program_ddr_read_rsp_valid),
		.program_ddr_read_rsp_ready_o(program_ddr_read_rsp_ready),
		.program_ddr_read_rsp_data_i(program_ddr_read_rsp_data),
		.program_ddr_read_rsp_keep_i(program_ddr_read_rsp_keep),
		.program_ddr_read_rsp_last_i(program_ddr_read_rsp_last),
		.program_ddr_read_rsp_id_i(program_ddr_read_rsp_id),
		.program_ddr_read_rsp_error_i(program_ddr_read_rsp_error),
		.program_start_request_i(program_start_request),
		.program_dependencies_ready_i(program_dependencies_ready),
		.program_start_ack_o(program_start_ack),
		.program_load_complete_o(program_load_complete),
		.program_ready_o(program_ready),
		.program_running_o(program_running),
		.program_done_o(program_done),
		.program_fault_o(program_fault),
		.program_fault_code_o(program_fault_code),
		.program_schedule_cycle_o(program_schedule_cycle),
		.mem_east_edge_valid_i('0),
		.mem_east_edge_data_i('0),
		.mem_east_edge_valid_o(),
		.mem_east_edge_data_o(),
		.mem_west_edge_valid_i('0),
		.mem_west_edge_data_i('0),
		.mem_west_edge_valid_o(),
		.mem_west_edge_data_o(),
		.mem_fault_o(),
		.mxm_fault_o(),
		.sxm_fault_o(),
		.vxm_fault_o(),
		.stream_conflict_o(),
		.cycle_o(physical_cycle)
	);

	task automatic check(input logic condition, input string label);
		begin
			if(!condition)begin
				$display("load_debug descriptor=%0b loader_error=%0b command_fault=%0b command_code=%0d load_path_fault=%0b distribute_fault=%0b",
					u_dut.u_program_load_system.descriptor_fault_q,
					u_dut.u_program_load_system.loader_error,
					u_dut.u_program_load_system.command_fault,
					u_dut.u_program_load_system.command_fault_code,
					u_dut.u_program_load_system.load_path_fault,
					u_dut.load_distribute_fault);
				$fatal(1, "FAIL %s schedule=%0d fault=%0b code=%0d", label,
					program_schedule_cycle, program_fault, program_fault_code);
			end
			checks = checks + 1;
		end
	endtask

	// Drive one command without inserting an idle cycle. R1 uses this helper to
	// reproduce the four consecutive CModel command writes exactly.
	task automatic drive_r1_command(
		input logic [COMMAND_ADDRESS_WIDTH-1:0] address,
		input logic [2:0] opcode,
		input logic [63:0] source_address,
		input logic [31:0] byte_count,
		input logic [PROGRAM_DESTINATION_WIDTH-1:0] destination,
		input logic [1:0] format,
		input logic [1:0] encoding_mode,
		input logic [16:0] imem_base,
		input logic image_first,
		input logic image_last,
		input logic [15:0] expected_words,
		input logic [COMMAND_ADDRESS_WIDTH-1:0] jump_address
	);
		begin
			program_cmd_write_address = address;
			program_cmd_write_opcode = opcode;
			program_cmd_write_source_address = source_address;
			program_cmd_write_byte_count = byte_count;
			program_cmd_write_destination = destination;
			program_cmd_write_format = format;
			program_cmd_write_encoding_mode = encoding_mode;
			program_cmd_write_imem_base_address = imem_base;
			program_cmd_write_image_first = image_first;
			program_cmd_write_image_last = image_last;
			program_cmd_write_expected_word_count = expected_words;
			program_cmd_write_jump_address = jump_address;
			program_cmd_write_valid = 1'b1;
		end
	endtask

	task automatic pulse_program_reset;
		integer edge_before;
		begin
			edge_before = physical_clock_edges;
			@(negedge clk);
			program_reset = 1'b1;
			@(posedge clk);
			@(negedge clk);
			program_reset = 1'b0;
			repeat(2) @(posedge clk);
			check(physical_clock_edges > edge_before, "Program Reset preserves physical clock");
			check(program_schedule_cycle == 0 && !program_running && !program_done,
				"Program Reset clears program control state");
		end
	endtask

	task automatic write_command(
		input integer address,
		input logic [2:0] opcode,
		input logic [63:0] source_address,
		input logic [31:0] byte_count,
		input logic [PROGRAM_DESTINATION_WIDTH-1:0] destination,
		input logic [1:0] format,
		input logic [15:0] expected_words,
		input logic [16:0] imem_base,
		input logic [1:0] encoding_mode
	);
		begin
			@(negedge clk);
			program_cmd_write_address = address[COMMAND_ADDRESS_WIDTH-1:0];
			program_cmd_write_opcode = opcode;
			program_cmd_write_source_address = source_address;
			program_cmd_write_byte_count = byte_count;
			program_cmd_write_destination = destination;
			program_cmd_write_format = format;
			program_cmd_write_encoding_mode = encoding_mode;
			program_cmd_write_imem_base_address = imem_base;
			program_cmd_write_image_first = 1'b1;
			program_cmd_write_image_last = 1'b1;
			program_cmd_write_expected_word_count = expected_words;
			program_cmd_write_jump_address = '0;
			program_cmd_write_valid = 1'b1;
			check(program_cmd_write_ready, "Program command RAM ready");
			@(posedge clk);
			@(negedge clk);
			program_cmd_write_valid = 1'b0;
		end
	endtask

	task automatic append_image_commands(
		input logic [63:0] source_address,
		input logic [31:0] byte_count,
		input logic [PROGRAM_DESTINATION_WIDTH-1:0] destination,
		input logic [1:0] format,
		input logic [15:0] expected_words
	);
		begin
			write_command(next_command, PROGRAM_LOADER_LOAD_IMEM, source_address, byte_count,
				destination, format, expected_words, 17'd0, PROGRAM_ENCODING_MACRO);
			next_command = next_command + 1;
			write_command(next_command, PROGRAM_LOADER_WAIT_DMA, 0, 0,
				destination, format, expected_words, 17'd0, PROGRAM_ENCODING_MACRO);
			next_command = next_command + 1;
			write_command(next_command, PROGRAM_LOADER_COMMIT_QUEUE, 0, 0,
				destination, format, expected_words, 17'd0, PROGRAM_ENCODING_MACRO);
			next_command = next_command + 1;
		end
	endtask

	task automatic append_end;
		begin
			write_command(next_command, PROGRAM_LOADER_END, 0, 0,
				program_destination_pack(PROGRAM_HEMISPHERE_EAST, PROGRAM_TARGET_MEM, 8'd0),
				PROGRAM_FORMAT_96, 0, 17'd0, PROGRAM_ENCODING_MACRO);
			next_command = next_command + 1;
		end
	endtask

	task automatic start_loader;
		begin
			@(negedge clk);
			program_load_start_command_count = next_command;
			program_load_start_valid = 1'b1;
			check(program_load_start_ready, "Program Loader accepts command list");
			@(posedge clk);
			@(negedge clk);
			program_load_start_valid = 1'b0;
		end
	endtask

	task automatic send_dma_beat(
		input logic [DMA_DATA_WIDTH-1:0] data,
		input logic [DMA_BYTES-1:0] keep,
		input logic last,
		input logic [7:0] id
	);
		begin
			@(negedge clk);
			program_ddr_read_rsp_data = data;
			program_ddr_read_rsp_keep = keep;
			program_ddr_read_rsp_last = last;
			program_ddr_read_rsp_id = id;
			program_ddr_read_rsp_error = 1'b0;
			program_ddr_read_rsp_valid = 1'b1;
			timeout = 0;
			while(!program_ddr_read_rsp_ready && timeout < 100)begin
				@(negedge clk);
				timeout = timeout + 1;
			end
			check(program_ddr_read_rsp_ready, "DMA response accepted under ready/valid");
			@(posedge clk);
			@(negedge clk);
			program_ddr_read_rsp_valid = 1'b0;
		end
	endtask

	// Send a complete Program Image with no bubble between accepted beats. When
	// ready drops, valid and the current payload remain stable until acceptance.
	task automatic send_dma_image_beats(
		input integer byte_count,
		input logic [287:0] image,
		input logic [7:0] id
	);
		integer byte_offset;
		integer beat_byte_count;
		integer byte_index;
		logic [DMA_DATA_WIDTH-1:0] beat_data;
		logic [DMA_BYTES-1:0] beat_keep;
		begin
			byte_offset = 0;
			@(negedge clk);
			program_ddr_read_rsp_valid = 1'b1;
			program_ddr_read_rsp_id = id;
			program_ddr_read_rsp_error = 1'b0;
			while(byte_offset < byte_count)begin
				beat_data = '0;
				beat_keep = '0;
				beat_byte_count = ((byte_count-byte_offset) < DMA_BYTES) ?
					(byte_count-byte_offset) : DMA_BYTES;
				for(byte_index = 0; byte_index < beat_byte_count; byte_index = byte_index + 1)begin
					beat_data[byte_index*8+:8] = image[(byte_offset+byte_index)*8+:8];
					beat_keep[byte_index] = 1'b1;
				end
				program_ddr_read_rsp_data = beat_data;
				program_ddr_read_rsp_keep = beat_keep;
				program_ddr_read_rsp_last = (byte_offset+beat_byte_count) == byte_count;
				timeout = 0;
				while(!program_ddr_read_rsp_ready && timeout < 100)begin
					@(negedge clk);
					timeout = timeout + 1;
				end
				check(program_ddr_read_rsp_ready, "DMA response beat accepted under ready/valid");
				@(posedge clk);
				byte_offset = byte_offset + beat_byte_count;
				if(byte_offset < byte_count)begin
					@(negedge clk);
				end
			end
			@(negedge clk);
			program_ddr_read_rsp_valid = 1'b0;
		end
	endtask

	task automatic serve_dma_image(
		input logic [63:0] expected_address,
		input integer byte_count,
		input logic [287:0] image
	);
		logic [7:0] dma_id;
		logic [63:0] held_address;
		logic [31:0] held_length;
		begin
			timeout = 0;
			while(!program_ddr_read_req_valid && timeout < 500)begin
				@(negedge clk);
				timeout = timeout + 1;
			end
			check(program_ddr_read_req_valid, "DMA command produced");
			held_address = program_ddr_read_req_address;
			held_length = program_ddr_read_req_length;
			dma_id = program_ddr_read_req_id;
			check(held_address == expected_address && held_length == byte_count,
				"ProgramImage source and byte count preserved");
			repeat(2)begin
				@(negedge clk);
				check(program_ddr_read_req_valid && program_ddr_read_req_address == held_address &&
					program_ddr_read_req_length == held_length && program_ddr_read_req_id == dma_id,
					"DMA command stable under backpressure");
			end
			program_ddr_read_req_ready = 1'b1;
			@(posedge clk);
			@(negedge clk);
			program_ddr_read_req_ready = 1'b0;
			send_dma_image_beats(byte_count, image, dma_id);
		end
	endtask

	task automatic wait_load_and_prime;
		begin
			timeout = 0;
			while(!program_load_complete && timeout < 2000)begin
				@(negedge clk);
				check(program_schedule_cycle == 0 && !program_running,
					"Load and write commit do not advance Schedule Cycle");
				timeout = timeout + 1;
			end
			check(program_load_complete, "All writes committed before Load Complete");
			timeout = 0;
			while(!program_ready && timeout < 2000)begin
				@(negedge clk);
				check(program_schedule_cycle == 0 && !program_running,
					"Parallel Prefetch does not advance Schedule Cycle");
				timeout = timeout + 1;
			end
			check(program_ready && !program_fault, "All primed Frontends reached Ready");
		end
	endtask

	// Execute the exact Phase-3 R1 image used by CModel. The relative cycle
	// counter starts at the first post-reset edge and is never offset afterward.
	task automatic run_phase3_r1;
		logic [287:0] image;
		begin
			image = {MEM_WORD_2, MEM_WORD_1, MEM_WORD_0};
			case_id = "phase3_r1";
			program_dependencies_ready = 1'b1;
			program_start_request = 1'b1;
			program_ddr_read_req_ready = 1'b1;
			r1_trace_enable = 1'b1;
			// CModel submit() presents one Program Reset cycle before the first
			// Host Adapter command.  Drive the same architectural input here so
			// cycle 0 is part of the zero-offset comparison rather than a reset
			// environment exception.
			program_reset = 1'b1;

			// Cycle 0 is idle at the command boundary. Cycles 1-4 accept LOAD,
			// WAIT_DMA, COMMIT_QUEUE, and END with no bubbles.
			@(negedge clk);
			program_reset = 1'b0;
			drive_r1_command(0, PROGRAM_LOADER_LOAD_IMEM, 64'h0000_0000_0006_0000, 32'd36,
				13'h0000, PROGRAM_FORMAT_96, PROGRAM_ENCODING_MACRO, 17'd0,
				1'b1, 1'b1, 16'd3, '0);
			@(negedge clk);
			program_start_request = 1'b0;
			drive_r1_command(1, PROGRAM_LOADER_WAIT_DMA, '0, '0,
				13'h0000, PROGRAM_FORMAT_96, PROGRAM_ENCODING_MACRO, 17'd0,
				1'b1, 1'b1, 16'd3, '0);
			@(negedge clk);
			drive_r1_command(2, PROGRAM_LOADER_COMMIT_QUEUE, '0, '0,
				13'h0000, PROGRAM_FORMAT_96, PROGRAM_ENCODING_MACRO, 17'd0,
				1'b1, 1'b1, 16'd3, '0);
			@(negedge clk);
			drive_r1_command(3, PROGRAM_LOADER_END, '0, '0,
				13'h0000, '0, '0, 17'd0, 1'b0, 1'b0, 16'd0, '0);
			@(negedge clk);
			program_cmd_write_valid = 1'b0;
			program_load_start_command_count = 4;
			program_load_start_valid = 1'b1;
			@(negedge clk);
			program_load_start_valid = 1'b0;

			// CModel presents the two DDR beats on cycles 10 and 11. The first
			// carries 32 bytes; the final beat carries the remaining four bytes.
			while(r1_cycle < 10) @(negedge clk);
			check(r1_dma_request_count == 1, "R1 issued exactly one DMA request before response");
			check(r1_dma_request_address == 64'h0000_0000_0006_0000,
				"R1 DMA source address matches CModel image");
			check(r1_dma_request_length == 32'd36,
				"R1 DMA byte count matches CModel image");
			program_ddr_read_rsp_valid = 1'b1;
			program_ddr_read_rsp_data = image[255:0];
			program_ddr_read_rsp_keep = '1;
			program_ddr_read_rsp_last = 1'b0;
			program_ddr_read_rsp_id = r1_dma_request_id;
			program_ddr_read_rsp_error = 1'b0;
			#1;
			check(program_ddr_read_rsp_ready, "R1 first DDR response beat ready on cycle 10");
			@(negedge clk);
			program_ddr_read_rsp_data = '0;
			program_ddr_read_rsp_data[31:0] = image[287:256];
			program_ddr_read_rsp_keep = '0;
			program_ddr_read_rsp_keep[3:0] = 4'hf;
			program_ddr_read_rsp_last = 1'b1;
			#1;
			check(program_ddr_read_rsp_ready, "R1 final DDR response beat ready on cycle 11");
			@(negedge clk);
			program_ddr_read_rsp_valid = 1'b0;
			program_ddr_read_rsp_last = 1'b0;

			while(r1_cycle < r1_expected_rows) @(negedge clk);
			#1;
			check(r1_trace_rows == r1_expected_rows,
				"R1/R2 emitted the requested PRE_POSEDGE rows");
			check(r1_command_write_count == 4, "R1 accepted four commands");
			check(r1_load_start_count == 1, "R1 accepted one load start");
			check(r1_load_txn_count == 1, "R1 accepted one load transaction");
			check(r1_config_enqueue_count == 1 && r1_config_dequeue_count == 1,
				"R1 Config FIFO accepted and retired one descriptor");
			check(r1_dma_final_response_count == 1, "R1 observed one final DMA response");
			check(r1_mem_program_count == 3, "R1 distributed three MEM program words");
			check(r1_mem_fetched_words == 3, "R1 fetched three MEM words");
			check(r1_mem_decoded_contexts == 2, "R1 decoded two MEM contexts");
			check(r1_mem_issued_count == 2, "R1 issued two MEM instructions");
			check(!program_fault, "R1 completed without Program fault");
			if(r1_trace_fd != 0) $fclose(r1_trace_fd);
			if(r1_stimulus_fd != 0) $fclose(r1_stimulus_fd);
			$display("PHASE3_R1_RTL_PASS rows=%0d commands=%0d load_txn=%0d config=%0d/%0d mem_program=%0d fetched=%0d decoded=%0d issued=%0d",
				r1_trace_rows, r1_command_write_count, r1_load_txn_count,
				r1_config_enqueue_count, r1_config_dequeue_count, r1_mem_program_count,
				r1_mem_fetched_words, r1_mem_decoded_contexts, r1_mem_issued_count);
			$finish;
		end
	endtask

	initial begin
		logic [287:0] mem_q0_image;
		logic [287:0] mem_q1_image;
		logic [287:0] mem_q103_image;
		logic [287:0] mem_q104_image;
		logic [287:0] mem_q105_image;
		logic [287:0] mem_q207_image;
		logic [287:0] cycle0_image;
		integer edge_before_switch;

		clk = 1'b0;
		rst_n = 1'b0;
		program_reset = 1'b0;
		program_cmd_write_valid = 1'b0;
		program_cmd_write_address = '0;
		program_cmd_write_opcode = '0;
		program_cmd_write_source_address = '0;
		program_cmd_write_byte_count = '0;
		program_cmd_write_destination = '0;
		program_cmd_write_format = '0;
		program_cmd_write_encoding_mode = '0;
		program_cmd_write_imem_base_address = '0;
		program_cmd_write_image_first = 1'b0;
		program_cmd_write_image_last = 1'b0;
		program_cmd_write_expected_word_count = '0;
		program_cmd_write_jump_address = '0;
		program_load_start_valid = 1'b0;
		program_load_start_command_count = '0;
		program_ddr_read_req_ready = 1'b0;
		program_ddr_read_rsp_valid = 1'b0;
		program_ddr_read_rsp_data = '0;
		program_ddr_read_rsp_keep = '0;
		program_ddr_read_rsp_last = 1'b0;
		program_ddr_read_rsp_id = '0;
		program_ddr_read_rsp_error = 1'b0;
		program_start_request = 1'b0;
		program_dependencies_ready = 1'b0;
		next_command = 0;
		checks = 0;
		timeout = 0;
		start_ack_count = 0;
		physical_clock_edges = 0;
		trace_fd = 0;
		stimulus_fd = 0;
		diagnostic_fd = 0;
		r1_trace_fd = 0;
		r1_stimulus_fd = 0;
		r1_only = $test$plusargs("R1_ONLY");
		r2_only = $test$plusargs("R2_ONLY");
		r3_only = $test$plusargs("R3_ONLY");
		r4_only = $test$plusargs("R4_ONLY");
		r1_trace_enable = 1'b0;
		r1_expected_rows = r4_only ? 92 : ((r2_only || r3_only) ? 89 : 91);
		r1_cycle = 0;
		r1_trace_rows = 0;
		r1_command_write_count = 0;
		r1_load_start_count = 0;
		r1_load_txn_count = 0;
		r1_prime_count = 0;
		r1_config_enqueue_count = 0;
		r1_config_dequeue_count = 0;
		r1_dma_request_count = 0;
		r1_dma_final_response_count = 0;
		r1_mem_program_count = 0;
		r1_mem_fetched_words = 0;
		r1_mem_decoded_contexts = 0;
		r1_mem_issued_count = 0;
		r1_dma_request_id = '0;
		r1_dma_request_address = '0;
		r1_dma_request_length = '0;
		r1_load_hold_valid = 1'b0;
		r1_config_hold_valid = 1'b0;
		r1_load_hold_payload = '0;
		r1_config_hold_payload = '0;
		case_id = "reset";
		if($value$plusargs("TRACE_PATH=%s", trace_path))begin
			trace_fd = $fopen(trace_path, "w");
		end
		if($value$plusargs("STIMULUS_PATH=%s", stimulus_path))begin
			stimulus_fd = $fopen(stimulus_path, "w");
		end
		if($value$plusargs("DIAGNOSTIC_PATH=%s", diagnostic_path))begin
			diagnostic_fd = $fopen(diagnostic_path, "w");
		end
		if($value$plusargs("R1_TRACE_PATH=%s", r1_trace_path))begin
			r1_trace_fd = $fopen(r1_trace_path, "w");
		end
		if($value$plusargs("R1_STIMULUS_PATH=%s", r1_stimulus_path))begin
			r1_stimulus_fd = $fopen(r1_stimulus_path, "w");
		end
		if(((trace_path != "") && (trace_fd == 0)) ||
			((stimulus_path != "") && (stimulus_fd == 0)) ||
			((diagnostic_path != "") && (diagnostic_fd == 0)) ||
			((r1_trace_path != "") && (r1_trace_fd == 0)) ||
			((r1_stimulus_path != "") && (r1_stimulus_fd == 0)))begin
			$fatal(1, "cannot open Phase 3 trace output");
		end
		if((r1_only || r2_only || r3_only || r4_only) &&
			((r1_trace_fd == 0) || (r1_stimulus_fd == 0)))begin
			$fatal(1, "R1_ONLY/R2_ONLY/R3_ONLY/R4_ONLY requires R1_TRACE_PATH and R1_STIMULUS_PATH");
		end
		if(r1_trace_fd != 0)begin
			write_r1_header();
		end

		repeat(5) @(posedge clk);
		@(negedge clk);
		rst_n = 1'b1;
		if(r1_only || r2_only || r3_only || r4_only)begin
			run_phase3_r1();
		end

		// The packed field order is Hemisphere[11], Kind[10:8], Target Index[7:0].
		check(program_destination_pack(PROGRAM_HEMISPHERE_EAST, PROGRAM_TARGET_MEM, 8'd0) == 13'h0000,
			"Destination encoding East MEM 0");
		check(program_destination_pack(PROGRAM_HEMISPHERE_EAST, PROGRAM_TARGET_MEM, 8'd103) == 13'h0067,
			"Destination encoding East MEM 103");
		check(program_destination_pack(PROGRAM_HEMISPHERE_WEST, PROGRAM_TARGET_MEM, 8'd0) == 13'h1000,
			"Destination encoding West MEM 0");
		check(program_destination_pack(PROGRAM_HEMISPHERE_WEST, PROGRAM_TARGET_MEM, 8'd103) == 13'h1067,
			"Destination encoding West MEM 103");
		check(program_destination_pack(PROGRAM_HEMISPHERE_EAST, PROGRAM_TARGET_MXM_COMPUTE, 8'd1) == 13'h0301,
			"Destination encoding East MXM Compute 1");
		check(program_destination_pack(PROGRAM_HEMISPHERE_WEST, PROGRAM_TARGET_MXM_LOAD, 8'd0) == 13'h1100,
			"Destination encoding West MXM Load 0");
		check(program_destination_pack(PROGRAM_HEMISPHERE_EAST, PROGRAM_TARGET_SXM_TRANSPOSE, 8'd0) == 13'h0500,
			"Destination encoding East SXM Transpose");
		check(program_destination_pack(PROGRAM_HEMISPHERE_EAST, PROGRAM_TARGET_SXM_PERMUTE, 8'd0) == 13'h0600,
			"Destination encoding East SXM Permute");

		// System Test C/D: load both hemispheres and all three MXM streams. No Queue is primed early.
		case_id = "routing_and_prefetch";
		mem_q0_image = make_mem_image(5, 100, 1);
		mem_q1_image = make_mem_image(5, 200, 2);
		mem_q103_image = make_mem_image(9, 500, 5);
		mem_q104_image = make_mem_image(7, 300, 3);
		mem_q105_image = make_mem_image(7, 400, 4);
		mem_q207_image = make_mem_image(11, 600, 6);
		next_command = 0;
		append_image_commands(64'h1000, 36,
			program_destination_pack(PROGRAM_HEMISPHERE_EAST, PROGRAM_TARGET_MEM, 8'd0), PROGRAM_FORMAT_96, 3);
		append_image_commands(64'h1100, 36,
			program_destination_pack(PROGRAM_HEMISPHERE_EAST, PROGRAM_TARGET_MEM, 8'd1), PROGRAM_FORMAT_96, 3);
		append_image_commands(64'h1400, 36,
			program_destination_pack(PROGRAM_HEMISPHERE_EAST, PROGRAM_TARGET_MEM, 8'd103), PROGRAM_FORMAT_96, 3);
		append_image_commands(64'h1200, 36,
			program_destination_pack(PROGRAM_HEMISPHERE_WEST, PROGRAM_TARGET_MEM, 8'd0), PROGRAM_FORMAT_96, 3);
		append_image_commands(64'h1300, 36,
			program_destination_pack(PROGRAM_HEMISPHERE_WEST, PROGRAM_TARGET_MEM, 8'd1), PROGRAM_FORMAT_96, 3);
		append_image_commands(64'h1500, 36,
			program_destination_pack(PROGRAM_HEMISPHERE_WEST, PROGRAM_TARGET_MEM, 8'd103), PROGRAM_FORMAT_96, 3);
		append_image_commands(64'h2000, 32,
			program_destination_pack(PROGRAM_HEMISPHERE_EAST, PROGRAM_TARGET_MXM_LOAD, 8'd0), PROGRAM_FORMAT_128, 2);
		append_image_commands(64'h2300, 32,
			program_destination_pack(PROGRAM_HEMISPHERE_EAST, PROGRAM_TARGET_MXM_LOAD, 8'd1), PROGRAM_FORMAT_128, 2);
		append_image_commands(64'h2400, 32,
			program_destination_pack(PROGRAM_HEMISPHERE_WEST, PROGRAM_TARGET_MXM_LOAD, 8'd0), PROGRAM_FORMAT_128, 2);
		append_image_commands(64'h2500, 32,
			program_destination_pack(PROGRAM_HEMISPHERE_WEST, PROGRAM_TARGET_MXM_LOAD, 8'd1), PROGRAM_FORMAT_128, 2);
		append_image_commands(64'h2100, 32,
			program_destination_pack(PROGRAM_HEMISPHERE_EAST, PROGRAM_TARGET_MXM_COMPUTE, 8'd0), PROGRAM_FORMAT_128, 2);
		append_image_commands(64'h2200, 32,
			program_destination_pack(PROGRAM_HEMISPHERE_EAST, PROGRAM_TARGET_MXM_DEQUANT, 8'd0), PROGRAM_FORMAT_128, 2);
		append_end();
		start_loader();
		check(!program_cmd_write_ready, "One active Program Load locks the command RAM");
		serve_dma_image(64'h1000, 36, mem_q0_image);
		serve_dma_image(64'h1100, 36, mem_q1_image);
		serve_dma_image(64'h1400, 36, mem_q103_image);
		serve_dma_image(64'h1200, 36, mem_q104_image);
		serve_dma_image(64'h1300, 36, mem_q105_image);
		serve_dma_image(64'h1500, 36, mem_q207_image);
		serve_dma_image(64'h2000, 32, make_mxm_image(MXM_LOAD));
		serve_dma_image(64'h2300, 32, make_mxm_image(MXM_LOAD));
		serve_dma_image(64'h2400, 32, make_mxm_image(MXM_LOAD));
		serve_dma_image(64'h2500, 32, make_mxm_image(MXM_LOAD));
		serve_dma_image(64'h2100, 32, make_mxm_image(MXM_COMPUTE));
		serve_dma_image(64'h2200, 32, make_mxm_image(MXM_DEQUANT));
		wait_load_and_prime();
		check(!program_start_ack && program_schedule_cycle == 0,
			"Ready does not imply START");
		check(u_dut.u_fu_subsystems.gen_hemisphere[0].u_mem_subsystem.gen_bank_frontend[0].u_frontend.u_imem.u_storage.memory_q[0] === MEM_WORD_0,
			"MEM global Queue 0 routed to East local Queue 0");
		check(u_dut.u_fu_subsystems.gen_hemisphere[0].u_mem_subsystem.gen_bank_frontend[1].u_frontend.u_imem.u_storage.memory_q[1] === mem_q1_image[96+:96],
			"MEM global Queue 1 routed to East local Queue 1");
		check(u_dut.u_fu_subsystems.gen_hemisphere[0].u_mem_subsystem.gen_bank_frontend[103].u_frontend.u_imem.u_storage.memory_q[1] === mem_q103_image[96+:96],
			"MEM global Queue 103 routed to East local Queue 103");
		check(u_dut.u_fu_subsystems.gen_hemisphere[1].u_mem_subsystem.gen_bank_frontend[0].u_frontend.u_imem.u_storage.memory_q[1] === mem_q104_image[96+:96],
			"MEM global Queue 104 routed to West local Queue 0");
		check(u_dut.u_fu_subsystems.gen_hemisphere[1].u_mem_subsystem.gen_bank_frontend[1].u_frontend.u_imem.u_storage.memory_q[1] === mem_q105_image[96+:96],
			"MEM global Queue 105 routed to West local Queue 1");
		check(u_dut.u_fu_subsystems.gen_hemisphere[1].u_mem_subsystem.gen_bank_frontend[103].u_frontend.u_imem.u_storage.memory_q[1] === mem_q207_image[96+:96],
			"MEM global Queue 207 routed to West local Queue 103");
		check(u_dut.u_fu_subsystems.gen_hemisphere[0].gen_mxm[0].u_mxm_subsystem.gen_frontend[0].u_frontend.u_imem.u_storage.memory_q[1] === MXM_LOAD,
			"MXM global Queue 0 routed to East local Queue 0");
		check(u_dut.u_fu_subsystems.gen_hemisphere[0].gen_mxm[1].u_mxm_subsystem.gen_frontend[0].u_frontend.u_imem.u_storage.memory_q[1] === MXM_LOAD,
			"MXM global Queue 1 routed to East local Queue 1");
		check(u_dut.u_fu_subsystems.gen_hemisphere[1].gen_mxm[0].u_mxm_subsystem.gen_frontend[0].u_frontend.u_imem.u_storage.memory_q[1] === MXM_LOAD,
			"MXM global Queue 2 routed to West local Queue 0");
		check(u_dut.u_fu_subsystems.gen_hemisphere[1].gen_mxm[1].u_mxm_subsystem.gen_frontend[0].u_frontend.u_imem.u_storage.memory_q[1] === MXM_LOAD,
			"MXM global Queue 3 routed to West local Queue 1");
		check(u_dut.u_fu_subsystems.gen_hemisphere[0].gen_mxm[0].u_mxm_subsystem.gen_frontend[1].u_frontend.u_imem.u_storage.memory_q[1] === MXM_COMPUTE,
			"MXM Compute uses an independent local iMEM");
		check(u_dut.u_fu_subsystems.gen_hemisphere[0].gen_mxm[0].u_mxm_subsystem.gen_frontend[2].u_frontend.u_imem.u_storage.memory_q[1] === MXM_DEQUANT,
			"MXM Dequant uses an independent local iMEM");

		// System Test A/B/E: reload two Bank-local images and accept an early START only after dependencies.
		case_id = "mem_decode_and_issue";
		pulse_program_reset();
		// Fixed Testbench deposits replace the removed architectural Host-to-MEM path.
		force u_dut.u_fu_subsystems.gen_hemisphere[0].u_mem_subsystem.gen_native_execution.u_native_mem.u_phase2a_data_plane.u_mem.gen_group[0].u_group.gen_slice[0].u_slice.gen_bank[0].u_logical_bank.gen_leaf[0].u_leaf.mem_array[100] = 64'h0101_0202_0303_0404;
		release u_dut.u_fu_subsystems.gen_hemisphere[0].u_mem_subsystem.gen_native_execution.u_native_mem.u_phase2a_data_plane.u_mem.gen_group[0].u_group.gen_slice[0].u_slice.gen_bank[0].u_logical_bank.gen_leaf[0].u_leaf.mem_array[100];
		force u_dut.u_fu_subsystems.gen_hemisphere[0].u_mem_subsystem.gen_native_execution.u_native_mem.u_phase2a_data_plane.u_mem.gen_group[0].u_group.gen_slice[0].u_slice.gen_bank[1].u_logical_bank.gen_leaf[0].u_leaf.mem_array[200] = 64'ha1a1_b2b2_c3c3_d4d4;
		release u_dut.u_fu_subsystems.gen_hemisphere[0].u_mem_subsystem.gen_native_execution.u_native_mem.u_phase2a_data_plane.u_mem.gen_group[0].u_group.gen_slice[0].u_slice.gen_bank[1].u_logical_bank.gen_leaf[0].u_leaf.mem_array[200];
		@(negedge clk);
		program_start_request = 1'b1;
		@(posedge clk);
		@(negedge clk);
		program_start_request = 1'b0;
		program_dependencies_ready = 1'b0;
		next_command = 0;
		append_image_commands(64'h3000, 36,
			program_destination_pack(PROGRAM_HEMISPHERE_EAST, PROGRAM_TARGET_MEM, 8'd0), PROGRAM_FORMAT_96, 3);
		append_image_commands(64'h3100, 36,
			program_destination_pack(PROGRAM_HEMISPHERE_EAST, PROGRAM_TARGET_MEM, 8'd1), PROGRAM_FORMAT_96, 3);
		append_end();
		start_loader();
		serve_dma_image(64'h3000, 36, mem_q0_image);
		serve_dma_image(64'h3100, 36, mem_q1_image);
		wait_load_and_prime();
		check(start_ack_count == 0 && !program_running,
			"Early START remains pending while dependencies are false");
		@(negedge clk);
		program_dependencies_ready = 1'b1;
		timeout = 0;
		while(start_ack_count == 0 && timeout < 50)begin
			@(negedge clk);
			timeout = timeout + 1;
		end
		check(start_ack_count == 1 && program_running,
			"Unified START begins all Frontends on one boundary");
		check(program_schedule_cycle == 0, "START exposes Schedule Cycle 0");
		timeout = 0;
		while(!(program_schedule_cycle == 5 && u_dut.local_mem_issue_valid[0] &&
			u_dut.local_mem_issue_valid[1]) && timeout < 100)begin
			@(negedge clk);
			timeout = timeout + 1;
		end
		check(timeout < 100, "Both MEM Banks issue together at Schedule Cycle 5");
		check(u_dut.local_mem_issue_instruction[15+:13] == 13'd100 &&
			u_dut.local_mem_issue_instruction[lpu_pkg::MEM_INSTRUCTION_WIDTH+15+:13] == 13'd200,
			"Bank-local Queue instructions retain addresses 100 and 200");
		check(u_dut.local_mem_issue_valid[1:0] == 2'b11 &&
			u_dut.u_fu_subsystems.gen_hemisphere[0].u_mem_subsystem.gen_native_execution.native_issue_valid[1:0] == 2'b11,
			"Frontend Queues reach the actual MEM FU issue interface");
		timeout = 0;
		while(!(u_dut.u_fu_subsystems.gen_hemisphere[0].u_mem_subsystem.gen_native_execution.u_native_mem.mem_producer_valid_o[0] &&
			u_dut.u_fu_subsystems.gen_hemisphere[0].u_mem_subsystem.gen_native_execution.u_native_mem.mem_producer_valid_o[4]) && timeout < 20)begin
			@(negedge clk);
			timeout = timeout + 1;
		end
		check(timeout < 20, "Both Native Banks complete their READ pipeline");
		check(u_dut.u_fu_subsystems.gen_hemisphere[0].u_mem_subsystem.gen_native_execution.u_native_mem.mem_producer_data_o[0+:64] == 64'h0101_0202_0303_0404,
			"Bank 0 executed READ 100 against its SRAM");
		check(u_dut.u_fu_subsystems.gen_hemisphere[0].u_mem_subsystem.gen_native_execution.u_native_mem.mem_producer_data_o[4*64+:64] == 64'ha1a1_b2b2_c3c3_d4d4,
			"Bank 1 executed READ 200 against its SRAM");
		timeout = 0;
		while(!program_done && !program_fault && timeout < 200)begin
			@(negedge clk);
			timeout = timeout + 1;
		end
		check(program_done && !program_fault, "Two-Column Program reaches Done without fault");

		// System Test F/H: switch Program without resetting the physical SRAM and issue at Cycle 0.
		case_id = "cycle0_program_switch";
		edge_before_switch = physical_clock_edges;
		pulse_program_reset();
		check(physical_clock_edges > edge_before_switch, "Program switch keeps physical time alive");
		#1;
		check(u_dut.u_fu_subsystems.gen_hemisphere[0].u_mem_subsystem.gen_native_execution.u_native_mem.u_phase2a_data_plane.u_mem.gen_group[0].u_group.gen_slice[0].u_slice.gen_bank[0].u_logical_bank.gen_leaf[0].u_leaf.mem_array[100] == 64'h0101_0202_0303_0404,
			"Program switch preserves shared physical SRAM contents");
		cycle0_image = make_mem_image(0, 10, 3);
		start_ack_count = 0;
		program_dependencies_ready = 1'b1;
		@(negedge clk);
		program_start_request = 1'b1;
		@(posedge clk);
		@(negedge clk);
		program_start_request = 1'b0;
		next_command = 0;
		append_image_commands(64'h4000, 36,
			program_destination_pack(PROGRAM_HEMISPHERE_EAST, PROGRAM_TARGET_MEM, 8'd0), PROGRAM_FORMAT_96, 3);
		append_end();
		start_loader();
		serve_dma_image(64'h4000, 36, cycle0_image);
		wait_load_and_prime();
		timeout = 0;
		while(!(program_schedule_cycle == 0 && u_dut.local_mem_issue_valid[0]) && timeout < 100)begin
			@(negedge clk);
			timeout = timeout + 1;
		end
		check(timeout < 100 && start_ack_count == 1,
			"Second Program emits its first instruction at Schedule Cycle 0");
		check(u_dut.local_mem_issue_instruction[15+:13] == 13'd10,
			"Cycle-0 instruction belongs to the new Program");

		// System Test G: descriptor checks reject an invalid Queue and an overflowing iMEM image.
		case_id = "descriptor_faults";
		pulse_program_reset();
		write_command(0, PROGRAM_LOADER_LOAD_IMEM, 64'h5000, 36,
			program_destination_pack(PROGRAM_HEMISPHERE_EAST, PROGRAM_TARGET_MEM, 8'd104),
			PROGRAM_FORMAT_96, 3, 17'd0, PROGRAM_ENCODING_MACRO);
		@(negedge clk);
		check(program_fault && program_fault_code == PROGRAM_FAULT_DESCRIPTOR,
			"Out-of-range MEM Target Index is rejected");
		pulse_program_reset();
		write_command(0, PROGRAM_LOADER_LOAD_IMEM, 64'h5050, 32,
			program_destination_pack(PROGRAM_HEMISPHERE_EAST, PROGRAM_TARGET_MXM_LOAD, 8'd2),
			PROGRAM_FORMAT_128, 2, 17'd0, PROGRAM_ENCODING_MACRO);
		@(negedge clk);
		check(program_fault && program_fault_code == PROGRAM_FAULT_DESCRIPTOR,
			"Out-of-range MXM Target Index is rejected");
		pulse_program_reset();
		write_command(0, PROGRAM_LOADER_LOAD_IMEM, 64'h5080, 32,
			program_destination_pack(PROGRAM_HEMISPHERE_EAST, PROGRAM_TARGET_RESERVED, 8'd0),
			PROGRAM_FORMAT_128, 2, 17'd0, PROGRAM_ENCODING_MACRO);
		@(negedge clk);
		check(program_fault && program_fault_code == PROGRAM_FAULT_DESCRIPTOR,
			"Reserved Target Kind is rejected");
		pulse_program_reset();
		write_command(0, PROGRAM_LOADER_LOAD_IMEM, 64'h5090, 32,
			program_destination_pack(PROGRAM_HEMISPHERE_EAST, PROGRAM_TARGET_VXM, 8'd0),
			PROGRAM_FORMAT_128, 2, 17'd0, PROGRAM_ENCODING_MACRO);
		@(negedge clk);
		check(program_fault && program_fault_code == PROGRAM_FAULT_DESCRIPTOR,
			"VXM Program Load remains explicitly unconnected");
		pulse_program_reset();
		write_command(0, PROGRAM_LOADER_LOAD_IMEM, 64'h50a0, 32,
			program_destination_pack(PROGRAM_HEMISPHERE_EAST, PROGRAM_TARGET_SXM_TRANSPOSE, 8'd0),
			PROGRAM_FORMAT_128, 2, 17'd0, PROGRAM_ENCODING_MACRO);
		@(negedge clk);
		check(program_fault && program_fault_code == PROGRAM_FAULT_DESCRIPTOR,
			"SXM Transpose Program Load remains explicitly unconnected");
		pulse_program_reset();
		write_command(0, PROGRAM_LOADER_LOAD_IMEM, 64'h50b0, 32,
			program_destination_pack(PROGRAM_HEMISPHERE_EAST, PROGRAM_TARGET_SXM_PERMUTE, 8'd0),
			PROGRAM_FORMAT_128, 2, 17'd0, PROGRAM_ENCODING_MACRO);
		@(negedge clk);
		check(program_fault && program_fault_code == PROGRAM_FAULT_DESCRIPTOR,
			"SXM Permute Program Load remains explicitly unconnected");
		pulse_program_reset();
		write_command(0, PROGRAM_LOADER_LOAD_IMEM, 64'h5100, 36,
			program_destination_pack(PROGRAM_HEMISPHERE_EAST, PROGRAM_TARGET_MEM, 8'd0),
			PROGRAM_FORMAT_96, 3, 17'd15, PROGRAM_ENCODING_MACRO);
		@(negedge clk);
		check(program_fault && program_fault_code == PROGRAM_FAULT_DESCRIPTOR,
			"ProgramImage exceeding local iMEM capacity is rejected");
		pulse_program_reset();
		write_command(0, PROGRAM_LOADER_LOAD_IMEM, 64'h5200, 36,
			program_destination_pack(PROGRAM_HEMISPHERE_EAST, PROGRAM_TARGET_MEM, 8'd0),
			PROGRAM_FORMAT_96, 3, 17'd0, PROGRAM_ENCODING_FU3D);
		@(negedge clk);
		check(program_fault && program_fault_code == PROGRAM_FAULT_DESCRIPTOR,
			"FU3D encoding is rejected by the Macro-only Program Control path");

		#1;
		if(trace_fd != 0) $fclose(trace_fd);
		if(stimulus_fd != 0) $fclose(stimulus_fd);
		if(diagnostic_fd != 0) $fclose(diagnostic_fd);
		$display("LPU_TOP_FU_SUBSYSTEM_PROGRAM PASS checks=%0d physical_edges=%0d dma_width=%0d", checks, physical_clock_edges, DMA_DATA_WIDTH);
		$finish;
	end
endmodule

