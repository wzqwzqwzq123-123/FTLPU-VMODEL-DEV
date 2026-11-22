`timescale 1ns/1ps

module lpu_mxm_macro_decoder_tb;
	localparam integer DECODER_COUNT = 10;
	localparam integer BAD_COMPUTE_INDEX = 5;
	localparam integer ESCAPE_COMPACT_INDEX = 6;
	localparam integer DICTIONARY_INDEX = 7;
	localparam integer ESCAPE_WIDE_INDEX = 8;
	localparam integer EXTENDED_INDEX = 9;

	logic clk;
	logic rst_n;
	logic word_valid [0:DECODER_COUNT-1];
	logic word_ready [0:DECODER_COUNT-1];
	logic [127:0] word_data [0:DECODER_COUNT-1];
	logic word_last [0:DECODER_COUNT-1];
	logic context_valid [0:DECODER_COUNT-1];
	logic context_ready [0:DECODER_COUNT-1];
	logic [48:0] context_instruction [0:DECODER_COUNT-1];
	logic [31:0] context_start_cycle [0:DECODER_COUNT-1];
	logic [31:0] context_inner_count [0:DECODER_COUNT-1];
	logic [31:0] context_inner_interval [0:DECODER_COUNT-1];
	logic signed [31:0] context_inner_stride [0:DECODER_COUNT-1];
	logic [31:0] context_outer_count [0:DECODER_COUNT-1];
	logic [31:0] context_outer_interval [0:DECODER_COUNT-1];
	logic signed [31:0] context_outer_stride [0:DECODER_COUNT-1];
	logic [1:0] context_target [0:DECODER_COUNT-1];
	logic [12:0] context_operand [0:DECODER_COUNT-1];
	logic done [0:DECODER_COUNT-1];
	logic fault [0:DECODER_COUNT-1];
	logic [3:0] fault_code [0:DECODER_COUNT-1];
	integer fail_count;
	integer init_index;

	genvar decoder_index;
	generate
		for(decoder_index = 0; decoder_index < DECODER_COUNT; decoder_index = decoder_index + 1)begin: gen_decoder
			localparam integer KIND = decoder_index < 5 ? decoder_index : lpu_mxm_isa_pkg::MXM_QUEUE_COMPUTE;
			lpu_mxm_macro_decoder_core #(
				.QUEUE_KIND(KIND)
			) u_decoder (
				.clk_i(clk),
				.rst_ni(rst_n),
				.word_valid_i(word_valid[decoder_index]),
				.word_ready_o(word_ready[decoder_index]),
				.word_i(word_data[decoder_index]),
				.word_last_i(word_last[decoder_index]),
				.context_valid_o(context_valid[decoder_index]),
				.context_ready_i(context_ready[decoder_index]),
				.context_instruction_o(context_instruction[decoder_index]),
				.context_start_cycle_o(context_start_cycle[decoder_index]),
				.context_inner_count_o(context_inner_count[decoder_index]),
				.context_inner_interval_o(context_inner_interval[decoder_index]),
				.context_inner_stride_o(context_inner_stride[decoder_index]),
				.context_outer_count_o(context_outer_count[decoder_index]),
				.context_outer_interval_o(context_outer_interval[decoder_index]),
				.context_outer_stride_o(context_outer_stride[decoder_index]),
				.context_induction_target_o(context_target[decoder_index]),
				.context_operand_o(context_operand[decoder_index]),
				.done_o(done[decoder_index]),
				.fault_o(fault[decoder_index]),
				.fault_code_o(fault_code[decoder_index])
			);
		end
	endgenerate

	always #5 clk = ~clk;

	task automatic push_bits(
		inout logic [511:0] packed_bits,
		inout integer cursor,
		input logic [63:0] value,
		input integer width
	);
		integer bit_index;
		begin
			for(bit_index = 0; bit_index < width; bit_index = bit_index + 1)begin
				packed_bits[cursor + bit_index] = value[bit_index];
			end
			cursor = cursor + width;
		end
	endtask

	task automatic send_word(input integer index, input logic [127:0] data, input logic last);
		begin
			@(negedge clk);
			word_valid[index] = 1'b1;
			word_data[index] = data;
			word_last[index] = last;
			do @(posedge clk); while(!word_ready[index]);
			@(negedge clk);
			word_valid[index] = 1'b0;
			word_data[index] = '0;
			word_last[index] = 1'b0;
		end
	endtask

	task automatic send_program(
		input integer index,
		input logic [511:0] packed_bits,
		input integer packed_width,
		input integer macro_count
	);
		integer word_index;
		integer word_count;
		logic [127:0] payload_word;
		begin
			send_word(index, 128'((macro_count << 4) | 8'h05), 1'b0);
			word_count = (packed_width + 127) / 128;
			for(word_index = 0; word_index < word_count; word_index = word_index + 1)begin
				payload_word = packed_bits[word_index * 128 +: 128];
				send_word(index, payload_word, word_index == (word_count - 1));
			end
		end
	endtask

	task automatic build_compact_program(
		input integer kind,
		input logic [48:0] native_instruction,
		input logic [31:0] start_cycle,
		input logic [12:0] operand,
		input logic [1:0] target,
		input integer run_length,
		input integer dictionary_count,
		input logic [21:0] dictionary_start_delta,
		input logic signed [13:0] dictionary_operand_delta,
		input integer delta_mode,
		input logic [31:0] escape_start_delta,
		input logic signed [31:0] escape_operand_delta,
		output logic [511:0] packed_bits,
		output integer packed_width
	);
		integer native_bits;
		integer operand_bits;
		begin
			packed_bits = '0;
			packed_width = 0;
			native_bits = lpu_mxm_isa_pkg::macro_native_bits(kind);
			operand_bits = lpu_mxm_isa_pkg::macro_operand_bits(kind);
			push_bits(packed_bits, packed_width, dictionary_count, 3);
			if(dictionary_count != 0)begin
				push_bits(packed_bits, packed_width, dictionary_start_delta, 22);
				push_bits(packed_bits, packed_width, dictionary_operand_delta, 14);
			end
			push_bits(packed_bits, packed_width, start_cycle, 32);
			push_bits(packed_bits, packed_width, operand, operand_bits);
			push_bits(packed_bits, packed_width, run_length > 1, 1);
			if(run_length > 1) push_bits(packed_bits, packed_width, run_length - 1, 16);
			push_bits(packed_bits, packed_width, 0, 1);
			push_bits(packed_bits, packed_width, native_instruction, native_bits);
			push_bits(packed_bits, packed_width, 0, 2);
			push_bits(packed_bits, packed_width, target, 2);

			if(run_length > 1)begin
				if(delta_mode == 0)begin
					push_bits(packed_bits, packed_width, 0, 1);
				end
				else begin
					push_bits(packed_bits, packed_width, 5'b11111, 5);
					push_bits(packed_bits, packed_width, delta_mode == 2, 1);
					if(delta_mode == 2)begin
						push_bits(packed_bits, packed_width, escape_start_delta, 32);
						push_bits(packed_bits, packed_width, escape_operand_delta, 32);
					end
					else begin
						push_bits(packed_bits, packed_width, escape_start_delta, 22);
						push_bits(packed_bits, packed_width, escape_operand_delta, 14);
					end
				end
			end
		end
	endtask

	task automatic build_extended_program(output logic [511:0] packed_bits, output integer packed_width);
		begin
			packed_bits = '0;
			packed_width = 0;
			push_bits(packed_bits, packed_width, 0, 3);
			push_bits(packed_bits, packed_width, 32'd20, 32);
			push_bits(packed_bits, packed_width, 13'd2, 6);
			push_bits(packed_bits, packed_width, 0, 1);
			push_bits(packed_bits, packed_width, 1, 1);
			push_bits(packed_bits, packed_width, 49'h1, 7);
			push_bits(packed_bits, packed_width, 32'd3, 32);
			push_bits(packed_bits, packed_width, 32'd2, 32);
			push_bits(packed_bits, packed_width, 32'd1, 32);
			push_bits(packed_bits, packed_width, 32'd2, 32);
			push_bits(packed_bits, packed_width, 32'd8, 32);
			push_bits(packed_bits, packed_width, 32'd16, 32);
			push_bits(packed_bits, packed_width, lpu_mxm_isa_pkg::MXM_INDUCTION_OPERAND0, 2);
		end
	endtask

	task automatic accept_and_check_context(
		input integer index,
		input logic [48:0] expected_instruction,
		input logic [31:0] expected_start_cycle,
		input logic [12:0] expected_operand,
		input logic [1:0] expected_target,
		input logic [31:0] expected_inner_count,
		input logic [31:0] expected_inner_interval,
		input logic signed [31:0] expected_inner_stride,
		input logic [31:0] expected_outer_count,
		input logic [31:0] expected_outer_interval,
		input logic signed [31:0] expected_outer_stride
	);
		logic [287:0] held_context;
		integer wait_cycles;
		begin
			wait_cycles = 0;
			while(!context_valid[index] && !fault[index] && (wait_cycles < 100))begin
				@(posedge clk);
				wait_cycles = wait_cycles + 1;
			end
			if(fault[index] || !context_valid[index])begin
				$display("FAIL decoder %0d did not produce Context, fault=%0b code=%0d", index, fault[index], fault_code[index]);
				fail_count = fail_count + 1;
			end
			else begin
				if(context_instruction[index] !== expected_instruction || context_start_cycle[index] !== expected_start_cycle ||
					context_operand[index] !== expected_operand || context_target[index] !== expected_target ||
					context_inner_count[index] !== expected_inner_count || context_inner_interval[index] !== expected_inner_interval ||
					context_inner_stride[index] !== expected_inner_stride || context_outer_count[index] !== expected_outer_count ||
					context_outer_interval[index] !== expected_outer_interval || context_outer_stride[index] !== expected_outer_stride)begin
					$display("FAIL decoder %0d Context mismatch", index);
					fail_count = fail_count + 1;
				end
				held_context = {context_instruction[index], context_start_cycle[index], context_inner_count[index],
					context_inner_interval[index], context_inner_stride[index], context_outer_count[index],
					context_outer_interval[index], context_outer_stride[index], context_target[index], context_operand[index]};
				repeat(3)begin
					@(posedge clk);
					if(!context_valid[index] || held_context !== {context_instruction[index], context_start_cycle[index],
						context_inner_count[index], context_inner_interval[index], context_inner_stride[index],
						context_outer_count[index], context_outer_interval[index], context_outer_stride[index],
						context_target[index], context_operand[index]})begin
						$display("FAIL decoder %0d Context changed under backpressure", index);
						fail_count = fail_count + 1;
					end
				end
				@(negedge clk);
				context_ready[index] = 1'b1;
				@(posedge clk);
				@(negedge clk);
				context_ready[index] = 1'b0;
			end
		end
	endtask

	initial begin
		logic [511:0] packed_bits;
		integer packed_width;
		logic [48:0] native_instruction;
		clk = 1'b0;
		rst_n = 1'b0;
		fail_count = 0;
		for(init_index = 0; init_index < DECODER_COUNT; init_index = init_index + 1)begin
			word_valid[init_index] = 1'b0;
			word_data[init_index] = '0;
			word_last[init_index] = 1'b0;
			context_ready[init_index] = 1'b0;
		end
		repeat(3) @(posedge clk);
		rst_n = 1'b1;

		for(init_index = 0; init_index < 5; init_index = init_index + 1)begin
			case(init_index)
				lpu_mxm_isa_pkg::MXM_QUEUE_LOAD: native_instruction = 49'h2;
				lpu_mxm_isa_pkg::MXM_QUEUE_COMPUTE: native_instruction = 49'h7;
				lpu_mxm_isa_pkg::MXM_QUEUE_DEQUANT: native_instruction = 49'h1;
				lpu_mxm_isa_pkg::MXM_QUEUE_PARAM_LOAD: native_instruction = 49'h1;
				default: native_instruction = 49'h8;
			endcase
			build_compact_program(init_index, native_instruction, 32'(3 + init_index), 13'd0,
				lpu_mxm_isa_pkg::MXM_INDUCTION_NONE, 1, 0, '0, '0, 0, '0, '0, packed_bits, packed_width);
			send_program(init_index, packed_bits, packed_width, 1);
			accept_and_check_context(init_index, native_instruction, 32'(3 + init_index), 13'd0,
				lpu_mxm_isa_pkg::MXM_INDUCTION_NONE, 1, 1, 0, 1, 1, 0);
		end

		build_compact_program(lpu_mxm_isa_pkg::MXM_QUEUE_COMPUTE, 49'h3f, 32'd3, 13'd0,
			lpu_mxm_isa_pkg::MXM_INDUCTION_NONE, 1, 0, '0, '0, 0, '0, '0, packed_bits, packed_width);
		send_program(BAD_COMPUTE_INDEX, packed_bits, packed_width, 1);
		wait(fault[BAD_COMPUTE_INDEX]);
		if(fault_code[BAD_COMPUTE_INDEX] != 4'd6) fail_count = fail_count + 1;

		build_compact_program(lpu_mxm_isa_pkg::MXM_QUEUE_COMPUTE, 49'h1, 32'd3, 13'd1,
			lpu_mxm_isa_pkg::MXM_INDUCTION_OPERAND0, 2, 0, '0, '0, 1, 32'd2, 32'sd1, packed_bits, packed_width);
		send_program(ESCAPE_COMPACT_INDEX, packed_bits, packed_width, 2);
		accept_and_check_context(ESCAPE_COMPACT_INDEX, 49'h3, 32'd3, 13'd1,
			lpu_mxm_isa_pkg::MXM_INDUCTION_OPERAND0, 1, 1, 0, 1, 1, 0);
		accept_and_check_context(ESCAPE_COMPACT_INDEX, 49'h5, 32'd5, 13'd2,
			lpu_mxm_isa_pkg::MXM_INDUCTION_OPERAND0, 1, 1, 0, 1, 1, 0);

		build_compact_program(lpu_mxm_isa_pkg::MXM_QUEUE_COMPUTE, 49'h1, 32'd7, 13'd1,
			lpu_mxm_isa_pkg::MXM_INDUCTION_OPERAND0, 2, 1, 22'd4, 14'sd1, 0, '0, '0, packed_bits, packed_width);
		send_program(DICTIONARY_INDEX, packed_bits, packed_width, 2);
		accept_and_check_context(DICTIONARY_INDEX, 49'h3, 32'd7, 13'd1,
			lpu_mxm_isa_pkg::MXM_INDUCTION_OPERAND0, 1, 1, 0, 1, 1, 0);
		accept_and_check_context(DICTIONARY_INDEX, 49'h5, 32'd11, 13'd2,
			lpu_mxm_isa_pkg::MXM_INDUCTION_OPERAND0, 1, 1, 0, 1, 1, 0);

		build_compact_program(lpu_mxm_isa_pkg::MXM_QUEUE_COMPUTE, 49'h1, 32'd12, 13'd3,
			lpu_mxm_isa_pkg::MXM_INDUCTION_OPERAND0, 2, 0, '0, '0, 2, 32'd5, -32'sd1, packed_bits, packed_width);
		send_program(ESCAPE_WIDE_INDEX, packed_bits, packed_width, 2);
		accept_and_check_context(ESCAPE_WIDE_INDEX, 49'h7, 32'd12, 13'd3,
			lpu_mxm_isa_pkg::MXM_INDUCTION_OPERAND0, 1, 1, 0, 1, 1, 0);
		accept_and_check_context(ESCAPE_WIDE_INDEX, 49'h5, 32'd17, 13'd2,
			lpu_mxm_isa_pkg::MXM_INDUCTION_OPERAND0, 1, 1, 0, 1, 1, 0);

		build_extended_program(packed_bits, packed_width);
		send_program(EXTENDED_INDEX, packed_bits, packed_width, 1);
		accept_and_check_context(EXTENDED_INDEX, 49'h5, 32'd20, 13'd2,
			lpu_mxm_isa_pkg::MXM_INDUCTION_OPERAND0, 3, 2, 1, 2, 8, 16);

		repeat(5) @(posedge clk);
		if(fail_count == 0) $display("MXM_MACRO_DECODER_TB PASS");
		else $fatal(1, "MXM_MACRO_DECODER_TB FAIL count=%0d", fail_count);
		$finish;
	end
endmodule
