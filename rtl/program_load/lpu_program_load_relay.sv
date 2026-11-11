module lpu_program_load_relay #(
	parameter integer BUFFER_DEPTH = 2,
	parameter integer MEM_SLICES_PER_HEMISPHERE = 52,
	parameter integer MEM_SLICES_PER_GROUP = 4,
	parameter integer BANKS_PER_SLICE = 2,
	parameter integer MEM_GROUPS_PER_RELAY = 2,
	parameter integer RELAY_INDEX = 0,
	parameter integer RELAY_HEMISPHERE = 0,
	parameter logic LAST_RELAY = 1'b0,
	parameter integer MEM_GROUP_COUNT =
		(MEM_SLICES_PER_HEMISPHERE + MEM_SLICES_PER_GROUP - 1) / MEM_SLICES_PER_GROUP,
	parameter integer MEM_BANKS_PER_GROUP = MEM_SLICES_PER_GROUP * BANKS_PER_SLICE,
	parameter integer RELAY_COUNT =
		(MEM_GROUP_COUNT + MEM_GROUPS_PER_RELAY - 1) / MEM_GROUPS_PER_RELAY,
	parameter integer LOCAL_GROUP_COUNT =
		((MEM_GROUP_COUNT - RELAY_INDEX * MEM_GROUPS_PER_RELAY) > MEM_GROUPS_PER_RELAY) ?
		MEM_GROUPS_PER_RELAY : (MEM_GROUP_COUNT - RELAY_INDEX * MEM_GROUPS_PER_RELAY),
	parameter integer LOCAL_BANK_COUNT = LOCAL_GROUP_COUNT * MEM_BANKS_PER_GROUP
) (
	input logic clk_i,
	input logic rst_ni,

	input logic input_valid_i,
	output logic input_ready_o,
	input logic [2:0] input_control_i,
	input logic [127:0] input_data_i,
	input logic [3:0] input_strb_i,
	input logic [1:0] input_scope_i,
	input logic [11:0] input_destination_i,
	input logic [16:0] input_imem_address_i,
	input logic input_last_i,

	output logic [LOCAL_BANK_COUNT-1:0] local_valid_o,
	input logic [LOCAL_BANK_COUNT-1:0] local_ready_i,
	output logic [2:0] local_control_o,
	output logic [127:0] local_data_o,
	output logic [3:0] local_strb_o,
	output logic [1:0] local_scope_o,
	output logic [11:0] local_destination_o,
	output logic [16:0] local_imem_address_o,
	output logic local_last_o,

	output logic forward_valid_o,
	input logic forward_ready_i,
	output logic [2:0] forward_control_o,
	output logic [127:0] forward_data_o,
	output logic [3:0] forward_strb_o,
	output logic [1:0] forward_scope_o,
	output logic [11:0] forward_destination_o,
	output logic [16:0] forward_imem_address_o,
	output logic forward_last_o,

	output logic [$clog2(BUFFER_DEPTH+1)-1:0] level_o,
	output logic idle_o,
	output logic fault_o,
	output logic [5:0] fault_code_o
);
	import lpu_program_load_pkg::*;

	localparam integer RECORD_WIDTH = 167;
	localparam integer PTR_WIDTH = (BUFFER_DEPTH <= 1) ? 1 : $clog2(BUFFER_DEPTH);
	localparam integer LEVEL_WIDTH = $clog2(BUFFER_DEPTH + 1);
	localparam integer MEM_BANK_COUNT = MEM_SLICES_PER_HEMISPHERE * BANKS_PER_SLICE;
	localparam integer LOCAL_BANK_BASE = RELAY_INDEX * MEM_GROUPS_PER_RELAY * MEM_BANKS_PER_GROUP;
	localparam integer LOCAL_BANK_END = LOCAL_BANK_BASE + LOCAL_BANK_COUNT;

	// The two-entry buffer is one Relay register boundary plus skid capacity, not two pipeline stages.
	logic [RECORD_WIDTH-1:0] record_mem[0:BUFFER_DEPTH-1];
	logic [PTR_WIDTH-1:0] write_ptr_q;
	logic [PTR_WIDTH-1:0] read_ptr_q;
	logic [LEVEL_WIDTH-1:0] level_q;
	logic [RECORD_WIDTH-1:0] input_record_w;
	logic [RECORD_WIDTH-1:0] head_record_w;

	logic head_valid_w;
	logic [2:0] head_control_w;
	logic [127:0] head_data_w;
	logic [3:0] head_strb_w;
	logic [1:0] head_scope_w;
	logic [11:0] head_destination_w;
	logic [16:0] head_imem_address_w;
	logic head_last_w;
	logic [2:0] head_target_kind_w;
	logic [7:0] head_target_index_w;
	logic [7:0] local_bank_offset_w;

	logic scope_invalid_w;
	logic scope_mismatch_w;
	logic hemisphere_mismatch_w;
	logic local_route_w;
	logic forward_mem_w;
	logic forward_peripheral_w;
	logic forward_route_w;
	logic route_invalid_w;
	logic enqueue_fire_w;
	logic local_fire_w;
	logic forward_fire_w;
	logic dequeue_fire_w;
	logic fault_q;

	function automatic [PTR_WIDTH-1:0] increment_ptr(input logic [PTR_WIDTH-1:0] ptr);
		if(ptr == BUFFER_DEPTH - 1)begin
			increment_ptr = '0;
		end
		else begin
			increment_ptr = ptr + 1'b1;
		end
	endfunction

	initial begin
		if(BUFFER_DEPTH < 2)begin
			$error("Relay BUFFER_DEPTH must be at least two to provide skid capacity");
		end
		if(MEM_SLICES_PER_HEMISPHERE < 1 || MEM_SLICES_PER_GROUP < 1 || BANKS_PER_SLICE < 1)begin
			$error("Relay MEM organization parameters must be positive");
		end
		if(MEM_GROUPS_PER_RELAY < 1 || RELAY_INDEX < 0 || RELAY_INDEX >= RELAY_COUNT)begin
			$error("Relay index and group allocation are inconsistent");
		end
		if(LOCAL_GROUP_COUNT < 1 || LOCAL_BANK_COUNT < 1 || LOCAL_BANK_END > MEM_BANK_COUNT)begin
			$error("Relay local MEM bank range is invalid");
		end
		if(RELAY_HEMISPHERE != PROGRAM_HEMISPHERE_EAST &&
			RELAY_HEMISPHERE != PROGRAM_HEMISPHERE_WEST)begin
			$error("Relay hemisphere must be East or West");
		end
	end

	assign input_record_w = {
		input_control_i,
		input_data_i,
		input_strb_i,
		input_scope_i,
		input_destination_i,
		input_imem_address_i,
		input_last_i
	};
	assign head_record_w = record_mem[read_ptr_q];
	assign {
		head_control_w,
		head_data_w,
		head_strb_w,
		head_scope_w,
		head_destination_w,
		head_imem_address_w,
		head_last_w
	} = head_record_w;

	assign head_valid_w = level_q != 0;
	assign head_target_kind_w = head_destination_w[
		PROGRAM_DESTINATION_KIND_MSB:PROGRAM_DESTINATION_KIND_LSB];
	assign head_target_index_w = head_destination_w[
		PROGRAM_DESTINATION_INDEX_MSB:PROGRAM_DESTINATION_INDEX_LSB];
	assign local_bank_offset_w = head_target_index_w - LOCAL_BANK_BASE;

	// A concrete Hemisphere chain accepts BOTH as metadata but never duplicates the Record locally.
	assign scope_invalid_w = (head_scope_w != PROGRAM_SCOPE_EAST) &&
		(head_scope_w != PROGRAM_SCOPE_WEST) && (head_scope_w != PROGRAM_SCOPE_BOTH);
	assign scope_mismatch_w = ((head_scope_w == PROGRAM_SCOPE_EAST) &&
		(RELAY_HEMISPHERE != PROGRAM_HEMISPHERE_EAST)) ||
		((head_scope_w == PROGRAM_SCOPE_WEST) &&
		 (RELAY_HEMISPHERE != PROGRAM_HEMISPHERE_WEST));
	assign hemisphere_mismatch_w = head_destination_w[PROGRAM_DESTINATION_HEMISPHERE_BIT] !=
		RELAY_HEMISPHERE;

	assign local_route_w = (head_target_kind_w == PROGRAM_TARGET_MEM) &&
		(head_target_index_w >= LOCAL_BANK_BASE) && (head_target_index_w < LOCAL_BANK_END);
	assign forward_mem_w = (head_target_kind_w == PROGRAM_TARGET_MEM) &&
		(head_target_index_w >= LOCAL_BANK_END) && (head_target_index_w < MEM_BANK_COUNT);
	assign forward_peripheral_w = ((head_target_kind_w >= PROGRAM_TARGET_MXM_LOAD) &&
		(head_target_kind_w <= PROGRAM_TARGET_MXM_COMPUTE)) ||
		(head_target_kind_w == PROGRAM_TARGET_SXM_TRANSPOSE) ||
		(head_target_kind_w == PROGRAM_TARGET_SXM_PERMUTE);
	assign forward_route_w = !LAST_RELAY && (forward_mem_w || forward_peripheral_w);
	assign route_invalid_w = head_valid_w && (scope_invalid_w || scope_mismatch_w ||
		hemisphere_mismatch_w || (!local_route_w && !forward_route_w));

	// Ready depends only on registered occupancy and local route validity, cutting downstream Ready chains.
	assign input_ready_o = !fault_q && !route_invalid_w && (level_q < BUFFER_DEPTH);
	assign enqueue_fire_w = input_valid_i && input_ready_o;

	always_comb begin
		local_valid_o = '0;
		if(head_valid_w && local_route_w && !route_invalid_w && !fault_q)begin
			local_valid_o[local_bank_offset_w] = 1'b1;
		end
	end

	assign local_fire_w = |(local_valid_o & local_ready_i);
	assign forward_valid_o = head_valid_w && forward_route_w && !route_invalid_w && !fault_q;
	assign forward_fire_w = forward_valid_o && forward_ready_i;
	assign dequeue_fire_w = local_fire_w || forward_fire_w || route_invalid_w;

	assign local_control_o = head_control_w;
	assign local_data_o = head_data_w;
	assign local_strb_o = head_strb_w;
	assign local_scope_o = head_scope_w;
	assign local_destination_o = head_destination_w;
	assign local_imem_address_o = head_imem_address_w;
	assign local_last_o = head_last_w;

	assign forward_control_o = head_control_w;
	assign forward_data_o = head_data_w;
	assign forward_strb_o = head_strb_w;
	assign forward_scope_o = head_scope_w;
	assign forward_destination_o = head_destination_w;
	assign forward_imem_address_o = head_imem_address_w;
	assign forward_last_o = head_last_w;

	assign level_o = level_q;
	assign idle_o = level_q == 0;
	assign fault_o = fault_q || route_invalid_w;
	assign fault_code_o = fault_o ? PROGRAM_FAULT_ROUTE : PROGRAM_FAULT_NONE;

	// Record storage is written independently from pointer and occupancy updates.
	always_ff @(posedge clk_i) begin
		if(rst_ni)begin
			if(enqueue_fire_w)begin
				record_mem[write_ptr_q] <= input_record_w;
			end
		end
	end

	always_ff @(posedge clk_i or negedge rst_ni) begin
		if(!rst_ni)begin
			write_ptr_q <= '0;
			read_ptr_q <= '0;
		end
		else begin
			if(enqueue_fire_w)begin
				write_ptr_q <= increment_ptr(write_ptr_q);
			end
			if(dequeue_fire_w)begin
				read_ptr_q <= increment_ptr(read_ptr_q);
			end
		end
	end

	always_ff @(posedge clk_i or negedge rst_ni) begin
		if(!rst_ni)begin
			level_q <= '0;
		end
		else begin
			case({enqueue_fire_w, dequeue_fire_w})
				2'b10: level_q <= level_q + 1'b1;
				2'b01: level_q <= level_q - 1'b1;
				default: level_q <= level_q;
			endcase
		end
	end

	// Fault is sticky until reset so an invalid route cannot be silently skipped.
	always_ff @(posedge clk_i or negedge rst_ni) begin
		if(!rst_ni)begin
			fault_q <= 1'b0;
		end
		else begin
			if(route_invalid_w)begin
				fault_q <= 1'b1;
			end
		end
	end
endmodule
