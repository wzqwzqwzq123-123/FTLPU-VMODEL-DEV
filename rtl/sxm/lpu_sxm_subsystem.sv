// Own the Triangle payload engine, native WriteTap scheduling and committed-write completion.
module lpu_sxm_subsystem #(
	parameter integer T = 4,
	parameter integer TIMER_BITS = 16,
	parameter integer DEPTH = 4096,
	localparam integer TILE_INDEX_WIDTH = $clog2(T)
) (
	input logic clk_i,
	input logic rst_ni,

	// A batch starts both engines only after completion control accepts the job.
	input logic batch_job_i,
	input logic [1:0] batch_mode_i,
	input logic [1:0] batch_dtype_i,
	input logic [15:0] batch_count_i,
	// Lane map packs [physical destination Tile][output Lane 0..7][3-bit input row/Lane selector].
	// Tile map packs [INPUT block row / logical OUTPUT block column][TILE_INDEX_WIDTH-bit physical destination Tile].
	input logic [T*24-1:0] batch_lane_map_i,
	input logic [T*TILE_INDEX_WIDTH-1:0] batch_tile_map_i,
	output logic batch_ready_o,
	output logic batch_fault_o,

	// cap_valid/lane_valid use [source Tile] / [source Tile][input Lane]; only 8*32 low bits of each 2048-bit capture slice are read.
	// Output blocks pack [physical destination Tile][output block row 0..7][output Lane/column 0..7][32-bit element].
	// block_matrix identifies the batch matrix; block_column retains the INPUT block-column id (OUTPUT block row after transpose).
	// Capture rows into Triangle storage and expose the transformed blocks consumed by the writer.
	input logic [T-1:0] batch_cap_valid_i,
	input logic [T*8-1:0] batch_lane_valid_i,
	input logic [T*2048-1:0] batch_cap_data_i,
	output logic [T-1:0] batch_cap_accept_o,
	output logic [T-1:0] batch_block_valid_o,
	output logic [T-1:0] batch_block_fp32_o,
	output logic [T-1:0] batch_block_vector_o,
	output logic [T*2048-1:0] batch_block_data_o,
	output logic [T*16-1:0] batch_block_matrix_o,
	output logic [T*TILE_INDEX_WIDTH-1:0] batch_block_column_o,

	// Streams pack [physical output Tile][Stream 0..31][Lane 0..7][8-bit byte], giving 64 bits/Stream.
	// Commands pack [MEM group 0..3][bank 0..7][32-bit command]; targets pack [group][Tile][15-bit address].
	// Tap-valid/sample indices are (group*8+bank)*T+Tile; these are hardware endpoints, not matrix coordinates.
	// Native MEM/SRF status gates admission and confirms actual tap samples.
	input logic resources_ready_i,
	input logic [14:0] base_i,
	input logic [3:0] mem_busy_i,
	input logic [3:0] mem_fault_i,
	input logic transport_fault_i,
	input logic [31:0] read_issue_valid_i,
	input logic [32*T-1:0] tap_data_valid_i,
	output logic [T*32-1:0] stream_valid_o,
	output logic [T*2048-1:0] stream_data_o,
	output logic [31:0] mem_issue_valid_o,
	output logic [1023:0] mem_issue_o,
	output logic [4*T-1:0] target_tap_o,
	output logic [4*T*15-1:0] target_address_o,
	output logic [32*T-1:0] tap_sample_o,
	output logic [31:0] committed_segments_o,
	output logic done_o,
	output logic busy_o,
	output logic completion_fault_o,

	// Expose existing engine and monitor status without adding a register boundary.
	output logic pending_o,
	output logic writer_busy_o,
	output logic writer_fault_o,
	output logic bad_o,
	output logic monitor_bad_o
);
	// start_w is the accepted batch pulse shared by the Triangle engine and writer.
	logic start_w;
	logic core_ready_w;
	logic core_busy_w;
	logic writer_ready_w;
	logic writer_busy_w;
	logic writer_fault_w;
	logic pending_w;
	logic bad_w;
	logic monitor_bad_w;
	logic [T-1:0] block_ready_w;

	assign pending_o = pending_w;
	assign writer_busy_o = writer_busy_w;
	assign writer_fault_o = writer_fault_w;
	assign bad_o = bad_w;
	assign monitor_bad_o = monitor_bad_w;

	// Triangle storage performs the retained SXM row/block transform and destination permutation.
	sxm_triangle_core #(
		.T(T),
		.TIMER_BITS(TIMER_BITS)
	) u_triangle_core (
		.clk_i,
		.rst_ni,
		.job_valid_i(start_w),
		.job_ready_o(core_ready_w),
		.mode_i(batch_mode_i),
		.dtype_i(batch_dtype_i),
		.count_i(batch_count_i),
		.lane_map_i(batch_lane_map_i),
		.tile_map_i(batch_tile_map_i),
		.cap_valid_i(batch_cap_valid_i),
		.cap_lane_valid_i(batch_lane_valid_i),
		.cap_data_i(batch_cap_data_i),
		.cap_accept_o(batch_cap_accept_o),
		.block_ready_i(block_ready_w),
		.block_valid_o(batch_block_valid_o),
		.block_fp32_o(batch_block_fp32_o),
		.block_vector_o(batch_block_vector_o),
		.block_data_o(batch_block_data_o),
		.block_matrix_o(batch_block_matrix_o),
		.block_column_o(batch_block_column_o),
		.busy_o(core_busy_w),
		.fault_o(batch_fault_o)
	);

	// WriteTap integration accepts matrix mode only, even though the standalone core also supports vectors.
	lpu_sxm_triangle_mem_adapter #(
		.T(T),
		.DEPTH(DEPTH)
	) u_writer (
		.clk_i,
		.rst_ni,
		.job_valid_i(start_w),
		.fp32_i(batch_dtype_i[0]),
		.resources_ready_i(resources_ready_i && batch_mode_i == 0 && batch_dtype_i <= 1),
		.matrices_i(batch_count_i),
		.base_i,
		.tile_map_i(batch_tile_map_i),
		.job_ready_o(writer_ready_w),
		.block_valid_i(batch_block_valid_o),
		.block_fp32_i(batch_block_fp32_o),
		.block_data_i(batch_block_data_o),
		.block_matrix_i(batch_block_matrix_o),
		.block_column_i(batch_block_column_o),
		.block_ready_o(block_ready_w),
		.stream_valid_o,
		.stream_data_o,
		.mem_issue_valid_o,
		.mem_issue_o,
		.target_tap_o,
		.target_address_o,
		.busy_o(writer_busy_w),
		.fault_o(writer_fault_w)
	);

	// Completion couples engine admission and holds the batch pending until native writes drain.
	lpu_sxm_writetap_completion #(
		.T(T),
		.DEPTH(DEPTH)
	) u_completion (
		.clk_i,
		.rst_ni,
		.job_valid_i(batch_job_i),
		.fp32_i(batch_dtype_i[0]),
		.matrices_i(batch_count_i),
		.core_ready(core_ready_w),
		.writer_ready(writer_ready_w),
		.core_busy(core_busy_w),
		.writer_busy(writer_busy_w),
		.core_fault(batch_fault_o),
		.writer_fault(writer_fault_w),
		.mem_busy(mem_busy_i),
		.mem_fault(mem_fault_i),
		.transport_fault(transport_fault_i),
		.read_issue_valid_i,
		.wi(mem_issue_valid_o),
		.wc(mem_issue_o),
		.target(target_tap_o),
		.target_addr(target_address_o),
		.tap_data_valid_i,
		.job_ready_o(batch_ready_o),
		.start(start_w),
		.busy_o,
		.fault_o(completion_fault_o),
		.pending_q(pending_w),
		.bad_q(bad_w),
		.monitor_bad(monitor_bad_w),
		.tap_sample_o,
		.committed_segments_o,
		.done_o
	);
endmodule
