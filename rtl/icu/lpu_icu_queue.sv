module lpu_icu_queue #(
	parameter integer PAYLOAD_WIDTH = 416,
	parameter integer DEPTH = 16,
	parameter bit APPLY_MEM_STRIDE = 1'b0
) (
	input logic clk_i,
	input logic rst_ni,
	input logic run_i,

	input logic enqueue_valid_i,
	output logic enqueue_ready_o,
	input logic enqueue_is_instruction_i,
	input logic [31:0] enqueue_command_i,
	input logic [PAYLOAD_WIDTH-1:0] enqueue_payload_i,

	output logic issue_valid_o,
	output logic [PAYLOAD_WIDTH-1:0] issue_payload_o,
	output logic fault_o,
	output logic [$clog2(DEPTH+1)-1:0] level_o,
	output logic idle_o
);
	localparam integer LEVEL_WIDTH = $clog2(DEPTH + 1);
	localparam integer ENTRY_WIDTH = 2 + PAYLOAD_WIDTH + 32;
	localparam integer STRIDE_PAYLOAD_WIDTH = (PAYLOAD_WIDTH < 31) ? 31 : PAYLOAD_WIDTH;

	logic [ENTRY_WIDTH-1:0] fifo_enqueue_data;
	logic [ENTRY_WIDTH-1:0] fifo_dequeue_data;
	logic fifo_dequeue_valid;
	logic [LEVEL_WIDTH-1:0] fifo_level;
	logic [1:0] head_kind;
	logic [PAYLOAD_WIDTH-1:0] head_payload;
	logic [31:0] head_command;

	logic [PAYLOAD_WIDTH-1:0] last_instruction_q;
	logic [PAYLOAD_WIDTH-1:0] repeat_instruction_q;
	logic last_instruction_valid_q;
	logic [29:0] nop_remaining_q;
	logic [9:0] repeat_remaining_q;
	logic [7:0] repeat_interval_q;
	logic [7:0] repeat_cooldown_q;
	logic signed [11:0] repeat_stride_q;
	logic [9:0] repeat_index_q;
	logic dequeue_fire;

	function automatic [PAYLOAD_WIDTH-1:0] apply_stride(input logic [PAYLOAD_WIDTH-1:0] payload, input logic signed [11:0] stride, input logic [9:0] index);
		logic [STRIDE_PAYLOAD_WIDTH-1:0] wide_payload;
		logic signed [22:0] delta;
		logic signed [23:0] address;
		begin
			wide_payload = '0;
			wide_payload[PAYLOAD_WIDTH-1:0] = payload;
			if(APPLY_MEM_STRIDE)begin
				delta = stride * $signed({1'b0, index});
				address = $signed({1'b0, wide_payload[30:15]}) + delta;
				wide_payload[30:15] = address[15:0];
			end
			apply_stride = wide_payload[PAYLOAD_WIDTH-1:0];
		end
	endfunction

	assign fifo_enqueue_data = {enqueue_is_instruction_i ? 2'd0 : enqueue_command_i[1:0], enqueue_payload_i, enqueue_command_i};
	assign {head_kind, head_payload, head_command} = fifo_dequeue_data;
	assign dequeue_fire = run_i && (nop_remaining_q == 0) && (repeat_remaining_q == 0) && fifo_dequeue_valid;
	assign level_o = fifo_level;
	assign idle_o = (fifo_level == 0) && (nop_remaining_q == 0) && (repeat_remaining_q == 0);

	lpu_queue_fifo #(
		.DATA_WIDTH(ENTRY_WIDTH),
		.DEPTH(DEPTH)
	) u_fifo (
		.clk_i,
		.rst_ni,
		.enqueue_valid_i,
		.enqueue_ready_o,
		.enqueue_data_i(fifo_enqueue_data),
		.dequeue_valid_o(fifo_dequeue_valid),
		.dequeue_ready_i(dequeue_fire),
		.dequeue_data_o(fifo_dequeue_data),
		.level_o(fifo_level)
	);

	always_ff @(posedge clk_i or negedge rst_ni) begin
		if(!rst_ni)begin
			last_instruction_q       <= '0;
			repeat_instruction_q     <= '0;
			last_instruction_valid_q <= 1'b0;
			nop_remaining_q          <= '0;
			repeat_remaining_q       <= '0;
			repeat_interval_q        <= 8'd1;
			repeat_cooldown_q        <= '0;
			repeat_stride_q          <= '0;
			repeat_index_q           <= '0;
			issue_valid_o            <= 1'b0;
			issue_payload_o          <= '0;
			fault_o                  <= 1'b0;
		end
		else begin
			issue_valid_o <= 1'b0;
			if(run_i)begin
				if(nop_remaining_q != 0)begin
					nop_remaining_q <= nop_remaining_q - 1'b1;
				end
				else if(repeat_remaining_q != 0)begin
					if(repeat_cooldown_q != 0)begin
						repeat_cooldown_q <= repeat_cooldown_q - 1'b1;
					end
					else begin
						issue_valid_o <= 1'b1;
						issue_payload_o <= apply_stride(repeat_instruction_q, repeat_stride_q, repeat_index_q);
						last_instruction_q <= apply_stride(repeat_instruction_q, repeat_stride_q, repeat_index_q);
						last_instruction_valid_q <= 1'b1;
						repeat_index_q <= repeat_index_q + 1'b1;
						repeat_remaining_q <= repeat_remaining_q - 1'b1;
						if(repeat_remaining_q > 1)begin
							repeat_cooldown_q <= repeat_interval_q - 1'b1;
						end
					end
				end
				else if(dequeue_fire)begin
					case (head_kind)
						2'd0: begin
							issue_valid_o <= 1'b1;
							issue_payload_o <= head_payload;
							last_instruction_q <= head_payload;
							last_instruction_valid_q <= 1'b1;
						end
						2'd1: begin
							if(head_command[31:2] != 0)begin
								nop_remaining_q <= head_command[31:2] - 1'b1;
							end
						end
						2'd2: begin
							if(!last_instruction_valid_q || (head_command[19:12] == 0))begin
								fault_o <= 1'b1;
							end
							else if(head_command[11:2] != 0)begin
								repeat_instruction_q <= last_instruction_q;
								repeat_stride_q <= head_command[31:20];
								repeat_interval_q <= head_command[19:12];
								repeat_index_q <= 10'd1;
								if(head_command[19:12] == 1)begin
									issue_valid_o <= 1'b1;
									issue_payload_o <= apply_stride(last_instruction_q, head_command[31:20], 10'd1);
									last_instruction_q <= apply_stride(last_instruction_q, head_command[31:20], 10'd1);
									repeat_index_q <= 10'd2;
									repeat_remaining_q <= head_command[11:2] - 1'b1;
									repeat_cooldown_q <= '0;
								end
								else begin
									repeat_remaining_q <= head_command[11:2];
									repeat_cooldown_q  <= head_command[19:12] - 2'd2;
								end
							end
						end
						default: fault_o <= 1'b1;
					endcase
				end
			end
		end
	end
endmodule
