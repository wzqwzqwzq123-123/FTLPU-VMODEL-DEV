module lpu_vxm_macro_decoder #(
	parameter integer LOCAL_QUEUE = 0
) (
	input  logic        clk_i,
	input  logic        rst_ni,

	// One VXM RUN_2D packet contains three 96-bit physical iMEM words.
	input  logic        word_valid_i,
	output logic        word_ready_o,
	input  logic [95:0] word_i,
	input  logic        word_last_i,

	// The compact instruction is the native 64-bit control plus FP32 immediate.
	output logic        context_valid_o,
	input  logic        context_ready_i,
	output logic [95:0] context_instruction_o,
	output logic [31:0] context_wait_cycle_o,
	output logic [31:0] context_inner_count_o,
	output logic [31:0] context_inner_interval_o,
	output logic [31:0] context_outer_count_o,
	output logic [31:0] context_outer_interval_o,

	output logic        done_o,
	output logic        fault_o,
	output logic [3:0]  fault_code_o
);
	localparam logic [3:0] FAULT_NONE = 4'd0;
	localparam logic [3:0] FAULT_HEADER = 4'd1;
	localparam logic [3:0] FAULT_RESERVED = 4'd2;
	localparam logic [3:0] FAULT_TRUNCATED = 4'd3;
	localparam logic [3:0] FAULT_SCHEDULE = 4'd4;
	localparam logic [3:0] FAULT_INSTRUCTION = 4'd5;

	logic [95:0] packet_word_q [0:2];
	logic [1:0] word_index_q;
	logic decode_pending_q;
	logic packet_last_q;

	logic context_valid_q;
	logic [95:0] context_instruction_q;
	logic [31:0] context_wait_cycle_q;
	logic [31:0] context_inner_count_q;
	logic [31:0] context_inner_interval_q;
	logic [31:0] context_outer_count_q;
	logic [31:0] context_outer_interval_q;

	logic done_q;
	logic fault_q;
	logic [3:0] fault_code_q;

	// Logical packet payload closes the four-bit subtype hole in word zero.
	logic [259:0] payload_w;
	logic header_illegal_w;
	logic reserved_bits_illegal_w;
	logic schedule_illegal_w;
	logic instruction_illegal_w;
	logic [16:0] inner_count_w;
	logic [16:0] outer_count_w;
	logic [23:0] inner_interval_w;
	logic [23:0] outer_interval_w;
	logic [63:0] inner_cycle_span_w;
	logic [63:0] total_cycle_span_w;
	logic [63:0] control_w;
	logic [3:0] opcode_w;
	logic [3:0] lhs_kind_w;
	logic [3:0] rhs_kind_w;
	logic [1:0] chain_depth_w;
	logic [31:0] repeat_count_w;
	logic output_enable_w;
	logic accumulator_reset_w;
	logic accumulator_write_w;
	logic local_scalar_write_w;
	integer chain_length_w;
	logic chain_head_w;
	logic chain_tail_w;
	logic opcode_position_illegal_w;
	logic operand_position_illegal_w;
	logic accumulator_operand_illegal_w;
	logic word_fire;
	logic context_fire;

	function automatic integer chain_length(
		input logic [1:0] encoded_depth
	);
		begin
			case(encoded_depth)
				2'd0: chain_length = 2;
				2'd1: chain_length = 4;
				2'd2: chain_length = 8;
				default: chain_length = 0;
			endcase
		end
	endfunction

	function automatic logic stream_operand(
		input logic [3:0] kind
	);
		begin
			stream_operand = (kind == 4'd4) || (kind == 4'd5) ||
				(kind == 4'd8);
		end
	endfunction

	initial begin
		if((LOCAL_QUEUE < 0) || (LOCAL_QUEUE > 7))begin
			$error("LOCAL_QUEUE must identify VXM logical Queue 0..7");
		end
	end

	assign word_fire = word_valid_i && word_ready_o;
	assign context_fire = context_valid_q && context_ready_i;
	assign word_ready_o = !fault_q && !decode_pending_q && !context_valid_q;

	assign context_valid_o = context_valid_q;
	assign context_instruction_o = context_instruction_q;
	assign context_wait_cycle_o = context_wait_cycle_q;
	assign context_inner_count_o = context_inner_count_q;
	assign context_inner_interval_o = context_inner_interval_q;
	assign context_outer_count_o = context_outer_count_q;
	assign context_outer_interval_o = context_outer_interval_q;
	assign done_o = done_q;
	assign fault_o = fault_q;
	assign fault_code_o = fault_code_q;

	// Convert the three physical words into the contiguous CModel payload numbering.
	always_comb begin
		payload_w = '0;
		for(integer bit_index = 0; bit_index < 260; bit_index++)begin
			if(bit_index < 80)begin
				payload_w[bit_index] = packet_word_q[0][bit_index+8];
			end
			else if(bit_index < 84)begin
				payload_w[bit_index] = packet_word_q[0][bit_index+12];
			end
			else if(bit_index < 172)begin
				payload_w[bit_index] = packet_word_q[1][bit_index-76];
			end
			else begin
				payload_w[bit_index] = packet_word_q[2][bit_index-164];
			end
		end
	end

	// Header, loop and current Compact-v1 checks mirror the CModel codec. The
	// physical channel identifies LOCAL_QUEUE, so no Stage index is encoded.
	always_comb begin
		header_illegal_w = (packet_word_q[0][7:0] != 8'h43)
			|| (packet_word_q[1][7:0] != 8'h47)
			|| (packet_word_q[2][7:0] != 8'h4b)
			|| (packet_word_q[0][91:88] != 4'd2);
		reserved_bits_illegal_w = |payload_w[259:200];

		inner_count_w = {1'b0, payload_w[39:24]} + 17'd1;
		outer_count_w = {1'b0, payload_w[55:40]} + 17'd1;
		inner_interval_w = payload_w[79:56];
		outer_interval_w = payload_w[103:80];
		inner_cycle_span_w = payload_w[39:24] * inner_interval_w;
		total_cycle_span_w = inner_cycle_span_w + payload_w[55:40] * outer_interval_w;
		schedule_illegal_w = (inner_interval_w == 0) || (outer_interval_w == 0)
			|| ((outer_count_w > 1) && (outer_interval_w <= inner_cycle_span_w))
			|| (total_cycle_span_w >= 64'd16777216);

		control_w = payload_w[167:104];
		opcode_w = control_w[3:0];
		lhs_kind_w = {control_w[52], control_w[6:4]};
		rhs_kind_w = {control_w[53], control_w[9:7]};
		output_enable_w = control_w[13];
		accumulator_reset_w = control_w[14];
		accumulator_write_w = control_w[15];
		chain_depth_w = control_w[18:17];
		repeat_count_w = control_w[50:19];
		local_scalar_write_w = control_w[51];
		chain_length_w = chain_length(chain_depth_w);
		chain_head_w = 1'b0;
		chain_tail_w = 1'b0;
		if(chain_length_w != 0)begin
			chain_head_w = ((LOCAL_QUEUE % chain_length_w) == 0);
			chain_tail_w = ((LOCAL_QUEUE % chain_length_w) ==
				(chain_length_w-1));
		end

		opcode_position_illegal_w = ((opcode_w == 6) && ((LOCAL_QUEUE % 4) != 1)) ||
			(((opcode_w == 7) || (opcode_w == 8) || (opcode_w == 9)) &&
			 ((LOCAL_QUEUE % 4) != 3));
		operand_position_illegal_w = 1'b0;
		if(chain_head_w)begin
			operand_position_illegal_w =
				(!(stream_operand(lhs_kind_w) || (lhs_kind_w == 6) ||
				   (lhs_kind_w == 7))) ||
				(!(stream_operand(rhs_kind_w) || (rhs_kind_w == 6)));
		end
		else begin
			operand_position_illegal_w = (lhs_kind_w != 0) ||
				!((rhs_kind_w == 1) || (rhs_kind_w == 2) ||
				  (rhs_kind_w == 6) ||
				  (((LOCAL_QUEUE % 4) == 1 || (LOCAL_QUEUE % 4) == 3) &&
				   (rhs_kind_w == 3)));
		end
		accumulator_operand_illegal_w =
			(accumulator_reset_w && !accumulator_write_w) ||
			(local_scalar_write_w && (accumulator_write_w ||
			 ((LOCAL_QUEUE % 4) != 1 && (LOCAL_QUEUE % 4) != 3))) ||
			(accumulator_write_w &&
			 (((LOCAL_QUEUE % 4) != 1 && (LOCAL_QUEUE % 4) != 3) ||
			  ((opcode_w != 1) && (opcode_w != 5)) || (rhs_kind_w != 3))) ||
			(!accumulator_write_w && (rhs_kind_w == 3) &&
			 ((LOCAL_QUEUE % 4) != 1 && (LOCAL_QUEUE % 4) != 3));

		instruction_illegal_w = (opcode_w > 9) || (lhs_kind_w > 8) ||
			(rhs_kind_w > 8) || (chain_depth_w > 2) ||
			(repeat_count_w == 0) || (|control_w[63:54]) ||
			opcode_position_illegal_w || operand_position_illegal_w ||
			accumulator_operand_illegal_w || (output_enable_w && !chain_tail_w);
	end

	// Word collection is independent from Context holding so output backpressure is lossless.
	always_ff @(posedge clk_i or negedge rst_ni) begin
		if(!rst_ni)begin
			word_index_q <= '0;
			decode_pending_q <= 1'b0;
			packet_last_q <= 1'b0;
			for(integer word_index = 0; word_index < 3; word_index++) packet_word_q[word_index] <= '0;
		end
		else if(!fault_q)begin
			if(word_fire)begin
				packet_word_q[word_index_q] <= word_i;
				if(word_last_i && (word_index_q != 2))begin
					word_index_q <= '0;
				end
				else if(word_index_q == 2)begin
					word_index_q <= '0;
					decode_pending_q <= 1'b1;
					packet_last_q <= word_last_i;
				end
				else begin
					word_index_q <= word_index_q + 1'b1;
				end
			end
			if(decode_pending_q) decode_pending_q <= 1'b0;
		end
	end

	// The decoded Context remains stable until accepted by the Scheduler.
	always_ff @(posedge clk_i or negedge rst_ni) begin
		if(!rst_ni)begin
			context_valid_q <= 1'b0;
			context_instruction_q <= '0;
			context_wait_cycle_q <= '0;
			context_inner_count_q <= '0;
			context_inner_interval_q <= '0;
			context_outer_count_q <= '0;
			context_outer_interval_q <= '0;
		end
		else begin
			if(context_fire) context_valid_q <= 1'b0;
			if(decode_pending_q && !header_illegal_w && !reserved_bits_illegal_w && !schedule_illegal_w && !instruction_illegal_w)begin
				context_valid_q <= 1'b1;
				context_instruction_q <= {payload_w[199:168], payload_w[167:104]};
				context_wait_cycle_q <= {8'd0, payload_w[23:0]};
				context_inner_count_q <= {15'd0, inner_count_w};
				context_inner_interval_q <= {8'd0, inner_interval_w};
				context_outer_count_q <= {15'd0, outer_count_w};
				context_outer_interval_q <= {8'd0, outer_interval_w};
			end
		end
	end

	// Terminal faults are sticky. done_q is a one-cycle descriptor-complete pulse
	// so one Decoder instance can accept the next RUN_2D packet without Reset.
	always_ff @(posedge clk_i or negedge rst_ni) begin
		if(!rst_ni)begin
			done_q <= 1'b0;
			fault_q <= 1'b0;
			fault_code_q <= FAULT_NONE;
		end
		else if(!fault_q)begin
			done_q <= 1'b0;
			if(word_fire && word_last_i && (word_index_q != 2))begin
				fault_q <= 1'b1;
				fault_code_q <= FAULT_TRUNCATED;
			end
			else if(decode_pending_q && header_illegal_w)begin
				fault_q <= 1'b1;
				fault_code_q <= FAULT_HEADER;
			end
			else if(decode_pending_q && reserved_bits_illegal_w)begin
				fault_q <= 1'b1;
				fault_code_q <= FAULT_RESERVED;
			end
			else if(decode_pending_q && schedule_illegal_w)begin
				fault_q <= 1'b1;
				fault_code_q <= FAULT_SCHEDULE;
			end
			else if(decode_pending_q && instruction_illegal_w)begin
				fault_q <= 1'b1;
				fault_code_q <= FAULT_INSTRUCTION;
			end
			else if(context_fire && packet_last_q)begin
				done_q <= 1'b1;
			end
		end
	end
endmodule
