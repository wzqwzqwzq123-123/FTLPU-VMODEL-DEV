`timescale 1ns/1ps

// Stateless conversion from the formal MEM machine code to the private
// 32-bit Native control word. Legal but unimplemented operations fail closed.
module lpu_mem_command_adapter (
  input  logic        issue_valid_i,
  input  logic [lpu_pkg::MEM_INSTRUCTION_WIDTH-1:0] issue_instruction_i,
  output logic        native_valid_o,
  output logic [lpu_pkg::MEM_NATIVE_COMMAND_WIDTH-1:0] native_command_o,
  output logic        command_fault_o,
  output logic        command_unsupported_o
);
  logic [2:0] opcode;
  logic [5:0] stream;
  logic [5:0] map_stream;
  logic [lpu_pkg::MEM_ADDRESS_WIDTH-1:0] address;
  logic preserve_stream;
  logic instruction_legal;
  logic instruction_implemented;

  lpu_mem_instruction_decode u_decode (
    .instruction_i(issue_instruction_i),
    .opcode_o(opcode),
    .stream_o(stream),
    .map_stream_o(map_stream),
    .address_o(address),
    .preserve_stream_o(preserve_stream),
    .legal_o(instruction_legal),
    .implemented_o(instruction_implemented)
  );

  always @* begin
    native_valid_o = 1'b0;
    native_command_o = '0;
    command_fault_o = 1'b0;
    command_unsupported_o = 1'b0;

    if (issue_valid_i) begin
      if (instruction_legal && instruction_implemented) begin
        native_valid_o = 1'b1;
        // Native keeps a narrower private control word. Formal map_stream is
        // ignored for READ/WRITE exactly as in the CModel decode, while the
        // bank-local row and WriteTap bit retain their architectural meaning.
        native_command_o[2:0] = opcode;
        native_command_o[8:3] = stream;
        native_command_o[27:15] = address;
        native_command_o[31] = preserve_stream;
      end else begin
        command_fault_o = 1'b1;
        command_unsupported_o = instruction_legal && !instruction_implemented;
      end
    end
  end
endmodule
