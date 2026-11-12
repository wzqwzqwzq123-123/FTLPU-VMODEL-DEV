`timescale 1ns/1ps

module lpu_program_load_relay_chain_tb;
	import lpu_program_load_pkg::*;

	localparam integer RELAY_COUNT = 7;
	localparam integer MEM_BANK_COUNT = 104;
	localparam integer LEVEL_WIDTH = $clog2(2 + 1);

	logic clk_i;
	logic rst_ni;
	logic input_valid_i;
	logic input_ready_o;
	logic [PROGRAM_LOAD_CONTROL_WIDTH-1:0] input_control_i;
	logic [127:0] input_data_i;
	logic [3:0] input_strb_i;
	logic [1:0] input_scope_i;
	logic [11:0] input_destination_i;
	logic [16:0] input_imem_address_i;
	logic input_last_i;
	logic [MEM_BANK_COUNT-1:0] mem_local_valid_o;
	logic [MEM_BANK_COUNT-1:0] mem_local_ready_i;
	logic [RELAY_COUNT*PROGRAM_LOAD_CONTROL_WIDTH-1:0] mem_local_control_o;
	logic [RELAY_COUNT*128-1:0] mem_local_data_o;
	logic [RELAY_COUNT*4-1:0] mem_local_strb_o;
	logic [RELAY_COUNT*2-1:0] mem_local_scope_o;
	logic [RELAY_COUNT*12-1:0] mem_local_destination_o;
	logic [RELAY_COUNT*17-1:0] mem_local_imem_address_o;
	logic [RELAY_COUNT-1:0] mem_local_last_o;
	logic outer_local_valid_o;
	logic outer_local_ready_i;
	logic [PROGRAM_LOAD_CONTROL_WIDTH-1:0] outer_local_control_o;
	logic [127:0] outer_local_data_o;
	logic [3:0] outer_local_strb_o;
	logic [1:0] outer_local_scope_o;
	logic [11:0] outer_local_destination_o;
	logic [16:0] outer_local_imem_address_o;
	logic outer_local_last_o;
	logic [RELAY_COUNT*LEVEL_WIDTH-1:0] relay_level_o;
	logic idle_o;
	logic fault_o;
	logic [5:0] fault_code_o;

	integer checks;
	integer failures;
	integer cycle_count;
	integer local_fire_count;
	integer first_fire_cycle;
	integer last_fire_cycle;

	always #5 clk_i = ~clk_i;

	lpu_program_load_relay_chain #(
		.HEMISPHERE_ID(PROGRAM_HEMISPHERE_EAST),
		.MXM_INSTANCES_PER_HEMISPHERE(2),
		.SXM_INSTANCES_PER_HEMISPHERE(1)
	) u_dut (
		.*
	);

	always @(posedge clk_i) begin
		if(!rst_ni)begin
			cycle_count <= 0;
			local_fire_count <= 0;
			first_fire_cycle <= -1;
			last_fire_cycle <= -1;
		end
		else begin
			cycle_count <= cycle_count + 1;
			if(|(mem_local_valid_o & mem_local_ready_i))begin
				if(local_fire_count == 0)begin
					first_fire_cycle <= cycle_count;
				end
				local_fire_count <= local_fire_count + 1;
				last_fire_cycle <= cycle_count;
			end
		end
	end

	task automatic check(input logic condition, input string message);
		begin
			checks = checks + 1;
			if(!condition)begin
				failures = failures + 1;
				$display("CHECK_FAIL %s time=%0t", message, $time);
			end
		end
	endtask

	task automatic reset_dut;
		begin
			@(negedge clk_i);
			rst_ni = 1'b0;
			input_valid_i = 1'b0;
			mem_local_ready_i = '0;
			outer_local_ready_i = 1'b0;
			repeat(3) @(posedge clk_i);
			@(negedge clk_i);
			rst_ni = 1'b1;
		end
	endtask

	task automatic send_record(
		input logic [2:0] target_kind,
		input logic [7:0] target_index,
		input logic hemisphere,
		input logic [127:0] data_value
	);
		begin
			@(negedge clk_i);
			input_control_i = PROGRAM_LOAD_WRITE;
			input_data_i = data_value;
			input_strb_i = 4'hf;
			input_scope_i = PROGRAM_SCOPE_EAST;
			input_destination_i = program_destination_pack(
				hemisphere, target_kind, target_index);
			input_imem_address_i = {9'd0, target_index};
			input_last_i = 1'b1;
			input_valid_i = 1'b1;
			while(!input_ready_o)begin
				@(negedge clk_i);
			end
			@(posedge clk_i);
			@(negedge clk_i);
			input_valid_i = 1'b0;
		end
	endtask

	task automatic expect_mem(
		input integer bank_index,
		input logic [127:0] data_value
	);
		integer wait_cycles;
		integer relay_index;
		begin
			wait_cycles = 0;
			relay_index = bank_index / 16;
			if(relay_index > RELAY_COUNT - 1)begin
				relay_index = RELAY_COUNT - 1;
			end
			while(!mem_local_valid_o[bank_index] && wait_cycles < 40)begin
				@(negedge clk_i);
				wait_cycles = wait_cycles + 1;
			end
			check(wait_cycles < 40, $sformatf("MEM bank %0d reached", bank_index));
			check($onehot(mem_local_valid_o),
				$sformatf("MEM bank %0d has one-hot local valid", bank_index));
			check(mem_local_destination_o[relay_index*12+:12] ==
				program_destination_pack(PROGRAM_HEMISPHERE_EAST, PROGRAM_TARGET_MEM,
				bank_index[7:0]), $sformatf("MEM bank %0d destination preserved", bank_index));
			check(mem_local_data_o[relay_index*128+:128] == data_value,
				$sformatf("MEM bank %0d data preserved", bank_index));
			mem_local_ready_i[bank_index] = 1'b1;
			@(posedge clk_i);
			@(negedge clk_i);
			mem_local_ready_i[bank_index] = 1'b0;
		end
	endtask

	task automatic expect_outer(
		input logic [2:0] target_kind,
		input logic [7:0] target_index,
		input logic [127:0] data_value
	);
		integer wait_cycles;
		begin
			wait_cycles = 0;
			while(!outer_local_valid_o && wait_cycles < 60)begin
				@(negedge clk_i);
				wait_cycles = wait_cycles + 1;
			end
			check(wait_cycles < 60, "Outer FU request reached R6 boundary");
			check(outer_local_destination_o == program_destination_pack(
				PROGRAM_HEMISPHERE_EAST, target_kind, target_index),
				"Outer FU destination preserved");
			check(outer_local_data_o == data_value, "Outer FU data preserved");
			outer_local_ready_i = 1'b1;
			@(posedge clk_i);
			@(negedge clk_i);
			outer_local_ready_i = 1'b0;
		end
	endtask

	task automatic send_mem_burst(input integer record_count);
		integer burst_index;
		begin
			@(negedge clk_i);
			input_control_i = PROGRAM_LOAD_WRITE;
			input_strb_i = 4'hf;
			input_scope_i = PROGRAM_SCOPE_EAST;
			input_last_i = 1'b1;
			input_valid_i = 1'b1;
			for(burst_index = 0; burst_index < record_count; burst_index = burst_index + 1)begin
				input_data_i = 128'h4000 + burst_index;
				input_destination_i = program_destination_pack(
					PROGRAM_HEMISPHERE_EAST, PROGRAM_TARGET_MEM, burst_index[7:0]);
				input_imem_address_i = burst_index[16:0];
				while(!input_ready_o)begin
					@(negedge clk_i);
				end
				@(posedge clk_i);
				@(negedge clk_i);
			end
			input_valid_i = 1'b0;
		end
	endtask

	initial begin
		integer boundary_index[0:13];
		logic [2:0] outer_kind[0:4];
		integer index;

		clk_i = 1'b0;
		rst_ni = 1'b0;
		input_valid_i = 1'b0;
		input_control_i = PROGRAM_LOAD_WRITE;
		input_data_i = '0;
		input_strb_i = '0;
		input_scope_i = PROGRAM_SCOPE_EAST;
		input_destination_i = '0;
		input_imem_address_i = '0;
		input_last_i = 1'b0;
		mem_local_ready_i = '0;
		outer_local_ready_i = 1'b0;
		checks = 0;
		failures = 0;

		boundary_index[0] = 0;
		boundary_index[1] = 15;
		boundary_index[2] = 16;
		boundary_index[3] = 31;
		boundary_index[4] = 32;
		boundary_index[5] = 47;
		boundary_index[6] = 48;
		boundary_index[7] = 63;
		boundary_index[8] = 64;
		boundary_index[9] = 79;
		boundary_index[10] = 80;
		boundary_index[11] = 95;
		boundary_index[12] = 96;
		boundary_index[13] = 103;
		outer_kind[0] = PROGRAM_TARGET_MXM_LOAD;
		outer_kind[1] = PROGRAM_TARGET_MXM_DEQUANT;
		outer_kind[2] = PROGRAM_TARGET_MXM_COMPUTE;
		outer_kind[3] = PROGRAM_TARGET_SXM_TRANSPOSE;
		outer_kind[4] = PROGRAM_TARGET_SXM_PERMUTE;

		reset_dut();
		for(index = 0; index < 14; index = index + 1)begin
			send_record(PROGRAM_TARGET_MEM, boundary_index[index][7:0],
				PROGRAM_HEMISPHERE_EAST, 128'h1000 + boundary_index[index]);
			expect_mem(boundary_index[index], 128'h1000 + boundary_index[index]);
		end

		for(index = 0; index < 5; index = index + 1)begin
			send_record(outer_kind[index], 8'd0, PROGRAM_HEMISPHERE_EAST,
				128'h2000 + index);
			expect_outer(outer_kind[index], 8'd0, 128'h2000 + index);
		end
		send_record(PROGRAM_TARGET_MXM_COMPUTE, 8'd1, PROGRAM_HEMISPHERE_EAST,
			128'h2fff);
		expect_outer(PROGRAM_TARGET_MXM_COMPUTE, 8'd1, 128'h2fff);

		// A blocked local Bank holds its Record stable without blocking earlier
		// Relay state updates or corrupting the payload.
		send_record(PROGRAM_TARGET_MEM, 8'd33, PROGRAM_HEMISPHERE_EAST, 128'h3333);
		repeat(8) @(negedge clk_i);
		check(mem_local_valid_o[33], "Blocked R2 MEM request remains valid");
		check(mem_local_data_o[2*128+:128] == 128'h3333,
			"Blocked R2 MEM payload remains stable");
		mem_local_ready_i[33] = 1'b1;
		@(posedge clk_i);
		@(negedge clk_i);
		mem_local_ready_i[33] = 1'b0;

		// With no backpressure, R0 sustains one accepted local Record per cycle.
		reset_dut();
		mem_local_ready_i = '1;
		send_mem_burst(8);
		while(local_fire_count < 8)begin
			@(posedge clk_i);
		end
		check((last_fire_cycle - first_fire_cycle) == 7, "R0 steady-state throughput is II=1");
		mem_local_ready_i = '0;

		// The terminal boundary rejects an MXM instance outside the configured range.
		reset_dut();
		send_record(PROGRAM_TARGET_MXM_LOAD, 8'd2, PROGRAM_HEMISPHERE_EAST, 128'h5000);
		wait(fault_o);
		check(fault_code_o == PROGRAM_FAULT_ROUTE, "Invalid outer index raises route fault");
		check(!outer_local_valid_o, "Invalid outer index is never acknowledged locally");

		// A wrong-Hemisphere record cannot cross into this Chain.
		reset_dut();
		send_record(PROGRAM_TARGET_MEM, 8'd0, PROGRAM_HEMISPHERE_WEST, 128'h6000);
		wait(fault_o);
		check(!(|mem_local_valid_o), "Wrong-Hemisphere record has no MEM local valid");

		if(failures == 0)begin
			$display("LPU_PROGRAM_LOAD_RELAY_CHAIN TEST_PASS checks=%0d", checks);
		end
		else begin
			$fatal(1, "LPU_PROGRAM_LOAD_RELAY_CHAIN TEST_FAIL failures=%0d checks=%0d",
				failures, checks);
		end
		$finish;
	end
endmodule
