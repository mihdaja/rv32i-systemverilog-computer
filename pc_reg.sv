// ============================================================================
// File: pc_reg.sv
// Description: Program Counter (PC) register for RV32I processor.
//              Supports synchronous enable and asynchronous active-low reset.
// ============================================================================

`ifndef PC_REG_SV
`define PC_REG_SV

`timescale 1ns / 1ps

import rv32i_pkg::*;

module pc_reg (
  input  logic        clk,
  input  logic        rst_n,
  input  logic        en,
  input  logic [31:0] next_pc,
  output logic [31:0] pc
);

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      pc <= RESET_VECTOR;
    end else if (en) begin
      pc <= next_pc;
    end
  end

endmodule : pc_reg

`endif // PC_REG_SV
