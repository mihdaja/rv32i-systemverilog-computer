`timescale 1ns/1ps

`ifndef IMM_GEN_SV
`define IMM_GEN_SV

import rv32i_pkg::*;

module imm_gen (
  input  logic [31:0] inst,
  input  imm_src_e    imm_src,
  output logic [31:0] imm
);

  wire [31:0] imm_i = {{20{inst[31]}}, inst[31:20]};
  wire [31:0] imm_s = {{20{inst[31]}}, inst[31:25], inst[11:7]};
  wire [31:0] imm_b = {{20{inst[31]}}, inst[7], inst[30:25], inst[11:8], 1'b0};
  wire [31:0] imm_u = {inst[31:12], 12'b0};
  wire [31:0] imm_j = {{12{inst[31]}}, inst[19:12], inst[20], inst[30:21], 1'b0};

  always_comb begin
    case (imm_src)
      IMM_I:   imm = imm_i;
      IMM_S:   imm = imm_s;
      IMM_B:   imm = imm_b;
      IMM_U:   imm = imm_u;
      IMM_J:   imm = imm_j;
      default: imm = 32'd0;
    endcase
  end

endmodule : imm_gen

`endif // IMM_GEN_SV
