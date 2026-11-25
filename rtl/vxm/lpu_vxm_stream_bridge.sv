module lpu_vxm_stream_bridge #(
	parameter integer HEMISPHERES = 2,
	parameter integer TILES = 4,
	parameter integer STREAMS = 32,
	parameter integer WORD_WIDTH = 64
) (
	input logic [HEMISPHERES*TILES*STREAMS-1:0] west_from_mem_valid_i,
	input logic [HEMISPHERES*TILES*STREAMS*WORD_WIDTH-1:0] west_from_mem_data_i,
	input logic [HEMISPHERES*TILES*STREAMS-1:0] external_east_valid_i,
	input logic [HEMISPHERES*TILES*STREAMS*WORD_WIDTH-1:0] external_east_data_i,
	input logic [HEMISPHERES*TILES*STREAMS-1:0] west_consumed_i,
	input logic [HEMISPHERES*TILES*STREAMS-1:0] produced_valid_i,
	input logic [HEMISPHERES*TILES*STREAMS*WORD_WIDTH-1:0] produced_data_i,

	output logic [HEMISPHERES*TILES*STREAMS-1:0] east_to_mem_valid_o,
	output logic [HEMISPHERES*TILES*STREAMS*WORD_WIDTH-1:0] east_to_mem_data_o,
	output logic conflict_o
);
	// Route external, bypassed and produced stream words; conflicting producers set conflict_o instead of overwriting.
	always_comb begin
		east_to_mem_valid_o = '0;
		east_to_mem_data_o = '0;
		conflict_o = 1'b0;

		// External East producers enter their local hemisphere unchanged.
		// cell_index flattens {hemisphere, Tile, stream}; bit_base=cell_index*WORD_WIDTH selects one Lane-packed stream word.
		for (integer cell_index = 0; cell_index < HEMISPHERES * TILES * STREAMS; cell_index++)begin
			if(external_east_valid_i[cell_index])begin
				east_to_mem_valid_o[cell_index] = 1'b1;
				east_to_mem_data_o[cell_index*WORD_WIDTH+:WORD_WIDTH] = external_east_data_i[cell_index*WORD_WIDTH+:WORD_WIDTH];
			end
		end

		// Unconsumed West traffic crosses to the opposite hemisphere's East edge.
		// hemisphere is the source boundary [0,HEMISPHERES-1]; hemisphere^1 selects the opposite destination boundary.
		for (integer hemisphere = 0; hemisphere < HEMISPHERES; hemisphere++)begin
			// tile is the physical row [0,TILES-1]; bypass keeps the row unchanged across the two boundaries.
			for (integer tile = 0; tile < TILES; tile++)begin
				// stream is the fixed byte-stream number [0,STREAMS-1]; flat cell=(hemisphere*TILES+tile)*STREAMS+stream.
				for (integer stream = 0; stream < STREAMS; stream++)begin
					if(west_from_mem_valid_i[(hemisphere*TILES+tile)*STREAMS+stream] && !west_consumed_i[(hemisphere*TILES+tile)*STREAMS+stream])begin
						if(east_to_mem_valid_o[(((hemisphere^1)*TILES+tile)*STREAMS)+stream])begin
							conflict_o = 1'b1;
						end
						else begin
							east_to_mem_valid_o[(((hemisphere^1)*TILES+tile)*STREAMS)+stream] = 1'b1;
							east_to_mem_data_o[ ((((hemisphere^1)*TILES+tile)*STREAMS)+stream)*WORD_WIDTH +: WORD_WIDTH] = west_from_mem_data_i[ ((hemisphere*TILES+tile)*STREAMS+stream)*WORD_WIDTH +: WORD_WIDTH];
						end
					end
				end
			end
		end

		// Active VXM results have the same conflict rules as any other producer.
		// cell_index is the produced output boundary cell; existing external/bypass ownership has priority on collision.
		for (integer cell_index = 0; cell_index < HEMISPHERES * TILES * STREAMS; cell_index++)begin
			if(produced_valid_i[cell_index])begin
				if(east_to_mem_valid_o[cell_index])begin
					conflict_o = 1'b1;
				end
				else begin
					east_to_mem_valid_o[cell_index] = 1'b1;
					east_to_mem_data_o[cell_index*WORD_WIDTH+:WORD_WIDTH] = produced_data_i[cell_index*WORD_WIDTH+:WORD_WIDTH];
				end
			end
		end
	end
endmodule
