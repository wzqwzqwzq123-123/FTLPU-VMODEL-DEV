`timescale 1ns/1ps

module lpu_mem_sram_execution_tb;
	logic clk_i;
	logic rst_ni;
	logic instruction_valid_i;
	logic [lpu_pkg::MEM_INSTRUCTION_WIDTH-1:0] instruction_i;
	logic [63:0] rx_valid_i;
	logic [64*64-1:0] rx_data_i;
	logic [63:0] rx_consume_o;
	logic tx_valid_o;
	logic [5:0] tx_stream_o;
	logic [63:0] tx_data_o;
	logic tx_last_o;
	logic fault_o;
	integer checks;

	always #5 clk_i = ~clk_i;

	function automatic logic [lpu_pkg::MEM_INSTRUCTION_WIDTH-1:0] mem_instruction(
		input logic [2:0] opcode,
		input logic [lpu_pkg::MEM_ADDRESS_WIDTH-1:0] address,
		input logic [5:0] stream
	);
		mem_instruction = '0;
		mem_instruction[2:0] = opcode;
		mem_instruction[8:3] = stream;
		mem_instruction[27:15] = address;
	endfunction

	function automatic logic [lpu_pkg::MEM_INSTRUCTION_WIDTH-1:0] mem_write(
		input logic [lpu_pkg::MEM_ADDRESS_WIDTH-1:0] address,
		input logic [5:0] stream,
		input logic preserve_stream
	);
		mem_write = mem_instruction(lpu_pkg::MEM_WRITE, address, stream);
		mem_write[31] = preserve_stream;
	endfunction

	task automatic check(input logic condition, input string label);
		begin
			if(!condition)begin
				$fatal(1, "FAIL %s", label);
			end
			checks = checks + 1;
		end
	endtask

	lpu_mem_tile_slice #(
		.DEPTH_ROWS(256),
		.USE_SRAM_MACRO(1'b0)
	) dut (
		.clk_i,
		.rst_ni,
		.instruction_valid_i,
		.instruction_i,
		.rx_valid_i,
		.rx_data_i,
		.rx_consume_o,
		.tx_valid_o,
		.tx_stream_o,
		.tx_data_o,
		.tx_last_o,
		.fault_o
	);

	initial begin
		clk_i = 1'b0;
		rst_ni = 1'b0;
		instruction_valid_i = 1'b0;
		instruction_i = '0;
		rx_valid_i = '0;
		rx_data_i = '0;
		checks = 0;
		repeat(2) @(posedge clk_i);
		@(negedge clk_i);
		rst_ni = 1'b1;

		// Initialize the read target through the normal FU instruction path.
		rx_valid_i[5] = 1'b1;
		rx_data_i[5*64+:64] = 64'h0101_0202_0303_0404;
		instruction_i = mem_write(13'd100, 6'd5, 1'b0);
		instruction_valid_i = 1'b1;
		#1;
		check(rx_consume_o[5], "MEM initialization WRITE consumes the selected Stream");
		@(posedge clk_i);
		@(negedge clk_i);
		instruction_valid_i = 1'b0;
		rx_valid_i = '0;

		instruction_i = mem_instruction(lpu_pkg::MEM_READ, 13'd100, 6'd3);
		instruction_valid_i = 1'b1;
		#1;
		check(tx_valid_o && tx_stream_o == 6'd3 &&
			tx_data_o == 64'h0101_0202_0303_0404, "MEM READ uses the execution SRAM path");
		@(posedge clk_i);
		@(negedge clk_i);
		instruction_valid_i = 1'b0;

		rx_valid_i[5] = 1'b1;
		rx_data_i[5*64+:64] = 64'ha1a1_b2b2_c3c3_d4d4;
		instruction_i = mem_write(13'd200, 6'd5, 1'b0);
		instruction_valid_i = 1'b1;
		#1;
		check(rx_consume_o[5], "MEM WRITE consumes the selected Stream");
		@(posedge clk_i);
		@(negedge clk_i);
		instruction_valid_i = 1'b0;
		rx_valid_i = '0;
		check(dut.gen_behavior.u_impl.sram[16'd200] == 64'ha1a1_b2b2_c3c3_d4d4,
			"MEM WRITE updates SRAM without a Host port");
		check(!fault_o, "MEM READ and WRITE complete without fault");

		// WriteTap preserves the architectural stream token while still writing.
		rx_valid_i[5] = 1'b1;
		rx_data_i[5*64+:64] = 64'h1111_2222_3333_4444;
		instruction_i = mem_write(13'd201, 6'd5, 1'b1);
		instruction_valid_i = 1'b1;
		#1;
		check(!rx_consume_o[5], "MEM WriteTap does not consume the selected Stream");
		@(posedge clk_i);
		@(negedge clk_i);
		instruction_valid_i = 1'b0;
		rx_valid_i = '0;
		check(dut.gen_behavior.u_impl.sram[16'd201] == 64'h1111_2222_3333_4444,
			"MEM WriteTap still updates SRAM");

		// Opcode 2 is retired, while Gather is legal ISA but not implemented by
		// the current Legacy datapath. Both must fail explicitly.
		instruction_i = mem_instruction(3'd2, 13'd0, 6'd0);
		instruction_valid_i = 1'b1;
		@(posedge clk_i);
		@(negedge clk_i);
		instruction_valid_i = 1'b0;
		check(fault_o, "retired MEM opcode 2 raises a Legacy fault");

		@(negedge clk_i);
		rst_ni = 1'b0;
		@(negedge clk_i);
		rst_ni = 1'b1;
		instruction_i = mem_instruction(lpu_pkg::MEM_GATHER, 13'd0, 6'd0);
		instruction_valid_i = 1'b1;
		@(posedge clk_i);
		@(negedge clk_i);
		instruction_valid_i = 1'b0;
		check(fault_o, "legal unsupported MEM Gather raises a Legacy fault");

		$display("LPU_MEM_SRAM_EXECUTION PASS checks=%0d", checks);
		$finish;
	end
endmodule
