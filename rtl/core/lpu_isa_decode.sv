module lpu_mem_instruction_decode (
  input  logic [lpu_pkg::MEM_INSTRUCTION_WIDTH-1:0] instruction_i,
  output logic [2:0]  opcode_o,
  output logic [5:0]  stream_o,
  output logic [5:0]  map_stream_o,
  output logic [lpu_pkg::MEM_ADDRESS_WIDTH-1:0] address_o,
  output logic        preserve_stream_o,
  output logic        legal_o,
  output logic        implemented_o
);
  always_comb begin
    opcode_o          = instruction_i[2:0];
    stream_o          = instruction_i[8:3];
    map_stream_o      = instruction_i[14:9];
    address_o         = instruction_i[27:15];
    preserve_stream_o = instruction_i[31];
    legal_o           = (instruction_i[63:32] == '0) &&
                        (instruction_i[30:28] == '0);
    implemented_o     = 1'b0;

    case (instruction_i[2:0])
      lpu_pkg::MEM_READ: begin
        legal_o = legal_o && !instruction_i[31];
        implemented_o = 1'b1;
      end
      lpu_pkg::MEM_WRITE: implemented_o = 1'b1;
      lpu_pkg::MEM_GATHER,
      lpu_pkg::MEM_SCATTER: implemented_o = 1'b0;
      default: legal_o = 1'b0;
    endcase
  end
endmodule
