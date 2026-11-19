package lpu_qctl_pkg;
	localparam integer QCTL_RECORD_WIDTH = 96;
	localparam integer QCTL_CYCLE_WIDTH = 32;
	localparam integer QCTL_OPCODE_WIDTH = 4;
	localparam integer QCTL_OPERAND_WIDTH = 32;

	// Logical message classes used by the unified QCTL Fabric. The first RTL
	// implementation keeps independent valid/ready channels for each class.
	typedef enum logic [3:0] {
		QCTL_MSG_POOL_READ_REQ = 4'd0,
		QCTL_MSG_POOL_READ_RESP = 4'd1,
		QCTL_MSG_EVENT = 4'd2,
		QCTL_MSG_SYNC_ARRIVE = 4'd3,
		QCTL_MSG_NOTIFY_REQ = 4'd4,
		QCTL_MSG_SYNC_RELEASE = 4'd5,
		QCTL_MSG_MEM_PACKET = 4'd6
	} lpu_qctl_msg_type_e;

	typedef enum logic [QCTL_OPCODE_WIDTH-1:0] {
		QCTL_OPCODE_SYNC = 4'd3,
		QCTL_OPCODE_NOTIFY = 4'd4,
		QCTL_OPCODE_WAIT_EVENT = 4'd7,
		QCTL_OPCODE_MEM_PACKET = 4'd8
	} lpu_qctl_opcode_e;

	function automatic logic [QCTL_RECORD_WIDTH-1:0] qctl_pack_record(
		input logic [QCTL_CYCLE_WIDTH-1:0] cycle,
		input logic [QCTL_OPCODE_WIDTH-1:0] opcode,
		input logic [QCTL_OPERAND_WIDTH-1:0] operand
	);
		qctl_pack_record = {operand, 28'd0, opcode, cycle};
	endfunction

	function automatic logic [QCTL_CYCLE_WIDTH-1:0] qctl_record_cycle(input logic [QCTL_RECORD_WIDTH-1:0] record);
		qctl_record_cycle = record[31:0];
	endfunction

	function automatic logic [QCTL_OPCODE_WIDTH-1:0] qctl_record_opcode(input logic [QCTL_RECORD_WIDTH-1:0] record);
		qctl_record_opcode = record[35:32];
	endfunction

	function automatic logic [QCTL_OPERAND_WIDTH-1:0] qctl_record_operand(input logic [QCTL_RECORD_WIDTH-1:0] record);
		qctl_record_operand = record[95:64];
	endfunction
endpackage
