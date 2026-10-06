`timescale 1ns/1ps

`ifndef REG_FILE_SV
`define REG_FILE_SV

import rv32i_pkg::*;

module reg_file (
  input  logic        clk,
  input  logic        rst_n,
  input  logic        we,
  input  logic [4:0]  waddr,
  input  logic [31:0] wdata,
  input  logic [4:0]  raddr1,
  input  logic [4:0]  raddr2,
  output logic [31:0] rdata1,
  output logic [31:0] rdata2
);

  logic [31:0] regs [31:0];

  // Asynchronous combinational reads (x0 is hardwired to 0)
  assign rdata1 = (raddr1 == 5'd0) ? 32'd0 : regs[raddr1];
  assign rdata2 = (raddr2 == 5'd0) ? 32'd0 : regs[raddr2];

  // Synchronous write with active-low asynchronous reset
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (int i = 0; i < 32; i++) begin
        regs[i] <= 32'd0;
      end
    end else if (we && (waddr != 5'd0)) begin
      regs[waddr] <= wdata;
    end
  end

endmodule : reg_file

`endif // REG_FILE_SV
