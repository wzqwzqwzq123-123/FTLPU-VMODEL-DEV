`timescale 1ns/1ps
// Observe native command metadata and count actual SRF tap samples before retiring a job.
module lpu_sxm_writetap_completion #(
	parameter integer T = 4,
	parameter integer DEPTH = 4096
) (
	input wire clk_i,
	input wire rst_ni,
	input wire job_valid_i,
	input wire fp32_i,
	input wire [15:0] matrices_i,

	// Admission and drain status cover both SXM engines and all four target MEM groups.
	input wire core_ready,
	input wire writer_ready,
	input wire core_busy,
	input wire writer_busy,
	input wire core_fault,
	input wire writer_fault,
	input wire [3:0] mem_busy,
	input wire [3:0] mem_fault,
	input wire transport_fault,
	input wire [31:0] read_issue_valid_i,

	// wi/wc pack [group 0..3][bank/Stream position 0..7], with 1 valid bit / 32 command bits per slot.
	// target/target_addr pack [group][physical Tile], with 1 valid bit / 15 SRAM row-address bits per entry.
	// tap_data_valid_i/tap_sample_o pack [group][bank][physical Tile], Tile varying fastest.
	// wi/wc carry group launch commands; target metadata identifies taps expected this cycle.
	input wire [31:0] wi,
	input wire [1023:0] wc,
	input wire [4*T-1:0] target,
	input wire [4*T*15-1:0] target_addr,
	input wire [32*T-1:0] tap_data_valid_i,
	output wire job_ready_o,
	output wire start,
	output wire busy_o,
	output wire fault_o,
	output reg pending_q,
	output reg bad_q,
	output reg monitor_bad,
	output wire [32*T-1:0] tap_sample_o,
	output reg [31:0] committed_segments_o,
	output reg done_o
);
	// expected_q counts byte-stream segments, not matrices or issued commands.
	reg [31:0] expected_q;
	wire [4*T-1:0] monitor_valid;
	wire [4*T*32-1:0] monitor_word;

	// start accepts one job into both engines; busy remains asserted through MEM drain.
	assign job_ready_o = core_ready && writer_ready && !pending_q && !(|mem_busy) && !fault_o;
	assign start = job_valid_i && job_ready_o;
	assign busy_o = pending_q || core_busy || writer_busy || (|mem_busy);
	assign fault_o = bad_q || core_fault || writer_fault || (|mem_fault) || transport_fault;

	// monitor_group=MEM group 0..3; monitor_tile=physical Tile 0..T-1; neither indexes matrix elements.
	// Metadata advances one register per Tile after Tile zero, mirroring native MEM command hops.
	for(genvar monitor_group = 0; monitor_group < 4; monitor_group = monitor_group + 1)begin : g_monitor
		for(genvar monitor_tile = 0; monitor_tile < T; monitor_tile = monitor_tile + 1)begin : g_tile
			if(monitor_tile == 0)begin
				// Observe bank 0's representative command: 8 valids and 8*32=256 command bits per group.
				assign monitor_valid[monitor_group*T+monitor_tile] = wi[monitor_group*8];
				assign monitor_word[(monitor_group*T+monitor_tile)*32+:32] = wc[monitor_group*256+:32];
			end
			else begin
				reg valid_q;
				reg [31:0] word_q;
				// Capture metadata only; SRF continues to own and transport the payload.
				always @(posedge clk_i) begin
					if(!rst_ni)begin
						valid_q <= 0;
						word_q <= 0;
					end
					else begin
						valid_q <= monitor_valid[monitor_group*T+monitor_tile-1];
						word_q <= monitor_word[(monitor_group*T+monitor_tile-1)*32+:32];
					end
				end
				assign monitor_valid[monitor_group*T+monitor_tile] = valid_q;
				assign monitor_word[(monitor_group*T+monitor_tile)*32+:32] = word_q;
			end

			// monitor_bank selects a MEM-local bank/Stream position (0..7); flat tap index=(group*8+bank)*T+Tile.
			// Count a tap only when a valid in-range WriteTap command meets actual SRF data.
			for(genvar monitor_bank = 0; monitor_bank < 8; monitor_bank = monitor_bank + 1)begin : g_tap
				// monitor_word packs [group][Tile][32-bit command], so (group*T+Tile)*32 is a BIT offset.
				wire [31:0] command = monitor_word[(monitor_group*T+monitor_tile)*32+:32];
				assign tap_sample_o[(monitor_group*8+monitor_bank)*T+monitor_tile] = pending_q && monitor_valid[monitor_group*T+monitor_tile] && command[31] && command[2:0] == 1 && command[8] && int'(command[29:15]) < DEPTH && tap_data_valid_i[(monitor_group*8+monitor_bank)*T+monitor_tile];
			end
		end
	end

	// The combinational population count adds no extra tap-sampling pipeline stage.
	localparam integer TAP_COUNT = 32*T, COUNT_BITS = $clog2(TAP_COUNT+1);
	wire [COUNT_BITS-1:0] ncommit = COUNT_BITS'($countones(tap_sample_o));
	// g/t/b repeat the MEM group, physical Tile and local bank axes; they are not input/output matrix rows or columns.
	integer g, t, b;
	reg [31:0] command;

	// Compare observed taps and command address/stream tags against the writer's target metadata.
	always @* begin
		monitor_bad = 0;
		command = 0;
		for(g = 0; g < 4; g = g + 1)begin
			for(t = 0; t < T; t = t + 1)begin
				// Command index=(group*T+Tile); target_addr adds 15 address bits, while tap indices also include bank b.
				command = monitor_word[(g*T+t)*32+:32];
				for(b = 0; b < 8; b = b + 1)begin
					if(pending_q && (tap_sample_o[(g*8+b)*T+t] != target[g*T+t]))begin
						monitor_bad = 1;
					end
					if(target[g*T+t] && (command[29:15] != target_addr[(g*T+t)*15+:15] || command[7:3] != 5'(g*8)))begin
						monitor_bad = 1;
					end
				end
			end
		end
	end

	// Retire only after both engines, MEM and command metadata drain with the exact segment count.
	always @(posedge clk_i) begin
		if(!rst_ni)begin
			pending_q <= 0;
			bad_q <= 0;
			expected_q <= 0;
			committed_segments_o <= 0;
			done_o <= 0;
		end
		else begin
			done_o <= 0;
			if((job_valid_i && !job_ready_o) || ((|read_issue_valid_i) && pending_q) || monitor_bad)begin
				bad_q <= 1;
			end
			// Admission clears the committed count and captures the full byte-segment expectation.
			if(start)begin
				pending_q <= 1;
				// Each matrix produces T source block columns*T destination Tiles*8 output block rows*2/4 element bytes.
				// Each counted segment is one Stream beat carrying the same byte position across 8 output Lanes.
				expected_q <= 32'(matrices_i)*32'(8*T*T)*(fp32_i ? 32'd4 : 32'd2);
				committed_segments_o <= 0;
			end
			else if(pending_q)begin
				committed_segments_o <= committed_segments_o + 32'(ncommit);
				// Completion compares the registered pre-edge count; this preserves its existing latency.
				if(!core_busy && !writer_busy && !(|mem_busy) && !(|monitor_valid) && !fault_o && !monitor_bad)begin
					if(committed_segments_o == expected_q)begin
						done_o <= 1;
						pending_q <= 0;
					end
					else begin
						bad_q <= 1;
					end
				end
			end
		end
	end
endmodule
