`timescale 1ns/1ps

module lpu_mxm_macro_frontends_tb;
	localparam integer STREAM_COUNT = 5;

	logic clk;
	logic rst_n;
	logic run_enable [0:STREAM_COUNT-1];
	logic prime [0:STREAM_COUNT-1];
	logic [31:0] schedule_cycle [0:STREAM_COUNT-1];
	logic fetch_valid [0:STREAM_COUNT-1];
	logic fetch_ready [0:STREAM_COUNT-1];
	logic [127:0] fetch_word [0:STREAM_COUNT-1];
	logic fetch_last [0:STREAM_COUNT-1];
	logic issue_valid [0:STREAM_COUNT-1];
	logic issue_ready [0:STREAM_COUNT-1];
	logic [48:0] issue_instruction [0:STREAM_COUNT-1];
	logic [31:0] issue_cycle [0:STREAM_COUNT-1];
	logic decoder_done [0:STREAM_COUNT-1];
	logic [2:0] word_level [0:STREAM_COUNT-1];
	logic [2:0] context_level [0:STREAM_COUNT-1];
	logic [2:0] active_count [0:STREAM_COUNT-1];
	logic idle [0:STREAM_COUNT-1];
	logic prime_ready [0:STREAM_COUNT-1];
	logic fault [0:STREAM_COUNT-1];
	logic [4:0] fault_code [0:STREAM_COUNT-1];
	integer issue_count [0:STREAM_COUNT-1];
	integer fail_count;
	integer init_index;

	genvar stream_index;
	generate
		for(stream_index = 0; stream_index < STREAM_COUNT; stream_index = stream_index + 1)begin: gen_frontend
			lpu_mxm_macro_frontend #(
				.QUEUE_KIND(stream_index),
				.ACTIVE_CONTEXTS(4),
				.WORD_FIFO_DEPTH(4),
				.CONTEXT_FIFO_DEPTH(4)
			) u_frontend (
				.clk_i(clk),
				.rst_ni(rst_n),
				.run_i(run_enable[stream_index]),
				.prime_i(prime[stream_index]),
				.schedule_cycle_i(schedule_cycle[stream_index]),
				.fetch_word_valid_i(fetch_valid[stream_index]),
				.fetch_word_ready_o(fetch_ready[stream_index]),
				.fetch_word_i(fetch_word[stream_index]),
				.fetch_word_last_i(fetch_last[stream_index]),
				.issue_valid_o(issue_valid[stream_index]),
				.issue_ready_i(issue_ready[stream_index]),
				.issue_instruction_o(issue_instruction[stream_index]),
				.issue_cycle_o(issue_cycle[stream_index]),
				.decoder_done_o(decoder_done[stream_index]),
				.word_fifo_level_o(word_level[stream_index]),
				.context_fifo_level_o(context_level[stream_index]),
				.active_count_o(active_count[stream_index]),
				.idle_o(idle[stream_index]),
				.prime_ready_o(prime_ready[stream_index]),
				.fault_o(fault[stream_index]),
				.fault_code_o(fault_code[stream_index])
			);
		end
	endgenerate

	always #5 clk = ~clk;

	task automatic push_bits(
		inout logic [127:0] bits,
		inout integer cursor,
		input logic [63:0] value,
		input integer width
	);
		integer bit_index;
		begin
			for(bit_index = 0; bit_index < width; bit_index = bit_index + 1)begin
				bits[cursor + bit_index] = value[bit_index];
			end
			cursor = cursor + width;
		end
	endtask

	task automatic drive_fetch(input integer index, input logic [127:0] data, input logic last);
		begin
			@(negedge clk);
			fetch_valid[index] = 1'b1;
			fetch_word[index] = data;
			fetch_last[index] = last;
			do @(posedge clk); while(!fetch_ready[index]);
			@(negedge clk);
			fetch_valid[index] = 1'b0;
			fetch_word[index] = '0;
			fetch_last[index] = 1'b0;
		end
	endtask

	task automatic load_one_macro(
		input integer index,
		input logic [48:0] native_instruction,
		input logic [31:0] start_cycle
	);
		logic [127:0] bits;
		integer cursor;
		integer native_width;
		integer operand_width;
		begin
			bits = '0;
			cursor = 0;
			native_width = lpu_mxm_isa_pkg::macro_native_bits(index);
			operand_width = lpu_mxm_isa_pkg::macro_operand_bits(index);
			push_bits(bits, cursor, 0, 3);
			push_bits(bits, cursor, start_cycle, 32);
			push_bits(bits, cursor, 0, operand_width);
			push_bits(bits, cursor, 0, 1);
			push_bits(bits, cursor, 0, 1);
			push_bits(bits, cursor, native_instruction, native_width);
			push_bits(bits, cursor, 0, 2);
			push_bits(bits, cursor, lpu_mxm_isa_pkg::MXM_INDUCTION_NONE, 2);
			drive_fetch(index, 128'h15, 1'b0);
			drive_fetch(index, bits, 1'b1);
		end
	endtask

	function automatic logic [48:0] expected_native(input integer index);
		case(index)
			lpu_mxm_isa_pkg::MXM_QUEUE_LOAD: expected_native = 49'h2;
			lpu_mxm_isa_pkg::MXM_QUEUE_COMPUTE: expected_native = 49'h7;
			lpu_mxm_isa_pkg::MXM_QUEUE_DEQUANT: expected_native = 49'h1;
			lpu_mxm_isa_pkg::MXM_QUEUE_PARAM_LOAD: expected_native = 49'h1;
			default: expected_native = 49'h8;
		endcase
	endfunction

	initial begin
		integer cycle_value;
		logic expected_valid;
		clk = 1'b0;
		rst_n = 1'b0;
		fail_count = 0;
		for(init_index = 0; init_index < STREAM_COUNT; init_index = init_index + 1)begin
			run_enable[init_index] = 1'b0;
			prime[init_index] = 1'b0;
			schedule_cycle[init_index] = '0;
			fetch_valid[init_index] = 1'b0;
			fetch_word[init_index] = '0;
			fetch_last[init_index] = 1'b0;
			issue_ready[init_index] = 1'b1;
			issue_count[init_index] = 0;
		end
		repeat(3) @(posedge clk);
		rst_n = 1'b1;

		for(init_index = 0; init_index < STREAM_COUNT; init_index = init_index + 1)begin
			load_one_macro(init_index, expected_native(init_index), 32'(3 + init_index));
			prime[init_index] = 1'b1;
		end

		for(init_index = 0; init_index < STREAM_COUNT; init_index = init_index + 1)begin
			wait(prime_ready[init_index] || fault[init_index]);
			if(fault[init_index])begin
				$display("FAIL frontend %0d prime fault code=%0d", init_index, fault_code[init_index]);
				fail_count = fail_count + 1;
			end
		end

		for(cycle_value = 0; cycle_value <= 7; cycle_value = cycle_value + 1)begin
			@(negedge clk);
			for(init_index = 0; init_index < STREAM_COUNT; init_index = init_index + 1)begin
				schedule_cycle[init_index] = cycle_value;
				run_enable[init_index] = 1'b1;
			end
			#1;
			for(init_index = 0; init_index < STREAM_COUNT; init_index = init_index + 1)begin
				expected_valid = cycle_value == (3 + init_index);
				if(issue_valid[init_index] !== expected_valid)begin
					$display("FAIL frontend %0d cycle %0d valid=%0b expected=%0b", init_index, cycle_value,
						issue_valid[init_index], expected_valid);
					fail_count = fail_count + 1;
				end
				if(expected_valid)begin
					issue_count[init_index] = issue_count[init_index] + 1;
					if(issue_cycle[init_index] != cycle_value || issue_instruction[init_index] != expected_native(init_index))begin
						$display("FAIL frontend %0d issue instruction=%h cycle=%0d", init_index,
							issue_instruction[init_index], issue_cycle[init_index]);
						fail_count = fail_count + 1;
					end
				end
			end
			@(posedge clk);
		end

		@(negedge clk);
		for(init_index = 0; init_index < STREAM_COUNT; init_index = init_index + 1)begin
			run_enable[init_index] = 1'b0;
			if(issue_count[init_index] != 1 || fault[init_index])begin
				$display("FAIL frontend %0d count=%0d fault=%0b", init_index, issue_count[init_index], fault[init_index]);
				fail_count = fail_count + 1;
			end
		end
		if(fail_count == 0) $display("MXM_MACRO_FRONTENDS_TB PASS");
		else $fatal(1, "MXM_MACRO_FRONTENDS_TB FAIL count=%0d", fail_count);
		$finish;
	end
endmodule
