// Program Transfer accepts one command-sequencer transaction atomically, receives
// the corresponding DMA response stream, rebuilds Program Words and buffers them
// until Program Distribution is ready.
module lpu_program_transfer_path #(
	parameter integer DMA_DATA_WIDTH = 256,
	parameter integer CONFIG_FIFO_DEPTH = 16,
	parameter integer DMA_OUTSTANDING_DEPTH = 16,
	parameter integer DMA_RX_FIFO_DEPTH = 16,
	parameter integer REASSEMBLY_BUFFER_BYTES = 64,
	parameter integer WORD_FIFO_DEPTH = 8,
	parameter integer IMEM_DEPTH = 65536
) (
	input logic clk_i,
	input logic rst_ni,
	input logic clear_i,

	input logic transaction_valid_i,
	output logic transaction_ready_o,
	input logic [63:0] transaction_source_address_i,
	input logic [31:0] transaction_byte_count_i,
	input logic [1:0] transaction_scope_i,
	input logic [11:0] transaction_destination_i,
	input logic [1:0] transaction_format_i,
	input logic [16:0] transaction_imem_base_address_i,
	input logic transaction_image_first_i,
	input logic transaction_image_last_i,
	input logic [15:0] transaction_expected_word_count_i,
	input logic [7:0] transaction_dma_id_i,

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

	output logic word_valid_o,
	input logic word_ready_i,
	output logic [127:0] word_data_o,
	output logic [3:0] word_strb_o,
	output logic [1:0] word_scope_o,
	output logic [11:0] word_destination_o,
	output logic [16:0] word_imem_address_o,
	output logic word_last_o,

	output logic idle_o,
	output logic [31:0] generated_word_count_o,
	output logic fault_o,
	output logic [5:0] fault_code_o
);
	import lpu_program_load_pkg::*;

	logic internal_rst_ni;
	logic config_enqueue_valid;
	logic config_enqueue_ready;
	logic config_dequeue_valid;
	logic config_dequeue_ready;
	logic [31:0] config_byte_count;
	logic [1:0] config_scope;
	logic [11:0] config_destination;
	logic [1:0] config_format;
	logic [16:0] config_imem_base_address;
	logic config_image_first;
	logic config_image_last;
	logic [15:0] config_expected_word_count;
	logic [7:0] config_dma_id;
	logic config_empty;

	logic dma_command_valid;
	logic dma_command_ready;
	logic response_valid;
	logic response_ready;
	logic [DMA_DATA_WIDTH-1:0] response_data;
	logic [DMA_DATA_WIDTH/8-1:0] response_keep;
	logic response_last;
	logic [7:0] response_id;
	logic response_error;
	logic dma_idle;
	logic dma_fault;
	logic [5:0] dma_fault_code;

	logic reassembler_word_valid;
	logic reassembler_word_ready;
	logic [127:0] reassembler_word_data;
	logic [3:0] reassembler_word_strb;
	logic [1:0] reassembler_word_scope;
	logic [11:0] reassembler_word_destination;
	logic [16:0] reassembler_word_imem_address;
	logic reassembler_word_last;
	logic reassembler_idle;
	logic reassembler_fault;
	logic [5:0] reassembler_fault_code;
	logic word_fifo_empty;
	logic [31:0] generated_word_count_q;

	assign internal_rst_ni = rst_ni && !clear_i;

	// The DMA command and matching reassembly metadata are accepted together.
	assign transaction_ready_o = dma_command_ready && config_enqueue_ready;
	assign dma_command_valid = transaction_valid_i && config_enqueue_ready;
	assign config_enqueue_valid = transaction_valid_i && dma_command_ready;

	lpu_program_config_fifo #(
		.DEPTH(CONFIG_FIFO_DEPTH)
	) u_config_fifo (
		.clk_i,
		.rst_ni(internal_rst_ni),
		.enqueue_valid_i(config_enqueue_valid),
		.enqueue_ready_o(config_enqueue_ready),
		.enqueue_source_address_i(transaction_source_address_i),
		.enqueue_byte_count_i(transaction_byte_count_i),
		.enqueue_scope_i(transaction_scope_i),
		.enqueue_destination_i(transaction_destination_i),
		.enqueue_format_i(transaction_format_i),
		.enqueue_imem_base_address_i(transaction_imem_base_address_i),
		.enqueue_image_first_i(transaction_image_first_i),
		.enqueue_image_last_i(transaction_image_last_i),
		.enqueue_expected_word_count_i(transaction_expected_word_count_i),
		.enqueue_dma_id_i(transaction_dma_id_i),
		.dequeue_valid_o(config_dequeue_valid),
		.dequeue_ready_i(config_dequeue_ready),
		.dequeue_source_address_o(),
		.dequeue_byte_count_o(config_byte_count),
		.dequeue_scope_o(config_scope),
		.dequeue_destination_o(config_destination),
		.dequeue_format_o(config_format),
		.dequeue_imem_base_address_o(config_imem_base_address),
		.dequeue_image_first_o(config_image_first),
		.dequeue_image_last_o(config_image_last),
		.dequeue_expected_word_count_o(config_expected_word_count),
		.dequeue_dma_id_o(config_dma_id),
		.level_o(),
		.empty_o(config_empty),
		.full_o()
	);

	lpu_instruction_dma #(
		.DMA_DATA_WIDTH(DMA_DATA_WIDTH),
		.DMA_ID_WIDTH(8),
		.OUTSTANDING_DEPTH(DMA_OUTSTANDING_DEPTH),
		.RX_FIFO_DEPTH(DMA_RX_FIFO_DEPTH)
	) u_instruction_dma (
		.clk_i,
		.rst_ni(internal_rst_ni),
		.command_valid_i(dma_command_valid),
		.command_ready_o(dma_command_ready),
		.command_address_i(transaction_source_address_i),
		.command_length_i(transaction_byte_count_i),
		.command_id_i(transaction_dma_id_i),
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
		.response_valid_o(response_valid),
		.response_ready_i(response_ready),
		.response_data_o(response_data),
		.response_keep_o(response_keep),
		.response_last_o(response_last),
		.response_id_o(response_id),
		.response_error_o(response_error),
		.outstanding_o(),
		.idle_o(dma_idle),
		.fault_o(dma_fault),
		.fault_code_o(dma_fault_code)
	);

	lpu_program_reassembler #(
		.DMA_DATA_WIDTH(DMA_DATA_WIDTH),
		.BUFFER_BYTES(REASSEMBLY_BUFFER_BYTES),
		.IMEM_DEPTH(IMEM_DEPTH)
	) u_reassembler (
		.clk_i,
		.rst_ni(internal_rst_ni),
		.config_valid_i(config_dequeue_valid),
		.config_ready_o(config_dequeue_ready),
		.config_byte_count_i(config_byte_count),
		.config_scope_i(config_scope),
		.config_destination_i(config_destination),
		.config_format_i(config_format),
		.config_imem_base_address_i(config_imem_base_address),
		.config_image_first_i(config_image_first),
		.config_image_last_i(config_image_last),
		.config_expected_word_count_i(config_expected_word_count),
		.config_dma_id_i(config_dma_id),
		.response_valid_i(response_valid),
		.response_ready_o(response_ready),
		.response_data_i(response_data),
		.response_keep_i(response_keep),
		.response_last_i(response_last),
		.response_id_i(response_id),
		.response_error_i(response_error),
		.word_valid_o(reassembler_word_valid),
		.word_ready_i(reassembler_word_ready),
		.word_data_o(reassembler_word_data),
		.word_strb_o(reassembler_word_strb),
		.word_scope_o(reassembler_word_scope),
		.word_destination_o(reassembler_word_destination),
		.word_imem_address_o(reassembler_word_imem_address),
		.word_image_last_o(reassembler_word_last),
		.received_byte_count_o(),
		.generated_word_count_o(),
		.idle_o(reassembler_idle),
		.fault_o(reassembler_fault),
		.fault_code_o(reassembler_fault_code)
	);

	lpu_program_word_fifo #(
		.DEPTH(WORD_FIFO_DEPTH)
	) u_word_fifo (
		.clk_i,
		.rst_ni(internal_rst_ni),
		.enqueue_valid_i(reassembler_word_valid),
		.enqueue_ready_o(reassembler_word_ready),
		.enqueue_data_i(reassembler_word_data),
		.enqueue_strb_i(reassembler_word_strb),
		.enqueue_scope_i(reassembler_word_scope),
		.enqueue_destination_i(reassembler_word_destination),
		.enqueue_imem_address_i(reassembler_word_imem_address),
		.enqueue_last_i(reassembler_word_last),
		.dequeue_valid_o(word_valid_o),
		.dequeue_ready_i(word_ready_i),
		.dequeue_data_o(word_data_o),
		.dequeue_strb_o(word_strb_o),
		.dequeue_scope_o(word_scope_o),
		.dequeue_destination_o(word_destination_o),
		.dequeue_imem_address_o(word_imem_address_o),
		.dequeue_last_o(word_last_o),
		.level_o(),
		.empty_o(word_fifo_empty),
		.full_o()
	);

	assign idle_o = dma_idle && config_empty && reassembler_idle && word_fifo_empty;
	assign generated_word_count_o = generated_word_count_q;
	assign fault_o = dma_fault || reassembler_fault;
	assign fault_code_o = dma_fault ? dma_fault_code :
		(reassembler_fault ? reassembler_fault_code : PROGRAM_FAULT_NONE);

	always_ff @(posedge clk_i or negedge internal_rst_ni) begin
		if(!internal_rst_ni)begin
			generated_word_count_q <= '0;
		end
		else if(reassembler_word_valid && reassembler_word_ready)begin
			generated_word_count_q <= generated_word_count_q + 1'b1;
		end
	end
endmodule
