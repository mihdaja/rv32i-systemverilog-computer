// ============================================================================
// File: next_pc_gen.sv
// Description: Next Program Counter (Next-PC) generation logic.
//              Handles sequential stepping, branch targets, direct jumps (JAL),
//              and indirect jumps (JALR).
// ============================================================================

`ifndef NEXT_PC_GEN_SV
`define NEXT_PC_GEN_SV

`timescale 1ns / 1ps

import rv32i_pkg::*;

module next_pc_gen (
  input  logic [31:0] pc,
  input  logic [31:0] imm,
  input  logic [31:0] rs1_data,
  input  logic        branch_taken,
  input  logic        jump,
  input  logic        jump_reg,
  output logic [31:0] next_pc,
  output logic [31:0] pc_plus_4
);

  assign pc_plus_4 = pc + 32'd4;

  always_comb begin
    if (jump_reg) begin
      next_pc = (rs1_data + imm) & ~32'd1;
    end else if (jump) begin
      next_pc = pc + imm;
    end else if (branch_taken) begin
      next_pc = pc + imm;
    end else begin
      next_pc = pc_plus_4;
    end
  end

endmodule : next_pc_gen

`endif // NEXT_PC_GEN_SV
