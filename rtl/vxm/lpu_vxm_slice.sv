module lpu_vxm_slice (
	input logic clk_i,
	input logic rst_ni,
	input logic run_i,

	// Eight logical Local instruction streams, not eight independent vector elements; each drives a mirrored ALU pair.
	input logic [7:0] local_issue_valid_i,
	input logic [8*lpu_pkg::VXM_LOCAL_MAX_INSTRUCTION_WIDTH-1:0] local_issue_instruction_i,
	input logic global_issue_valid_i,
	input logic [lpu_pkg::VXM_GLOBAL_CONFIG_WIDTH-1:0] global_issue_instruction_i,
	output logic config_ready_o,
	input logic execute_valid_i,
	output logic execute_ready_o,
	input logic [3:0] repeat_control_i,
	input logic [7:0] immediate_valid_i,
	input logic [255:0] immediate_data_i,
	output logic idle_o,

	// One programming stream broadcasts identical compact LUT contents to
	// all private Superlane/Lane LUT copies in this VXM.
	input logic lut_config_valid_i,
	// Special-function id 0/1/2/3 selects EXP/RECIP/RSQRT/Log, not a MEM SRAM Bank.
	input logic [1:0] lut_config_bank_i,
	input logic [15:0] lut_config_input_min_i,
	input logic [15:0] lut_config_segment_width_i,
	input logic lut_write_valid_i,
	input logic [1:0] lut_write_bank_i,
	// Zero-based coefficient-row index [0,63] within the selected function; not a byte address.
	input logic [5:0] lut_write_address_i,
	input logic [15:0] lut_write_k_i,
	input logic [15:0] lut_write_b_i,
	input logic [49:0] lut_write_log_i,

	//4 tiles, 2 direction, 32 stream, 8 lanes each stream, 1B each lane
	//west means leaving this hemisphere
	input logic [2*4*32-1:0] west_from_mem_valid_i,
	input logic [2*4*32*64-1:0] west_from_mem_data_i,
	//east means entering this hemisphere
	input logic [2*4*32-1:0] external_east_valid_i,
	input logic [2*4*32*64-1:0] external_east_data_i,
	//
	output wire [2*4*32-1:0] east_to_mem_valid_o,
	output wire [2*4*32*64-1:0] east_to_mem_data_o,

	output logic fault_o,
	output logic conflict_o
);
	import lpu_pkg::*;

	localparam integer HEMISPHERES = 2;
	localparam integer TILES = 4;
	localparam integer BOUNDARY_CELLS = HEMISPHERES * TILES;
	localparam integer STREAMS = lpu_pkg::STREAMS_PER_DIRECTION;
	localparam integer LANES = lpu_pkg::LANES_PER_TILE;
	// Bits per byte-Stream beat across all Lanes; not the numeric precision of one Lane's operand.
	localparam integer WORD_WIDTH = LANES * 8;
	localparam integer LUT_FUNCTIONS = 4;
	localparam integer LUT_ADDRESS_WIDTH = 6;
	localparam integer LUT_STAGE_WIDTH = 4;
	localparam integer LUT_LANE_REQUESTS = LUT_FUNCTIONS * LANES;
	localparam integer LOCAL_MAX_WIDTH = lpu_pkg::VXM_LOCAL_MAX_INSTRUCTION_WIDTH;
	localparam integer CONFIG_WIDTH = lpu_pkg::VXM_GLOBAL_CONFIG_WIDTH;
	localparam integer CONFIG_PAYLOAD_WIDTH = 8+56+15+8+256;
	logic [4*CONFIG_PAYLOAD_WIDTH-1:0] config_payload;
	logic [3:0] config_valid;
	logic [31:0] tile_immediate_valid;
	logic [1023:0] tile_immediate_data;
	logic [15:0] tile_repeat_control;

	logic [TILES*8-1:0] tile_local_valid;
	logic [TILES*8*LOCAL_MAX_WIDTH-1:0] tile_local_instruction;
	logic [TILES*CONFIG_WIDTH-1:0] tile_global_config;
	logic [TILES-1:0] tile_global_config_valid;
	logic global_config_fault;

	logic [TILES-1:0] row_config_wave;
	logic [TILES-1:0] row_config_ready;
	// One physical Tile accepts its arriving Local words only when Run, Tile readiness and Global configuration agree.
	logic [TILES-1:0] row_config_fire;
	logic [TILES-1:0] tile_config_ready;
	// Fixed one-cycle execute wave. This is a timing pipeline register, not an
	// instruction buffer: a Superlane may not retain or retry the command when
	// it is not ready. The compiler schedules the matching data beats.
	logic [TILES-1:0] tile_execute_wave_q;
	logic [TILES-1:0] tile_execute_ready;
	logic [TILES-1:0] tile_config_done;
	logic [TILES-1:0] tile_idle;
	logic [TILES-1:0] tile_fault;
	// Retained Global direction code per physical Tile: 0 selects boundary 0 input, 1 selects boundary 1 input.
	logic [TILES-1:0] tile_flow_direction_q;
	logic [TILES*STREAMS-1:0] tile_stream_consumed;
	logic [TILES*STREAMS-1:0] tile_output_valid;
	logic [TILES*STREAMS*WORD_WIDTH-1:0] tile_output_data;
	// TileLutRequest[t][f][l]/TileLutResponse[t][f][l] view tile_lut_request_*/tile_lut_response_* by physical Tile/function/Lane.
	logic [TILES*LUT_LANE_REQUESTS-1:0] tile_lut_request_valid;
	logic [TILES*LUT_LANE_REQUESTS*LUT_ADDRESS_WIDTH-1:0] tile_lut_request_address;
	logic [TILES*LUT_LANE_REQUESTS*LUT_STAGE_WIDTH-1:0] tile_lut_request_stage;
	logic [TILES*LUT_LANE_REQUESTS-1:0] tile_lut_response_valid;
	logic [TILES*LUT_LANE_REQUESTS*LUT_STAGE_WIDTH-1:0] tile_lut_response_stage;
	logic [TILES*LUT_LANE_REQUESTS*16-1:0] tile_lut_response_k;
	logic [TILES*LUT_LANE_REQUESTS*16-1:0] tile_lut_response_b;
	logic [TILES*LUT_LANE_REQUESTS*50-1:0] tile_lut_response_log;
	logic [TILES*LUT_FUNCTIONS-1:0] tile_lut_configured;
	logic [TILES*LUT_FUNCTIONS*16-1:0] tile_lut_input_min;
	logic [TILES*LUT_FUNCTIONS*16-1:0] tile_lut_segment_width;
	logic [TILES-1:0] tile_lut_fault;
	logic [BOUNDARY_CELLS*STREAMS-1:0] west_consumed;
	logic [BOUNDARY_CELLS*STREAMS-1:0] produced_valid;
	logic [BOUNDARY_CELLS*STREAMS*WORD_WIDTH-1:0] produced_data;
	logic config_wave_fault;
	logic execute_wave_fault;
	wire bridge_conflict;

	assign idle_o = (&tile_idle) && !(|config_valid) && !(|tile_execute_wave_q);
	assign config_ready_o = idle_o;
	// Repeat tokens may wait inside the FU. A token that has entered the fixed
	// four-row wave cannot stall or retry at a later row.
	assign execute_ready_o = idle_o && (&tile_execute_ready);
	assign global_config_fault = global_issue_valid_i && !config_ready_o;

	lpu_control_pipeline #(
		.WIDTH(CONFIG_PAYLOAD_WIDTH),
		.ROWS(4)
	) u_config_wave (
		.clk_i,
		.rst_ni,
		.issue_valid_i(global_issue_valid_i && config_ready_o),
		.issue_payload_i({local_issue_valid_i, local_issue_instruction_i,
			global_issue_instruction_i, immediate_valid_i, immediate_data_i}),
		.row_valid_o(config_valid),
		.row_payload_o(config_payload)
	);

	lpu_control_pipeline #(
		.WIDTH(4),
		.ROWS(4)
	) u_execute_wave (
		.clk_i,
		.rst_ni,
		.issue_valid_i(execute_valid_i && execute_ready_o),
		.issue_payload_i(repeat_control_i),
		.row_valid_o(tile_execute_wave_q),
		.row_payload_o(tile_repeat_control)
	);

	// Config[physical row] holds Active[logical queue], Local[queue], Global,
	// ImmediateValid[queue], Immediate[queue]. Each row receives the same bundle
	// one clock later than its predecessor; no field travels on a separate path.
	for(genvar config_row = 0; config_row < TILES; config_row++)begin : gen_config_row
		assign {tile_local_valid[config_row*8+:8],
			tile_local_instruction[config_row*56+:56],
			tile_global_config[config_row*15+:15],
			tile_immediate_valid[config_row*8+:8],
			tile_immediate_data[config_row*256+:256]} =
			config_payload[config_row*CONFIG_PAYLOAD_WIDTH+:CONFIG_PAYLOAD_WIDTH];
		assign tile_global_config_valid[config_row] = config_valid[config_row];
	end

	// Accept each Tile's configuration wave only when ready and flag any configuration/Execute timing violation.
	always_comb begin
		row_config_wave = '0;
		row_config_ready = '0;
		row_config_fire = '0;
		config_wave_fault = 1'b0;
		execute_wave_fault = 1'b0;
		// row is the physical Tile/Superlane [0,TILES-1]; row*8 selects its eight logical Local words.
		for (integer row = 0; row < TILES; row++)begin
			row_config_wave[row] = config_valid[row];
			row_config_ready[row] = tile_config_ready[row] && !tile_execute_wave_q[row];
			row_config_fire[row] = run_i && row_config_wave[row] && row_config_ready[row] && tile_global_config_valid[row];
			if(run_i && row_config_wave[row] && (!row_config_ready[row] || !tile_global_config_valid[row]))begin
				config_wave_fault = 1'b1;
			end
			// Static scheduling has no retry path. If the command cannot enter the
			// Superlane on its assigned cycle, report a schedule error immediately.
			if(run_i && tile_execute_wave_q[row] && !tile_execute_ready[row])begin
				execute_wave_fault = 1'b1;
			end
		end
	end

	// Retain the accepted configuration's direction for each physical row.
	// Execute ownership belongs exclusively to the instruction controller.
	always_ff @(posedge clk_i or negedge rst_ni) begin
		if(!rst_ni)begin
			tile_flow_direction_q <= '0;
		end
		else begin
			// row is the physical Tile/Superlane [0,TILES-1]; latch direction from the Global word that row accepted.
			for (integer row = 0; row < TILES; row++)begin
				if(row_config_fire[row])begin
					tile_flow_direction_q[row] <= tile_global_config[row*CONFIG_WIDTH+VXM_GLOBAL_FLOW_DIRECTION_BIT];
				end
			end
		end
	end

	generate
		// For physical Tile t=row and h=tile_flow_direction_q[t]: TileInput[t][st][l]=West[h][t][st][l].
		// West views west_from_mem_data_i, TileInput is u_tile.stream_data_i; both retain Stream st and Lane l.
		for (genvar row = 0; row < TILES; row++)begin : gen_tile
			lpu_vxm_tile_execution #(
				.LUT_BANK_COUNT(LUT_FUNCTIONS),
				.EXTERNAL_LUT(1)
			) u_tile (
				.clk_i,
				.rst_ni,
				.local_config_load_i(row_config_fire[row]),
				.local_config_ready_o(tile_config_ready[row]),
				.local_config_active_i(tile_local_valid[row*8+:8]),
				.local_config_instruction_i(tile_local_instruction[row*8*LOCAL_MAX_WIDTH+:8*LOCAL_MAX_WIDTH]),
				.execute_valid_i(tile_execute_wave_q[row] && run_i),
				.execute_ready_o(tile_execute_ready[row]),
				.repeat_control_i(tile_repeat_control[row*4+:4]),
				.config_done_o(tile_config_done[row]),
				.global_config_valid_i(tile_global_config_valid[row]),
				.global_config_i(tile_global_config[row*CONFIG_WIDTH+:CONFIG_WIDTH]),
				.stream_valid_i(west_from_mem_valid_i[((tile_flow_direction_q[row]?TILES : 0)+row)*STREAMS+:STREAMS]),
				.stream_data_i(west_from_mem_data_i[((tile_flow_direction_q[row]?TILES : 0)+row)*STREAMS*WORD_WIDTH+:STREAMS*WORD_WIDTH]),
				.stream_consumed_o(tile_stream_consumed[row*STREAMS+:STREAMS]),
				.immediate_valid_i(tile_immediate_valid[row*8+:8]),
				.immediate_data_i(tile_immediate_data[row*256+:256]),
				.lut_config_valid_i(1'b0),
				.lut_config_bank_i('0),
				.lut_config_input_min_i('0),
				.lut_config_segment_width_i('0),
				.lut_write_valid_i(1'b0),
				.lut_write_bank_i('0),
				.lut_write_address_i('0),
				.lut_write_k_i('0),
				.lut_write_b_i('0),
				.lut_write_log_i('0),
				.lut_shared_configured_i(tile_lut_configured[row*LUT_FUNCTIONS+:LUT_FUNCTIONS]),
				.lut_shared_input_min_i(tile_lut_input_min[row*LUT_FUNCTIONS*16+:LUT_FUNCTIONS*16]),
				.lut_shared_segment_width_i(tile_lut_segment_width[row*LUT_FUNCTIONS*16+:LUT_FUNCTIONS*16]),
				.lut_lane_request_valid_o(tile_lut_request_valid[row*LUT_LANE_REQUESTS+:LUT_LANE_REQUESTS]),
				.lut_lane_request_address_o(tile_lut_request_address[row*LUT_LANE_REQUESTS*LUT_ADDRESS_WIDTH+:LUT_LANE_REQUESTS*LUT_ADDRESS_WIDTH]),
				.lut_lane_request_stage_o(tile_lut_request_stage[row*LUT_LANE_REQUESTS*LUT_STAGE_WIDTH+:LUT_LANE_REQUESTS*LUT_STAGE_WIDTH]),
				.lut_lane_response_valid_i(tile_lut_response_valid[row*LUT_LANE_REQUESTS+:LUT_LANE_REQUESTS]),
				.lut_lane_response_stage_i(tile_lut_response_stage[row*LUT_LANE_REQUESTS*LUT_STAGE_WIDTH+:LUT_LANE_REQUESTS*LUT_STAGE_WIDTH]),
				.lut_lane_response_k_i(tile_lut_response_k[row*LUT_LANE_REQUESTS*16+:LUT_LANE_REQUESTS*16]),
				.lut_lane_response_b_i(tile_lut_response_b[row*LUT_LANE_REQUESTS*16+:LUT_LANE_REQUESTS*16]),
				.lut_lane_response_log_i(tile_lut_response_log[row*LUT_LANE_REQUESTS*50+:LUT_LANE_REQUESTS*50]),
				.output_ready_i('1),
				.output_valid_o(tile_output_valid[row*STREAMS+:STREAMS]),
				.output_data_o(tile_output_data[row*STREAMS*WORD_WIDTH+:STREAMS*WORD_WIDTH]),
				.tail_valid_o(),
				.tail_value_o(),
				.tail_original_o(),
				.tail_auxiliary_o(),
				.accumulator_state_valid_o(),
				.accumulator_state_data_o(),
				.feedback_state_valid_o(),
				.feedback_state_value_o(),
				.instruction_pending_o(),
				.idle_o(tile_idle[row]),
				.fault_o(tile_fault[row])
			);
		end

		// Each Superlane owns 4 functions x 8 Lane SRAMs. All Superlanes
		// can read the same function/Lane concurrently at independent addresses.
		// row elaborates a private LUT set per Tile/Superlane; functions and Lanes remain independently readable.
		for (genvar row = 0; row < TILES; row++)begin : gen_lut_tile
			lpu_vxm_tile_lut #(
				.FUNCTION_COUNT(LUT_FUNCTIONS),
				.LANES(LANES),
				.ENTRY_COUNT(1 << LUT_ADDRESS_WIDTH),
				.STAGE_WIDTH(LUT_STAGE_WIDTH)
			) u_tile_lut (
				.clk_i,
				.rst_ni,
				.config_valid_i(lut_config_valid_i),
				.config_function_i(lut_config_bank_i),
				.config_input_min_i(lut_config_input_min_i),
				.config_segment_width_i(lut_config_segment_width_i),
				.write_valid_i(lut_write_valid_i),
				.write_function_i(lut_write_bank_i),
				.write_address_i(lut_write_address_i),
				.write_k_i(lut_write_k_i),
				.write_b_i(lut_write_b_i),
				.write_log_i(lut_write_log_i),
				.request_valid_i(tile_lut_request_valid[row*LUT_LANE_REQUESTS+:LUT_LANE_REQUESTS]),
				.request_address_i(tile_lut_request_address[row*LUT_LANE_REQUESTS*LUT_ADDRESS_WIDTH+:LUT_LANE_REQUESTS*LUT_ADDRESS_WIDTH]),
				.request_stage_i(tile_lut_request_stage[row*LUT_LANE_REQUESTS*LUT_STAGE_WIDTH+:LUT_LANE_REQUESTS*LUT_STAGE_WIDTH]),
				.response_valid_o(tile_lut_response_valid[row*LUT_LANE_REQUESTS+:LUT_LANE_REQUESTS]),
				.response_stage_o(tile_lut_response_stage[row*LUT_LANE_REQUESTS*LUT_STAGE_WIDTH+:LUT_LANE_REQUESTS*LUT_STAGE_WIDTH]),
				.response_k_o(tile_lut_response_k[row*LUT_LANE_REQUESTS*16+:LUT_LANE_REQUESTS*16]),
				.response_b_o(tile_lut_response_b[row*LUT_LANE_REQUESTS*16+:LUT_LANE_REQUESTS*16]),
				.response_log_o(tile_lut_response_log[row*LUT_LANE_REQUESTS*50+:LUT_LANE_REQUESTS*50]),
				.configured_o(tile_lut_configured[row*LUT_FUNCTIONS+:LUT_FUNCTIONS]),
				.input_min_o(tile_lut_input_min[row*LUT_FUNCTIONS*16+:LUT_FUNCTIONS*16]),
				.segment_width_o(tile_lut_segment_width[row*LUT_FUNCTIONS*16+:LUT_FUNCTIONS*16]),
				.fault_o(tile_lut_fault[row])
			);
		end
	endgenerate

	// One physical Tile sits between the two hemisphere boundaries. The global
	// direction bit controls both its 2:1 input MUX and opposite-side output
	// routing; stream numbers remain fixed inside the Tile.
	always_comb begin
		west_consumed = '0;
		produced_valid = '0;
		produced_data = '0;
		// For Tile t=row and h=tile_flow_direction_q[t]: Produced[h^1][t][st][l]=TileOutput[t][st][l].
		// Data views Produced/TileOutput name produced_data/tile_output_data; their per-Stream valids follow the same route.
		// Consumed=west_consumed and TileConsumed=tile_stream_consumed: Consumed[h][t][st]=TileConsumed[t][st].
		// Consumption acknowledges input boundary h, not the opposite output boundary h^1.
		for (integer row = 0; row < TILES; row++)begin
			if(tile_flow_direction_q[row] == VXM_FLOW_LEFT_TO_RIGHT)begin
				west_consumed[row*STREAMS+:STREAMS] = tile_stream_consumed[row*STREAMS+:STREAMS];
				produced_valid[(TILES+row)*STREAMS+:STREAMS] = tile_output_valid[row*STREAMS+:STREAMS];
				produced_data[(TILES+row)*STREAMS*WORD_WIDTH+:STREAMS*WORD_WIDTH] = tile_output_data[row*STREAMS*WORD_WIDTH+:STREAMS*WORD_WIDTH];
			end
			else begin
				west_consumed[(TILES+row)*STREAMS+:STREAMS] = tile_stream_consumed[row*STREAMS+:STREAMS];
				produced_valid[row*STREAMS+:STREAMS] = tile_output_valid[row*STREAMS+:STREAMS];
				produced_data[row*STREAMS*WORD_WIDTH+:STREAMS*WORD_WIDTH] = tile_output_data[row*STREAMS*WORD_WIDTH+:STREAMS*WORD_WIDTH];
			end
		end
	end

	lpu_vxm_stream_bridge #(
		.HEMISPHERES(HEMISPHERES),
		.TILES(TILES),
		.STREAMS(STREAMS),
		.WORD_WIDTH(WORD_WIDTH)
	) u_stream_bridge (
		.west_from_mem_valid_i,
		.west_from_mem_data_i,
		.external_east_valid_i,
		.external_east_data_i,
		.west_consumed_i(west_consumed),
		.produced_valid_i(produced_valid),
		.produced_data_i(produced_data),
		.east_to_mem_valid_o,
		.east_to_mem_data_o,
		.conflict_o(bridge_conflict)
	);

	// Latch execution and routing faults during run_i; reset or leaving Run clears the Slice status.
	always_ff @(posedge clk_i or negedge rst_ni) begin
		if(!rst_ni)begin
			fault_o <= 1'b0;
			conflict_o <= 1'b0;
		end
		else if(!run_i)begin
			fault_o <= 1'b0;
			conflict_o <= 1'b0;
		end
		else begin
			fault_o <= fault_o | global_config_fault | config_wave_fault | execute_wave_fault | (|tile_fault) | (|tile_lut_fault);
			conflict_o <= conflict_o | bridge_conflict;
		end
	end

	// Completion is observed after all four rows and their output beats drain;
	// a per-iteration Tile marker alone cannot retire the resident command.
endmodule
