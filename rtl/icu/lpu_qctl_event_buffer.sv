module lpu_qctl_event_buffer #(
	parameter integer QUEUE_COUNT = 220,
	parameter integer EVENT_DEPTH = 8,
	parameter integer TAG_WIDTH = lpu_qctl_pkg::QCTL_OPERAND_WIDTH,
	parameter integer EVENT_INDEX_WIDTH = EVENT_DEPTH <= 1 ? 1 : $clog2(EVENT_DEPTH)
) (
	input logic clk_i,
	input logic rst_ni,
	input logic clear_i,
	input logic event_valid_i,
	output logic event_ready_o,
	input logic [TAG_WIDTH-1:0] event_tag_i,
	input logic [QUEUE_COUNT-1:0] waiter_valid_i,
	input logic [QUEUE_COUNT*TAG_WIDTH-1:0] waiter_tag_i,
	output logic broadcast_valid_o,
	output logic [TAG_WIDTH-1:0] broadcast_tag_o,
	output logic fault_o
);
	logic [EVENT_DEPTH-1:0] event_slot_valid_q;
	logic [TAG_WIDTH-1:0] event_slot_tag_q [0:EVENT_DEPTH-1];
	logic matched_slot_found_w;
	logic [EVENT_INDEX_WIDTH-1:0] matched_slot_index_w;
	logic free_slot_found_w;
	logic [EVENT_INDEX_WIDTH-1:0] free_slot_index_w;
	logic duplicate_event_w;
	logic event_fire_w;

	assign broadcast_valid_o = matched_slot_found_w;
	assign broadcast_tag_o = matched_slot_found_w ?
		event_slot_tag_q[matched_slot_index_w] : '0;
	assign event_ready_o = duplicate_event_w || free_slot_found_w;
	assign event_fire_w = event_valid_i && event_ready_o;
	assign fault_o = 1'b0;

	// Select one buffered TAG that currently matches at least one waiting
	// Controller. The same broadcast releases every waiter for that TAG.
	always_comb begin
		matched_slot_found_w = 1'b0;
		matched_slot_index_w = '0;
		for(integer slot = 0; slot < EVENT_DEPTH; slot++)begin
			for(integer queue_index = 0; queue_index < QUEUE_COUNT; queue_index++)begin
				if(!matched_slot_found_w && event_slot_valid_q[slot] &&
					waiter_valid_i[queue_index] &&
					(event_slot_tag_q[slot] == waiter_tag_i[queue_index*TAG_WIDTH+:TAG_WIDTH]))begin
					matched_slot_found_w = 1'b1;
					matched_slot_index_w = slot[EVENT_INDEX_WIDTH-1:0];
				end
			end
		end
	end

	// A slot consumed by the current broadcast is immediately reusable. Repeated
	// notifications for a still-buffered TAG are acknowledged and de-duplicated.
	always_comb begin
		free_slot_found_w = 1'b0;
		free_slot_index_w = '0;
		duplicate_event_w = 1'b0;
		for(integer slot = 0; slot < EVENT_DEPTH; slot++)begin
			if(event_slot_valid_q[slot] && (event_slot_tag_q[slot] == event_tag_i))begin
				duplicate_event_w = 1'b1;
			end
			if(!free_slot_found_w && (!event_slot_valid_q[slot] ||
				(matched_slot_found_w && (matched_slot_index_w == slot))))begin
				free_slot_found_w = 1'b1;
				free_slot_index_w = slot[EVENT_INDEX_WIDTH-1:0];
			end
		end
	end

	// Event storage is outside every Controller so an early DMA completion is
	// retained until a future WAIT_EVENT exposes the matching TAG.
	always_ff @(posedge clk_i or negedge rst_ni) begin
		if(!rst_ni)begin
			event_slot_valid_q <= '0;
			for(integer slot = 0; slot < EVENT_DEPTH; slot++)begin
				event_slot_tag_q[slot] <= '0;
			end
		end
		else if(clear_i)begin
			event_slot_valid_q <= '0;
			for(integer slot = 0; slot < EVENT_DEPTH; slot++)begin
				event_slot_tag_q[slot] <= '0;
			end
		end
		else begin
			if(matched_slot_found_w)begin
				event_slot_valid_q[matched_slot_index_w] <= 1'b0;
			end
			if(event_fire_w && !duplicate_event_w)begin
				event_slot_valid_q[free_slot_index_w] <= 1'b1;
				event_slot_tag_q[free_slot_index_w] <= event_tag_i;
			end
		end
	end

endmodule
