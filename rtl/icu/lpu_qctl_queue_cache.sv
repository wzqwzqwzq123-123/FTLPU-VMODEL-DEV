// QCTL Queue-local prefetch cache. Storage bookkeeping is intentionally
// isolated from the semantic Controller state machine.
module lpu_qctl_queue_cache #(
	parameter integer QUEUE_ENTRY_LIMIT = 16,
	parameter integer CACHE_DEPTH = 4,
	parameter integer GENERATION_WIDTH = 64,
	parameter integer ENTRY_INDEX_WIDTH = QUEUE_ENTRY_LIMIT <= 1 ? 1 : $clog2(QUEUE_ENTRY_LIMIT),
	parameter integer ENTRY_COUNT_WIDTH = $clog2(QUEUE_ENTRY_LIMIT + 1),
	parameter integer CACHE_COUNT_WIDTH = $clog2(CACHE_DEPTH + 1)
) (
	input logic clk_i,
	input logic rst_ni,
	input logic clear_i,

	input logic configure_valid_i,
	input logic [ENTRY_COUNT_WIDTH-1:0] configure_count_i,
	input logic [GENERATION_WIDTH-1:0] configure_generation_i,

	output logic pool_request_valid_o,
	input logic pool_request_ready_i,
	output logic [ENTRY_INDEX_WIDTH-1:0] pool_request_index_o,
	output logic [GENERATION_WIDTH-1:0] pool_request_generation_o,
	input logic pool_response_valid_i,
	input logic [lpu_qctl_pkg::QCTL_RECORD_WIDTH-1:0] pool_response_data_i,
	input logic pool_response_error_i,

	output logic head_valid_o,
	output logic [lpu_qctl_pkg::QCTL_RECORD_WIDTH-1:0] head_record_o,
	input logic head_retire_i,

	output logic configured_o,
	output logic primed_o,
	output logic done_o,
	output logic fault_o,
	output logic [3:0] fault_code_o
);
	localparam logic [3:0] FAULT_NONE = 4'd0;
	localparam logic [3:0] FAULT_CONFIGURATION = 4'd1;
	localparam logic [3:0] FAULT_POOL_RESPONSE = 4'd2;
	localparam logic [3:0] FAULT_OVERFLOW = 4'd3;
	localparam logic [3:0] FAULT_RETIRE = 4'd4;

	logic configured_q;
	logic prime_complete_q;
	logic [ENTRY_COUNT_WIDTH-1:0] control_count_q;
	logic [GENERATION_WIDTH-1:0] generation_q;
	logic [ENTRY_COUNT_WIDTH-1:0] fetch_offset_q;
	logic [ENTRY_COUNT_WIDTH-1:0] retire_offset_q;
	logic [CACHE_COUNT_WIDTH-1:0] cache_level_q;
	logic [CACHE_COUNT_WIDTH-1:0] inflight_read_q;
	logic [lpu_qctl_pkg::QCTL_RECORD_WIDTH-1:0] cache_q [0:CACHE_DEPTH-1];

	logic request_fire;
	logic response_accept_w;
	logic retire_fire;
	logic [CACHE_COUNT_WIDTH:0] reserved_entries_w;
	logic [CACHE_COUNT_WIDTH-1:0] prime_target_w;
	logic set_fault_w;
	logic [3:0] set_fault_code_w;
	logic fault_q;
	logic [3:0] fault_code_q;

	initial begin
		if(QUEUE_ENTRY_LIMIT < 1)begin
			$error("QUEUE_ENTRY_LIMIT must be at least one");
		end
		if(CACHE_DEPTH < 1 || CACHE_DEPTH > QUEUE_ENTRY_LIMIT)begin
			$error("CACHE_DEPTH must be between one and QUEUE_ENTRY_LIMIT");
		end
	end

	assign reserved_entries_w = cache_level_q + inflight_read_q;
	assign pool_request_valid_o = configured_q && !fault_q &&
		(fetch_offset_q < control_count_q) && (reserved_entries_w < CACHE_DEPTH);
	assign pool_request_index_o = fetch_offset_q[ENTRY_INDEX_WIDTH-1:0];
	assign pool_request_generation_o = generation_q;
	assign request_fire = pool_request_valid_o && pool_request_ready_i;
	assign response_accept_w = pool_response_valid_i && !pool_response_error_i &&
		(inflight_read_q != 0) && !fault_q;
	assign retire_fire = head_retire_i && head_valid_o && !fault_q;

	assign head_valid_o = cache_level_q != 0;
	assign head_record_o = cache_q[0];
	assign configured_o = configured_q;
	assign primed_o = configured_q && prime_complete_q;
	assign done_o = configured_q && (retire_offset_q == control_count_q);
	assign fault_o = fault_q;
	assign fault_code_o = fault_code_q;

	// Priming requires either all records for a short partition or a full cache.
	always_comb begin
		if(control_count_q < CACHE_DEPTH)begin
			prime_target_w = control_count_q[CACHE_COUNT_WIDTH-1:0];
		end
		else begin
			prime_target_w = CACHE_DEPTH;
		end
	end

	// Cache faults protect the Pool response contract and retirement ordering.
	always_comb begin
		set_fault_w = 1'b0;
		set_fault_code_w = FAULT_NONE;
		if(configure_valid_i && ((configure_generation_i == 0) ||
			(configure_count_i > QUEUE_ENTRY_LIMIT)))begin
			set_fault_w = 1'b1;
			set_fault_code_w = FAULT_CONFIGURATION;
		end
		else if(pool_response_valid_i && (pool_response_error_i || (inflight_read_q == 0)))begin
			set_fault_w = 1'b1;
			set_fault_code_w = FAULT_POOL_RESPONSE;
		end
		else if(response_accept_w && ((cache_level_q - retire_fire) >= CACHE_DEPTH))begin
			set_fault_w = 1'b1;
			set_fault_code_w = FAULT_OVERFLOW;
		end
		else if(head_retire_i && !head_valid_o)begin
			set_fault_w = 1'b1;
			set_fault_code_w = FAULT_RETIRE;
		end
	end

	// Configuration owns partition-local Fetch and Retire offsets. Pool addresses
	// remain the responsibility of lpu_qctl_shared_pool.
	always_ff @(posedge clk_i or negedge rst_ni) begin
		if(!rst_ni)begin
			configured_q <= 1'b0;
			prime_complete_q <= 1'b0;
			control_count_q <= '0;
			generation_q <= '0;
			fetch_offset_q <= '0;
			retire_offset_q <= '0;
			inflight_read_q <= '0;
		end
		else if(clear_i)begin
			configured_q <= 1'b0;
			prime_complete_q <= 1'b0;
			control_count_q <= '0;
			generation_q <= '0;
			fetch_offset_q <= '0;
			retire_offset_q <= '0;
			inflight_read_q <= '0;
		end
		else if(configure_valid_i)begin
			configured_q <= (configure_generation_i != 0) &&
				(configure_count_i <= QUEUE_ENTRY_LIMIT);
			prime_complete_q <= configure_count_i == 0;
			control_count_q <= configure_count_i;
			generation_q <= configure_generation_i;
			fetch_offset_q <= '0;
			retire_offset_q <= '0;
			inflight_read_q <= '0;
		end
		else begin
			if(!prime_complete_q &&
				((cache_level_q + response_accept_w) >= prime_target_w))begin
				prime_complete_q <= 1'b1;
			end
			if(request_fire)begin
				fetch_offset_q <= fetch_offset_q + 1'b1;
			end
			if(retire_fire)begin
				retire_offset_q <= retire_offset_q + 1'b1;
			end
			case({request_fire, response_accept_w})
				2'b10: inflight_read_q <= inflight_read_q + 1'b1;
				2'b01: inflight_read_q <= inflight_read_q - 1'b1;
				default: inflight_read_q <= inflight_read_q;
			endcase
		end
	end

	// Retire shifts the FIFO head, while an accepted Pool response appends after
	// all retained records. Simultaneous retire and refill are supported.
	always_ff @(posedge clk_i or negedge rst_ni) begin
		if(!rst_ni)begin
			cache_level_q <= '0;
			for(integer cache_index = 0; cache_index < CACHE_DEPTH; cache_index++)begin
				cache_q[cache_index] <= '0;
			end
		end
		else if(clear_i || configure_valid_i)begin
			cache_level_q <= '0;
			for(integer cache_index = 0; cache_index < CACHE_DEPTH; cache_index++)begin
				cache_q[cache_index] <= '0;
			end
		end
		else begin
			if(retire_fire)begin
				for(integer cache_index = 0; cache_index < CACHE_DEPTH; cache_index++)begin
					if((cache_index + 1) < cache_level_q)begin
						cache_q[cache_index] <= cache_q[cache_index + 1];
					end
					else begin
						cache_q[cache_index] <= '0;
					end
				end
			end
			if(response_accept_w)begin
				cache_q[cache_level_q - retire_fire] <= pool_response_data_i;
			end
			case({response_accept_w, retire_fire})
				2'b10: cache_level_q <= cache_level_q + 1'b1;
				2'b01: cache_level_q <= cache_level_q - 1'b1;
				default: cache_level_q <= cache_level_q;
			endcase
		end
	end

	// Cache protocol faults remain sticky for the configured program.
	always_ff @(posedge clk_i or negedge rst_ni) begin
		if(!rst_ni)begin
			fault_q <= 1'b0;
			fault_code_q <= FAULT_NONE;
		end
		else if(clear_i || configure_valid_i)begin
			fault_q <= 1'b0;
			fault_code_q <= FAULT_NONE;
		end
		else if(set_fault_w && !fault_q)begin
			fault_q <= 1'b1;
			fault_code_q <= set_fault_code_w;
		end
	end
endmodule
