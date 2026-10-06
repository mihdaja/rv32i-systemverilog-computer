`timescale 1ns/1ps

`ifndef ALU_SV
`define ALU_SV

import rv32i_pkg::*;

module alu (
  input  logic [31:0] a,
  input  logic [31:0] b,
  input  alu_op_e     alu_op,
  output logic [31:0] result,
  output logic        zero
);

  logic [4:0] shamt;
  assign shamt = b[4:0];

  always_comb begin
    case (alu_op)
      ALU_ADD:    result = a + b;
      ALU_SUB:    result = a - b;
      ALU_SLL:    result = a << shamt;
      ALU_SLT:    result = ($signed(a) < $signed(b)) ? 32'd1 : 32'd0;
      ALU_SLTU:   result = (a < b) ? 32'd1 : 32'd0;
      ALU_XOR:    result = a ^ b;
      ALU_SRL:    result = a >> shamt;
      ALU_SRA:    result = $signed(a) >>> shamt;
      ALU_OR:     result = a | b;
      ALU_AND:    result = a & b;
      ALU_PASS_B: result = b;
      default:    result = 32'd0;
    endcase
  end

  assign zero = (result == 32'd0);

endmodule : alu

`endif // ALU_SV
