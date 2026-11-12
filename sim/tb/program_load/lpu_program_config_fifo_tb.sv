module lpu_program_config_fifo_tb;
	logic clk_i;
	logic rst_ni;
	logic enqueue_valid_i;
	logic enqueue_ready_o;
	logic [63:0] enqueue_source_address_i;
	logic [31:0] enqueue_byte_count_i;
	logic [1:0] enqueue_scope_i;
	logic [11:0] enqueue_destination_i;
	logic [1:0] enqueue_format_i;
	logic [16:0] enqueue_imem_base_address_i;
	logic enqueue_image_first_i;
	logic enqueue_image_last_i;
	logic [15:0] enqueue_expected_word_count_i;
	logic [7:0] enqueue_dma_id_i;
	logic dequeue_valid_o;
	logic dequeue_ready_i;
	logic [63:0] dequeue_source_address_o;
	logic [31:0] dequeue_byte_count_o;
	logic [1:0] dequeue_scope_o;
	logic [11:0] dequeue_destination_o;
	logic [1:0] dequeue_format_o;
	logic [16:0] dequeue_imem_base_address_o;
	logic dequeue_image_first_o;
	logic dequeue_image_last_o;
	logic [15:0] dequeue_expected_word_count_o;
	logic [7:0] dequeue_dma_id_o;
	logic [1:0] level_o;
	logic empty_o;
	logic full_o;

	integer checks;

	always #5 clk_i = ~clk_i;

	lpu_program_config_fifo #(
		.DEPTH(2)
	) dut (.*);

	task automatic drive_entry(input logic [7:0] id, input logic [63:0] address);
		begin
			enqueue_source_address_i = address;
			enqueue_byte_count_i = {24'd0, id} + 32'd12;
			enqueue_scope_i = id[0] ? 2'd1 : 2'd0;
			enqueue_destination_i = {id[0], id[2:0], id};
			enqueue_format_i = id[1:0];
			enqueue_imem_base_address_i = {8'd0, id};
			enqueue_image_first_i = id[0];
			enqueue_image_last_i = ~id[0];
			enqueue_expected_word_count_i = {8'd0, id};
			enqueue_dma_id_i = id;
		end
	endtask

	task automatic expect_head(input logic [7:0] id, input logic [63:0] address);
		begin
			#1;
			if(!dequeue_valid_o || dequeue_dma_id_o != id ||
				dequeue_source_address_o != address || dequeue_destination_o[7:0] != id)begin
				$fatal(1, "config FIFO head mismatch id=%0d", id);
			end
			checks = checks + 1;
		end
	endtask

	initial begin
		clk_i = 1'b0;
		rst_ni = 1'b0;
		enqueue_valid_i = 1'b0;
		dequeue_ready_i = 1'b0;
		drive_entry(8'd0, 64'd0);
		checks = 0;
		repeat(2) @(posedge clk_i);
		rst_ni = 1'b1;

		@(negedge clk_i);
		drive_entry(8'd1, 64'h1000);
		enqueue_valid_i = 1'b1;
		@(posedge clk_i);
		@(negedge clk_i);
		drive_entry(8'd2, 64'h2000);
		@(posedge clk_i);
		@(negedge clk_i);
		enqueue_valid_i = 1'b0;
		if(!full_o || enqueue_ready_o)begin
			$fatal(1, "config FIFO did not report full");
		end
		expect_head(8'd1, 64'h1000);

		// A full FIFO must still accept a replacement when the head dequeues in the same cycle.
		dequeue_ready_i = 1'b1;
		drive_entry(8'd3, 64'h3000);
		enqueue_valid_i = 1'b1;
		#1;
		if(!enqueue_ready_o)begin
			$fatal(1, "simultaneous dequeue/enqueue was blocked");
		end
		@(posedge clk_i);
		@(negedge clk_i);
		enqueue_valid_i = 1'b0;
		dequeue_ready_i = 1'b0;
		expect_head(8'd2, 64'h2000);

		dequeue_ready_i = 1'b1;
		@(posedge clk_i);
		@(negedge clk_i);
		dequeue_ready_i = 1'b0;
		expect_head(8'd3, 64'h3000);
		dequeue_ready_i = 1'b1;
		@(posedge clk_i);
		@(negedge clk_i);
		dequeue_ready_i = 1'b0;
		if(!empty_o || level_o != 0)begin
			$fatal(1, "config FIFO did not drain");
		end
		checks = checks + 1;

		// Ready on an empty FIFO is a legal probe and must never underflow the level counter.
		dequeue_ready_i = 1'b1;
		repeat(2) @(posedge clk_i);
		@(negedge clk_i);
		dequeue_ready_i = 1'b0;
		if(!empty_o || level_o != 0 || dequeue_valid_o)begin
			$fatal(1, "config FIFO underflowed while empty");
		end
		checks = checks + 1;

		$display("lpu_program_config_fifo_tb passed checks=%0d", checks);
		$finish;
	end
endmodule
