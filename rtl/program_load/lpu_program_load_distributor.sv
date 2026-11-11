module lpu_program_load_distributor #(
	parameter integer ELASTIC_DEPTH = 2
) (
	input logic clk_i,
	input logic rst_ni,

	input logic input_valid_i,
	output logic input_ready_o,
	input logic [lpu_program_load_pkg::PROGRAM_LOAD_CONTROL_WIDTH-1:0] input_control_i,
	input logic [127:0] input_data_i,
	input logic [3:0] input_strb_i,
	input logic [1:0] input_scope_i,
	input logic [11:0] input_destination_i,
	input logic [16:0] input_imem_address_i,
	input logic input_last_i,

	output logic west_valid_o,
	input logic west_ready_i,
	output logic [lpu_program_load_pkg::PROGRAM_LOAD_CONTROL_WIDTH-1:0] west_control_o,
	output logic [127:0] west_data_o,
	output logic [3:0] west_strb_o,
	output logic [11:0] west_destination_o,
	output logic [16:0] west_imem_address_o,
	output logic west_last_o,

	output logic east_valid_o,
	input logic east_ready_i,
	output logic [lpu_program_load_pkg::PROGRAM_LOAD_CONTROL_WIDTH-1:0] east_control_o,
	output logic [127:0] east_data_o,
	output logic [3:0] east_strb_o,
	output logic [11:0] east_destination_o,
	output logic [16:0] east_imem_address_o,
	output logic east_last_o,

	output logic idle_o,
	output logic fault_o,
	output logic [5:0] fault_code_o
);
	import lpu_program_load_pkg::*;

	logic head_valid;
	logic head_ready;
	logic [PROGRAM_LOAD_CONTROL_WIDTH-1:0] head_control;
	logic [127:0] head_data;
	logic [3:0] head_strb;
	logic [1:0] head_scope;
	logic [11:0] head_destination;
	logic [16:0] head_imem_address;
	logic head_last;
	logic elastic_idle;

	logic west_required_w;
	logic east_required_w;
	logic west_done_q;
	logic east_done_q;
	logic west_fire;
	logic east_fire;
	logic west_complete_w;
	logic east_complete_w;
	logic scope_invalid_w;
	logic scope_mismatch_w;
	logic route_invalid_w;
	logic fault_q;

	lpu_program_load_elastic_stage #(
		.DEPTH(ELASTIC_DEPTH)
	) u_input_elastic (
		.clk_i,
		.rst_ni,
		.input_valid_i,
		.input_ready_o,
		.input_control_i,
		.input_data_i,
		.input_strb_i,
		.input_scope_i,
		.input_destination_i,
		.input_imem_address_i,
		.input_last_i,
		.output_valid_o(head_valid),
		.output_ready_i(head_ready),
		.output_control_o(head_control),
		.output_data_o(head_data),
		.output_strb_o(head_strb),
		.output_scope_o(head_scope),
		.output_destination_o(head_destination),
		.output_imem_address_o(head_imem_address),
		.output_last_o(head_last),
		.level_o(),
		.idle_o(elastic_idle)
	);

	assign west_required_w = (head_scope == PROGRAM_SCOPE_WEST) ||
		(head_scope == PROGRAM_SCOPE_BOTH);
	assign east_required_w = (head_scope == PROGRAM_SCOPE_EAST) ||
		(head_scope == PROGRAM_SCOPE_BOTH);
	assign scope_invalid_w = (head_scope != PROGRAM_SCOPE_EAST) &&
		(head_scope != PROGRAM_SCOPE_WEST) && (head_scope != PROGRAM_SCOPE_BOTH);
	assign scope_mismatch_w = ((head_scope == PROGRAM_SCOPE_EAST) &&
		(head_destination[PROGRAM_DESTINATION_HEMISPHERE_BIT] != PROGRAM_HEMISPHERE_EAST)) ||
		((head_scope == PROGRAM_SCOPE_WEST) &&
		 (head_destination[PROGRAM_DESTINATION_HEMISPHERE_BIT] != PROGRAM_HEMISPHERE_WEST));
	assign route_invalid_w = head_valid && (scope_invalid_w || scope_mismatch_w);

	assign west_valid_o = head_valid && west_required_w && !west_done_q && !fault_q;
	assign east_valid_o = head_valid && east_required_w && !east_done_q && !fault_q;
	assign west_fire = west_valid_o && west_ready_i;
	assign east_fire = east_valid_o && east_ready_i;
	assign west_complete_w = !west_required_w || west_done_q || west_fire;
	assign east_complete_w = !east_required_w || east_done_q || east_fire;
	assign head_ready = head_valid && (route_invalid_w ||
		(west_complete_w && east_complete_w && !fault_q));

	assign west_control_o = head_control;
	assign west_data_o = head_data;
	assign west_strb_o = head_strb;
	assign west_destination_o = {PROGRAM_HEMISPHERE_WEST,
		head_destination[PROGRAM_DESTINATION_KIND_MSB:PROGRAM_DESTINATION_INDEX_LSB]};
	assign west_imem_address_o = head_imem_address;
	assign west_last_o = head_last;

	assign east_control_o = head_control;
	assign east_data_o = head_data;
	assign east_strb_o = head_strb;
	assign east_destination_o = {PROGRAM_HEMISPHERE_EAST,
		head_destination[PROGRAM_DESTINATION_KIND_MSB:PROGRAM_DESTINATION_INDEX_LSB]};
	assign east_imem_address_o = head_imem_address;
	assign east_last_o = head_last;

	assign idle_o = elastic_idle && !west_done_q && !east_done_q;
	assign fault_o = fault_q || route_invalid_w;
	assign fault_code_o = fault_o ? PROGRAM_FAULT_ROUTE : PROGRAM_FAULT_NONE;

	// West and East are independent ready/valid branches; a BOTH command is retired after both handshakes.
	always_ff @(posedge clk_i or negedge rst_ni) begin
		if(!rst_ni)begin
			west_done_q <= 1'b0;
			east_done_q <= 1'b0;
		end
		else begin
			if(head_ready)begin
				west_done_q <= 1'b0;
				east_done_q <= 1'b0;
			end
			else begin
				if(west_fire)begin
					west_done_q <= 1'b1;
				end
				if(east_fire)begin
					east_done_q <= 1'b1;
				end
			end
		end
	end

	always_ff @(posedge clk_i or negedge rst_ni) begin
		if(!rst_ni)begin
			fault_q <= 1'b0;
		end
		else if(route_invalid_w)begin
			fault_q <= 1'b1;
		end
	end
endmodule
