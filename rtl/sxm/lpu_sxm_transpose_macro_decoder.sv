module lpu_sxm_transpose_macro_decoder (
	input  logic         clk_i,
	input  logic         rst_ni,
	input  logic         word_valid_i,
	output logic         word_ready_o,
	input  logic [95:0]  word_i,
	input  logic         word_last_i,
	output logic         context_valid_o,
	input  logic         context_ready_i,
	output logic [415:0] context_instruction_o,
	output logic [31:0]  context_wait_cycle_o,
	output logic [31:0]  context_inner_count_o,
	output logic [31:0]  context_inner_interval_o,
	output logic [31:0]  context_outer_count_o,
	output logic [31:0]  context_outer_interval_o,
	output logic         done_o,
	output logic         fault_o,
	output logic [3:0]   fault_code_o
);
	localparam logic [3:0] FAULT_NONE = 4'd0;
	localparam logic [3:0] FAULT_HEADER = 4'd1;
	localparam logic [3:0] FAULT_RESERVED = 4'd2;
	localparam logic [3:0] FAULT_TRUNCATED = 4'd3;
	localparam logic [3:0] FAULT_SCHEDULE = 4'd4;
	localparam logic [3:0] FAULT_STREAM = 4'd5;
	localparam logic [3:0] FAULT_SELECTOR = 4'd6;

	logic [95:0] packet_word_q [0:1];
	logic word_index_q;
	logic decode_pending_q;
	logic packet_last_q;
	logic context_valid_q;
	logic [415:0] context_instruction_q;
	logic [31:0] context_wait_cycle_q;
	logic [31:0] context_inner_count_q;
	logic [31:0] context_inner_interval_q;
	logic [31:0] context_outer_count_q;
	logic [31:0] context_outer_interval_q;
	logic done_q;
	logic fault_q;
	logic [3:0] fault_code_q;
	logic [171:0] payload_w;
	logic [415:0] native_instruction_w;
	logic [16:0] inner_count_w;
	logic [16:0] outer_count_w;
	logic [23:0] inner_interval_w;
	logic [23:0] outer_interval_w;
	logic [63:0] inner_cycle_span_w;
	logic [63:0] total_cycle_span_w;
	logic [5:0] source_base_w;
	logic [5:0] destination_base_w;
	logic [3:0] input_row_w;
	logic [4:0] source_count_w;
	logic header_invalid_w;
	logic reserved_invalid_w;
	logic schedule_invalid_w;
	logic stream_invalid_w;
	logic selector_invalid_w;
	logic word_fire;
	logic context_fire;

	assign word_fire = word_valid_i && word_ready_o;
	assign context_fire = context_valid_q && context_ready_i;
	assign word_ready_o = !fault_q && !done_q && !decode_pending_q && !context_valid_q;
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

	always_comb begin
		payload_w = '0;
		for(integer bit_index = 0; bit_index < 172; bit_index++)begin
			if(bit_index < 80) payload_w[bit_index] = packet_word_q[0][bit_index+8];
			else if(bit_index < 84) payload_w[bit_index] = packet_word_q[0][bit_index+12];
			else payload_w[bit_index] = packet_word_q[1][bit_index-76];
		end
	end

	// Rebuild the 416-bit native SXM instruction expected by the present datapath.
	always_comb begin
		inner_count_w = {1'b0, payload_w[39:24]} + 17'd1;
		outer_count_w = {1'b0, payload_w[55:40]} + 17'd1;
		inner_interval_w = payload_w[79:56];
		outer_interval_w = payload_w[103:80];
		inner_cycle_span_w = payload_w[39:24] * inner_interval_w;
		total_cycle_span_w = inner_cycle_span_w + payload_w[55:40] * outer_interval_w;
		source_base_w = payload_w[109:104];
		destination_base_w = payload_w[115:110];
		input_row_w = payload_w[119:116];
		source_count_w = (input_row_w == 8) ? 5'd16 : 5'd2;

		header_invalid_w = (packet_word_q[0][7:0] != 8'h43)
			|| (packet_word_q[1][7:0] != 8'h47)
			|| (packet_word_q[0][91:88] != 4'd2);
		reserved_invalid_w = |payload_w[171:120];
		schedule_invalid_w = (inner_interval_w == 0) || (outer_interval_w == 0)
			|| ((outer_count_w > 1) && (outer_interval_w <= inner_cycle_span_w))
			|| (total_cycle_span_w >= 64'd16777216);
		stream_invalid_w = ({1'b0, source_base_w} + source_count_w > 7'd64)
			|| ({1'b0, destination_base_w} + 7'd16 > 7'd64)
			|| ((source_base_w[5] != (source_base_w + source_count_w - 1'b1) >> 5))
			|| (destination_base_w[5] != (destination_base_w + 6'd15) >> 5);
		selector_invalid_w = (input_row_w > 8) && (input_row_w != 9);

		native_instruction_w = '0;
		native_instruction_w[1:0] = 2'd2;
		native_instruction_w[10:6] = source_count_w;
		native_instruction_w[15:11] = 5'd16;
		for(integer stream_index = 0; stream_index < 16; stream_index++)begin
			if(stream_index < source_count_w) native_instruction_w[16+stream_index*6+:6] = source_base_w + stream_index;
			native_instruction_w[112+stream_index*6+:6] = destination_base_w + stream_index;
		end
		native_instruction_w[403:400] = 4'd8;
		native_instruction_w[407:404] = input_row_w;
		native_instruction_w[410:408] = 3'd4;
	end

	always_ff @(posedge clk_i or negedge rst_ni) begin
		if(!rst_ni)begin
			word_index_q <= 1'b0;
			decode_pending_q <= 1'b0;
			packet_last_q <= 1'b0;
			packet_word_q[0] <= '0;
			packet_word_q[1] <= '0;
		end
		else if(!fault_q && !done_q)begin
			if(word_fire)begin
				packet_word_q[word_index_q] <= word_i;
				if(word_last_i && !word_index_q)begin
					word_index_q <= 1'b0;
				end
				else if(word_index_q)begin
					word_index_q <= 1'b0;
					decode_pending_q <= 1'b1;
					packet_last_q <= word_last_i;
				end
				else begin
					word_index_q <= 1'b1;
				end
			end
			if(decode_pending_q) decode_pending_q <= 1'b0;
		end
	end

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
			if(decode_pending_q && !header_invalid_w && !reserved_invalid_w && !schedule_invalid_w && !stream_invalid_w && !selector_invalid_w)begin
				context_valid_q <= 1'b1;
				context_instruction_q <= native_instruction_w;
				context_wait_cycle_q <= {8'd0, payload_w[23:0]};
				context_inner_count_q <= {15'd0, inner_count_w};
				context_inner_interval_q <= {8'd0, inner_interval_w};
				context_outer_count_q <= {15'd0, outer_count_w};
				context_outer_interval_q <= {8'd0, outer_interval_w};
			end
		end
	end

	always_ff @(posedge clk_i or negedge rst_ni) begin
		if(!rst_ni)begin
			done_q <= 1'b0;
			fault_q <= 1'b0;
			fault_code_q <= FAULT_NONE;
		end
		else if(!fault_q && !done_q)begin
			if(word_fire && word_last_i && !word_index_q)begin
				fault_q <= 1'b1;
				fault_code_q <= FAULT_TRUNCATED;
			end
			else if(decode_pending_q && header_invalid_w)begin
				fault_q <= 1'b1;
				fault_code_q <= FAULT_HEADER;
			end
			else if(decode_pending_q && reserved_invalid_w)begin
				fault_q <= 1'b1;
				fault_code_q <= FAULT_RESERVED;
			end
			else if(decode_pending_q && schedule_invalid_w)begin
				fault_q <= 1'b1;
				fault_code_q <= FAULT_SCHEDULE;
			end
			else if(decode_pending_q && stream_invalid_w)begin
				fault_q <= 1'b1;
				fault_code_q <= FAULT_STREAM;
			end
			else if(decode_pending_q && selector_invalid_w)begin
				fault_q <= 1'b1;
				fault_code_q <= FAULT_SELECTOR;
			end
			else if(context_fire && packet_last_q)begin
				done_q <= 1'b1;
			end
		end
	end
endmodule
