module lpu_schedule_clock (
	input logic clk_i,
	input logic rst_ni,
	input logic run_i,

	output logic [31:0] schedule_cycle_o,
	output logic [63:0] cycle_o,
	output logic schedule_wrap_o
);
	logic [63:0] cycle_q;

	assign schedule_cycle_o = cycle_q[31:0];
	assign cycle_o = cycle_q;

	// The physical clock never stops; run_i advances the architectural Schedule time.
	always_ff @(posedge clk_i or negedge rst_ni) begin
		if(!rst_ni)begin
			cycle_q <= '0;
			schedule_wrap_o <= 1'b0;
		end
		else begin
			schedule_wrap_o <= 1'b0;
			if(run_i)begin
				cycle_q <= cycle_q + 1'b1;
				schedule_wrap_o <= &cycle_q[31:0];
			end
		end
	end
endmodule
