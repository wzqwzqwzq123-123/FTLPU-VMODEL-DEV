module lpu_qctl_sync_fabric #(
	parameter integer QUEUE_COUNT = 220,
	parameter integer QUEUE_ID_WIDTH = QUEUE_COUNT <= 1 ? 1 : $clog2(QUEUE_COUNT)
) (
	input logic clk_i,
	input logic rst_ni,
	input logic clear_i,
	input logic [QUEUE_COUNT-1:0] participant_mask_i,
	input logic [QUEUE_COUNT-1:0] sync_arrive_valid_i,
	input logic [QUEUE_COUNT-1:0] notify_valid_i,
	output logic [QUEUE_COUNT-1:0] notify_ready_o,
	output logic [QUEUE_COUNT-1:0] sync_release_valid_o,
	output logic fault_o
);
	logic [QUEUE_COUNT-1:0] sync_arrive_mask_q;
	logic [QUEUE_COUNT-1:0] sync_arrive_mask_w;
	logic [QUEUE_COUNT-1:0] release_mask_q;
	logic all_arrived_w;
	logic notify_selected_w;
	logic [QUEUE_ID_WIDTH-1:0] notify_queue_w;
	logic notify_fire_w;
	logic notifier_is_participant_w;
	logic fault_q;

	assign sync_arrive_mask_w = sync_arrive_mask_q |
		(sync_arrive_valid_i & participant_mask_i);
	assign all_arrived_w =
		((sync_arrive_mask_w & participant_mask_i) == participant_mask_i);
	assign sync_release_valid_o = release_mask_q;
	assign fault_o = fault_q;

	// Select one NOTIFY requester. A notifier must not also be an outstanding
	// participant, otherwise a single global barrier would self-lock.
	always_comb begin
		notify_selected_w = 1'b0;
		notify_queue_w = '0;
		for(integer queue_index = 0; queue_index < QUEUE_COUNT; queue_index++)begin
			if(!notify_selected_w && notify_valid_i[queue_index])begin
				notify_selected_w = 1'b1;
				notify_queue_w = queue_index[QUEUE_ID_WIDTH-1:0];
			end
		end
	end

	assign notifier_is_participant_w = notify_selected_w &&
		participant_mask_i[notify_queue_w];
	assign notify_fire_w = notify_selected_w && all_arrived_w &&
		(release_mask_q == '0) && !notifier_is_participant_w;

	// Ready is asserted only for the selected notifier after all configured
	// participants have arrived in the current barrier round.
	always_comb begin
		notify_ready_o = '0;
		if(notify_fire_w)begin
			notify_ready_o[notify_queue_w] = 1'b1;
		end
	end

	// Arrival state is idempotent within a round. A successful NOTIFY clears the
	// round and registers a one-cycle Release for all participants.
	always_ff @(posedge clk_i or negedge rst_ni) begin
		if(!rst_ni)begin
			sync_arrive_mask_q <= '0;
			release_mask_q <= '0;
		end
		else if(clear_i)begin
			sync_arrive_mask_q <= '0;
			release_mask_q <= '0;
		end
		else begin
			release_mask_q <= '0;
			if(notify_fire_w)begin
				sync_arrive_mask_q <= '0;
				release_mask_q <= participant_mask_i;
			end
			else if(release_mask_q != '0)begin
				// Controllers hold arrive high through the Release edge. Do not
				// re-latch those level requests into the next barrier round.
				sync_arrive_mask_q <= '0;
			end
			else begin
				sync_arrive_mask_q <= sync_arrive_mask_w;
			end
		end
	end

	// Misconfigured barriers are sticky until program clear.
	always_ff @(posedge clk_i or negedge rst_ni) begin
		if(!rst_ni)begin
			fault_q <= 1'b0;
		end
		else if(clear_i)begin
			fault_q <= 1'b0;
		end
		else if(notifier_is_participant_w)begin
			fault_q <= 1'b1;
		end
	end
endmodule
