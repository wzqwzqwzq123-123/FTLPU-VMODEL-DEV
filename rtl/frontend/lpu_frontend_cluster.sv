module lpu_frontend_cluster (
	input logic clk_i,
	input logic rst_ni,
	input logic run_i,
	input logic enable_i,

	// MEM follows the separate {hemisphere,slice,bank} execution path in lpu_top.
	input  logic [207:0]      mem_issue_valid_i,
	output logic [207:0]      mem_issue_ready_o,
	input  logic [lpu_pkg::MEM_BANK_COUNT*lpu_pkg::MEM_INSTRUCTION_WIDTH-1:0] mem_issue_instruction_i,
	input  logic [3:0]        mxm_load_issue_valid_i,
	output logic [3:0]        mxm_load_issue_ready_o,
	input  logic [4*29-1:0]   mxm_load_issue_instruction_i,
	input  logic [3:0]        mxm_dequant_issue_valid_i,
	output logic [3:0]        mxm_dequant_issue_ready_o,
	input  logic [4*16-1:0]   mxm_dequant_issue_instruction_i,
	input  logic [3:0]        mxm_compute_issue_valid_i,
	output logic [3:0]        mxm_compute_issue_ready_o,
	input  logic [4*49-1:0]   mxm_compute_issue_instruction_i,
	input  logic [1:0]        sxm_transpose_issue_valid_i,
	output logic [1:0]        sxm_transpose_issue_ready_o,
	input  logic [2*416-1:0]  sxm_transpose_issue_instruction_i,
	input  logic [1:0]        sxm_permute_issue_valid_i,
	output logic [1:0]        sxm_permute_issue_ready_o,
	input  logic [2*416-1:0]  sxm_permute_issue_instruction_i,

	// VXM uses a native resident-config plus Execute-Token contract.
	input  logic        vxm_config_valid_i,
	output logic        vxm_config_ready_o,
	input  logic [95:0] vxm_config_instruction_i,
	output logic        vxm_config_valid_o,
	input  logic        vxm_config_ready_i,
	output logic [95:0] vxm_config_instruction_o,
	input  logic        vxm_execute_valid_i,
	output logic        vxm_execute_ready_o,
	output logic        vxm_execute_valid_o,
	input  logic        vxm_execute_ready_i,

	// Frontend-local faults are already indexed with the legacy Queue map.
	input  logic [137:0] source_queue_fault_i,
	output logic [137:0] dispatch_valid_o,
	output logic [138*416-1:0] dispatch_payload_o,
	output logic [137:0] queue_fault_o,

	output logic [31:0] schedule_cycle_o,
	output logic [63:0] cycle_o,
	output logic schedule_wrap_o,
	output logic integration_fault_o,
	output logic [3:0] integration_fault_code_o
);
	localparam logic [3:0] FAULT_NONE = 4'd0;
	localparam logic [3:0] FAULT_MXM_COMPUTE_WIDTH = 4'd1;

	logic [3:0] compute_width_fault_q;
	logic [3:0] compute_width_invalid_w;

	function automatic integer mxm_load_queue(input integer mxm);
		case(mxm)
			0: mxm_load_queue = 104;
			1: mxm_load_queue = 132;
			2: mxm_load_queue = 105;
			default: mxm_load_queue = 133;
		endcase
	endfunction

	function automatic integer mxm_dequant_queue(input integer mxm);
		case(mxm)
			0: mxm_dequant_queue = 106;
			1: mxm_dequant_queue = 134;
			2: mxm_dequant_queue = 107;
			default: mxm_dequant_queue = 135;
		endcase
	endfunction

	function automatic integer mxm_compute_queue(input integer mxm);
		case(mxm)
			0: mxm_compute_queue = 108;
			1: mxm_compute_queue = 136;
			2: mxm_compute_queue = 109;
			default: mxm_compute_queue = 137;
		endcase
	endfunction

	lpu_schedule_clock u_schedule_clock (
		.clk_i,
		.rst_ni,
		.run_i,
		.schedule_cycle_o,
		.cycle_o,
		.schedule_wrap_o
	);

	// Existing MXM datapaths accept 48 bits. Bit 48 must be adapted explicitly.
	always_comb begin
		compute_width_invalid_w = '0;
		for(integer mxm = 0; mxm < 4; mxm++) begin
			compute_width_invalid_w[mxm] = enable_i && mxm_compute_issue_valid_i[mxm] &&
				mxm_compute_issue_instruction_i[mxm*49+48];
		end
	end

	always_ff @(posedge clk_i or negedge rst_ni) begin
		if(!rst_ni)begin
			compute_width_fault_q <= '0;
		end
		else begin
			compute_width_fault_q <= compute_width_fault_q | compute_width_invalid_w;
		end
	end

	// Fixed Queue mapping is kept in one short combinational dispatch block.
	always_comb begin
		dispatch_valid_o = '0;
		dispatch_payload_o = '0;
		queue_fault_o = enable_i ? source_queue_fault_i : '0;
		mem_issue_ready_o = {208{enable_i}};
		mxm_load_issue_ready_o = {4{enable_i}};
		mxm_dequant_issue_ready_o = {4{enable_i}};
		mxm_compute_issue_ready_o = '0;
		sxm_transpose_issue_ready_o = {2{enable_i}};
		sxm_permute_issue_ready_o = {2{enable_i}};

		if(enable_i)begin
			for(integer mxm = 0; mxm < 4; mxm++) begin
				dispatch_valid_o[mxm_load_queue(mxm)] = mxm_load_issue_valid_i[mxm];
				dispatch_payload_o[mxm_load_queue(mxm)*416+:29] = mxm_load_issue_instruction_i[mxm*29+:29];
				dispatch_valid_o[mxm_dequant_queue(mxm)] = mxm_dequant_issue_valid_i[mxm];
				dispatch_payload_o[mxm_dequant_queue(mxm)*416+:16] = mxm_dequant_issue_instruction_i[mxm*16+:16];
				mxm_compute_issue_ready_o[mxm] = !compute_width_fault_q[mxm] && !compute_width_invalid_w[mxm];
				dispatch_valid_o[mxm_compute_queue(mxm)] = mxm_compute_issue_valid_i[mxm] &&
					mxm_compute_issue_ready_o[mxm];
				dispatch_payload_o[mxm_compute_queue(mxm)*416+:48] = mxm_compute_issue_instruction_i[mxm*49+:48];
				queue_fault_o[mxm_compute_queue(mxm)] = source_queue_fault_i[mxm_compute_queue(mxm)] ||
					compute_width_fault_q[mxm] || compute_width_invalid_w[mxm];
			end
			for(integer sxm = 0; sxm < 2; sxm++) begin
				dispatch_valid_o[128+sxm] = sxm_transpose_issue_valid_i[sxm];
				dispatch_payload_o[(128+sxm)*416+:416] = sxm_transpose_issue_instruction_i[sxm*416+:416];
				dispatch_valid_o[130+sxm] = sxm_permute_issue_valid_i[sxm];
				dispatch_payload_o[(130+sxm)*416+:416] = sxm_permute_issue_instruction_i[sxm*416+:416];
			end
		end
	end

	// VXM remains native until the resident-config/Execute adapter is implemented.
	assign vxm_config_valid_o = enable_i && vxm_config_valid_i;
	assign vxm_config_instruction_o = enable_i ? vxm_config_instruction_i : '0;
	assign vxm_config_ready_o = enable_i && vxm_config_ready_i;
	assign vxm_execute_valid_o = enable_i && vxm_execute_valid_i;
	assign vxm_execute_ready_o = enable_i && vxm_execute_ready_i;
	assign integration_fault_o = |compute_width_fault_q;
	assign integration_fault_code_o = integration_fault_o ? FAULT_MXM_COMPUTE_WIDTH : FAULT_NONE;
endmodule
