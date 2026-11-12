module lpu_program_reassembler_tb;
	import lpu_program_load_pkg::*;

	logic clk_i;
	logic rst_ni;
	logic config_valid_i;
	logic config_ready_o;
	logic [31:0] config_byte_count_i;
	logic [1:0] config_scope_i;
	logic [11:0] config_destination_i;
	logic [1:0] config_format_i;
	logic [16:0] config_imem_base_address_i;
	logic config_image_first_i;
	logic config_image_last_i;
	logic [15:0] config_expected_word_count_i;
	logic [7:0] config_dma_id_i;
	logic response_valid_i;
	logic response_ready_o;
	logic [255:0] response_data_i;
	logic [31:0] response_keep_i;
	logic response_last_i;
	logic [7:0] response_id_i;
	logic response_error_i;
	logic word_valid_o;
	logic word_ready_i;
	logic [127:0] word_data_o;
	logic [3:0] word_strb_o;
	logic [1:0] word_scope_o;
	logic [11:0] word_destination_o;
	logic [16:0] word_imem_address_o;
	logic word_image_last_o;
	logic [31:0] received_byte_count_o;
	logic [15:0] generated_word_count_o;
	logic idle_o;
	logic fault_o;
	logic [5:0] fault_code_o;

	integer expected_byte;
	integer expected_words;
	integer observed_words;
	integer expected_word_bytes;
	integer byte_index;
	integer checks;
	logic [127:0] stalled_word;

	always #5 clk_i = ~clk_i;

	lpu_program_reassembler dut (.*);

	always @(posedge clk_i) begin
		if(rst_ni && word_valid_o && word_ready_i)begin
			for(byte_index = 0; byte_index < expected_word_bytes; byte_index = byte_index + 1)begin
				if(word_data_o[byte_index * 8 +: 8] != ((expected_byte + byte_index) & 8'hFF))begin
					$fatal(1, "reassembled byte mismatch word=%0d byte=%0d expected=%0d got=%0d",
						observed_words, byte_index, (expected_byte + byte_index) & 8'hFF,
						word_data_o[byte_index * 8 +: 8]);
				end
			end
			if(word_imem_address_o != 17'h20 + observed_words)begin
				$fatal(1, "word metadata mismatch word=%0d", observed_words);
			end
			if(word_image_last_o != (observed_words + 1 == expected_words))begin
				$fatal(1, "last marker mismatch word=%0d", observed_words);
			end
			expected_byte <= expected_byte + expected_word_bytes;
			observed_words <= observed_words + 1;
		end
	end

	task automatic reset_dut;
		begin
			rst_ni = 1'b0;
			config_valid_i = 1'b0;
			response_valid_i = 1'b0;
			word_ready_i = 1'b1;
			repeat(2) @(posedge clk_i);
			@(negedge clk_i);
			rst_ni = 1'b1;
			expected_byte = 0;
			observed_words = 0;
		end
	endtask

	task automatic present_config(
		input logic [31:0] byte_count,
		input logic [1:0] format,
		input logic image_first,
		input logic image_last,
		input logic [15:0] word_count,
		input logic [7:0] dma_id
	);
		begin
			@(negedge clk_i);
			config_byte_count_i = byte_count;
			config_format_i = format;
			config_image_first_i = image_first;
			config_image_last_i = image_last;
			config_expected_word_count_i = word_count;
			config_dma_id_i = dma_id;
			config_valid_i = 1'b1;
			@(posedge clk_i);
			@(negedge clk_i);
		end
	endtask

	task automatic send_beat(
		input integer first_byte,
		input integer valid_bytes,
		input logic last,
		input logic [7:0] dma_id
	);
		integer index;
		begin
			response_data_i = '0;
			response_keep_i = '0;
			for(index = 0; index < valid_bytes; index = index + 1)begin
				response_data_i[index * 8 +: 8] = (first_byte + index) & 8'hFF;
				response_keep_i[index] = 1'b1;
			end
			response_last_i = last;
			response_id_i = dma_id;
			response_error_i = 1'b0;
			response_valid_i = 1'b1;
			while(!response_ready_o)begin
				@(negedge clk_i);
			end
			@(posedge clk_i);
			@(negedge clk_i);
			response_valid_i = 1'b0;
			if(last)begin
				config_valid_i = 1'b0;
			end
		end
	endtask

	task automatic wait_for_words(input integer count);
		integer timeout;
		begin
			timeout = 0;
			while(observed_words != count && timeout < 100)begin
				@(negedge clk_i);
				timeout = timeout + 1;
			end
			if(observed_words != count)begin
				$fatal(1, "timed out waiting for %0d words got=%0d", count, observed_words);
			end
		end
	endtask

	initial begin
		clk_i = 1'b0;
		rst_ni = 1'b0;
		config_valid_i = 1'b0;
		config_byte_count_i = '0;
		config_scope_i = PROGRAM_SCOPE_WEST;
		config_destination_i = program_destination_pack(
			PROGRAM_HEMISPHERE_WEST, PROGRAM_TARGET_MEM, 8'd3);
		config_format_i = PROGRAM_FORMAT_96;
		config_imem_base_address_i = 17'h20;
		config_image_first_i = 1'b0;
		config_image_last_i = 1'b0;
		config_expected_word_count_i = '0;
		config_dma_id_i = '0;
		response_valid_i = 1'b0;
		response_data_i = '0;
		response_keep_i = '0;
		response_last_i = 1'b0;
		response_id_i = '0;
		response_error_i = 1'b0;
		word_ready_i = 1'b1;
		checks = 0;

		// 96-bit words: successive 32-byte beats release 2, 3, and 3 complete words.
		reset_dut();
		expected_words = 8;
		expected_word_bytes = 12;
		present_config(32'd96, PROGRAM_FORMAT_96, 1'b1, 1'b1, 16'd8, 8'd1);
		send_beat(0, 32, 1'b0, 8'd1);
		wait_for_words(2);
		checks = checks + 1;
		send_beat(32, 32, 1'b0, 8'd1);
		wait_for_words(5);
		checks = checks + 1;
		send_beat(64, 32, 1'b1, 8'd1);
		wait_for_words(8);
		checks = checks + 1;
		if(fault_o)begin
			$fatal(1, "96-bit scenario fault code=%0d", fault_code_o);
		end

		// 128-bit words: one 32-byte beat releases exactly two words.
		reset_dut();
		expected_words = 2;
		expected_word_bytes = 16;
		present_config(32'd32, PROGRAM_FORMAT_128, 1'b1, 1'b1, 16'd2, 8'd2);
		send_beat(0, 32, 1'b1, 8'd2);
		wait_for_words(2);
		if(word_strb_o != 4'b1111)begin
			$fatal(1, "128-bit strobe mismatch");
		end
		checks = checks + 1;

		// A partial 96-bit word crosses the transaction boundary without being cleared.
		reset_dut();
		expected_words = 3;
		expected_word_bytes = 12;
		present_config(32'd20, PROGRAM_FORMAT_96, 1'b1, 1'b0, 16'd3, 8'd3);
		send_beat(0, 20, 1'b1, 8'd3);
		wait_for_words(1);
		present_config(32'd16, PROGRAM_FORMAT_96, 1'b0, 1'b1, 16'd3, 8'd4);
		send_beat(20, 16, 1'b1, 8'd4);
		wait_for_words(3);
		if(fault_o)begin
			$fatal(1, "cross-burst scenario fault code=%0d", fault_code_o);
		end
		checks = checks + 1;

		// Output data and metadata must remain stable throughout downstream backpressure.
		reset_dut();
		expected_words = 2;
		expected_word_bytes = 16;
		word_ready_i = 1'b0;
		present_config(32'd32, PROGRAM_FORMAT_128, 1'b1, 1'b1, 16'd2, 8'd5);
		send_beat(0, 32, 1'b1, 8'd5);
		wait(word_valid_o);
		stalled_word = word_data_o;
		repeat(3) begin
			@(negedge clk_i);
			if(!word_valid_o || word_data_o != stalled_word)begin
				$fatal(1, "word changed while output was stalled");
			end
		end
		word_ready_i = 1'b1;
		wait_for_words(2);
		checks = checks + 1;

		// The final image byte count must exactly match word_count times the physical width.
		reset_dut();
		expected_words = 2;
		expected_word_bytes = 12;
		present_config(32'd23, PROGRAM_FORMAT_96, 1'b1, 1'b1, 16'd2, 8'd6);
		send_beat(0, 23, 1'b1, 8'd6);
		@(negedge clk_i);
		if(!fault_o || fault_code_o != PROGRAM_FAULT_IMAGE_LENGTH)begin
			$fatal(1, "invalid image tail was not rejected code=%0d", fault_code_o);
		end
		checks = checks + 1;

		$display("lpu_program_reassembler_tb passed checks=%0d", checks);
		$finish;
	end
endmodule
