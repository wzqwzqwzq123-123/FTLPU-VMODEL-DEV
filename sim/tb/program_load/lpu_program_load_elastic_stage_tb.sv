module lpu_program_load_elastic_stage_tb;
	logic clk_i;
	logic rst_ni;
	logic input_valid_i;
	logic input_ready_o;
	logic [lpu_program_load_pkg::PROGRAM_LOAD_CONTROL_WIDTH-1:0] input_control_i;
	logic [127:0] input_data_i;
	logic [3:0] input_strb_i;
	logic [1:0] input_scope_i;
	logic [11:0] input_destination_i;
	logic [16:0] input_imem_address_i;
	logic input_last_i;
	logic output_valid_o;
	logic output_ready_i;
	logic [lpu_program_load_pkg::PROGRAM_LOAD_CONTROL_WIDTH-1:0] output_control_o;
	logic [127:0] output_data_o;
	logic [3:0] output_strb_o;
	logic [1:0] output_scope_o;
	logic [11:0] output_destination_o;
	logic [16:0] output_imem_address_o;
	logic output_last_o;
	logic [1:0] level_o;
	logic idle_o;

	integer expected_sequence;
	integer accepted_count;
	integer emitted_count;

	always #5 clk_i = ~clk_i;

	lpu_program_load_elastic_stage #(
		.DEPTH(2)
	) dut (.*);

	always @(posedge clk_i) begin
		if(rst_ni && output_valid_o && output_ready_i)begin
			if(output_data_o[15:0] != expected_sequence)begin
				$fatal(1, "elastic stage reordered data expected=%0d got=%0d", expected_sequence, output_data_o[15:0]);
			end
			expected_sequence <= expected_sequence + 1;
			emitted_count <= emitted_count + 1;
		end
	end

	initial begin
		clk_i = 1'b0;
		rst_ni = 1'b0;
		input_valid_i = 1'b0;
		input_control_i = '0;
		input_data_i = '0;
		input_strb_i = 4'b1111;
		input_scope_i = '0;
		input_destination_i = '0;
		input_imem_address_i = '0;
		input_last_i = 1'b0;
		output_ready_i = 1'b0;
		expected_sequence = 0;
		accepted_count = 0;
		emitted_count = 0;
		repeat(2) @(posedge clk_i);
		rst_ni = 1'b1;

		// Fill both entries while the consumer is stalled.
		repeat(2) begin
			@(negedge clk_i);
			input_valid_i = 1'b1;
			input_data_i = accepted_count;
			@(posedge clk_i);
			accepted_count = accepted_count + 1;
		end
		@(negedge clk_i);
		input_data_i = 128'd2;
		#1;
		if(input_ready_o)begin
			$fatal(1, "elastic stage accepted a third stalled item");
		end

		// Drain while continuously presenting the third entry.
		output_ready_i = 1'b1;
		@(posedge clk_i);
		accepted_count = accepted_count + 1;
		@(negedge clk_i);
		input_valid_i = 1'b0;
		wait(emitted_count == 3);
		@(negedge clk_i);
		if(!idle_o || level_o != 0)begin
			$fatal(1, "elastic stage did not become idle");
		end

		$display("lpu_program_load_elastic_stage_tb passed emitted=%0d", emitted_count);
		$finish;
	end
endmodule
