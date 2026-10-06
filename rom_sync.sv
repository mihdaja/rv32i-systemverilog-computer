// ============================================================================
// File: rom_sync.sv
// Description: Synchronous Boot ROM for RV32I SoC.
//              Supports preloading machine code via HEX_FILE parameter using
//              $readmemh. Returns 32-bit instruction words with 1-cycle latency.
// ============================================================================

`timescale 1ns / 1ps

`ifndef ROM_SYNC_SV
`define ROM_SYNC_SV

`include "rv32i_pkg.sv"

`ifdef USE_BUS_IF
module rom_sync
  import rv32i_pkg::*;
#(
  parameter HEX_FILE   = "",
  parameter int    SIZE_BYTES = 16384
)(
  bus_if.slave bus
);
  wire        clk   = bus.clk;
  wire        rst_n = bus.rst_n;
  wire [31:0] addr  = bus.addr;
  wire [31:0] wdata = bus.wdata;
  wire [3:0]  wstrb = bus.wstrb;
  wire        valid = bus.valid;
  logic [31:0] rdata;
  logic        ready;
  assign bus.rdata = rdata;
  assign bus.ready = ready;

`else
module rom_sync
  import rv32i_pkg::*;
#(
  parameter HEX_FILE   = "",
  parameter int    SIZE_BYTES = 16384
)(
  input  logic        clk,
  input  logic        rst_n,
  input  logic [31:0] addr,
  input  logic [31:0] wdata,
  input  logic [3:0]  wstrb,
  input  logic        valid,
  output logic [31:0] rdata,
  output logic        ready
);
`endif

  // Calculate memory depth in 32-bit words
  localparam int unsigned WORDS      = SIZE_BYTES / 4;
  localparam int unsigned ADDR_WIDTH = (WORDS > 1) ? $clog2(WORDS) : 1;

  // ROM storage
  logic [31:0] mem [0:WORDS-1];

  // Address calculation (relative to ROM_BASE = 0x0000_0000)
  wire [31:0] offset   = addr - ROM_BASE;
  wire [ADDR_WIDTH-1:0] word_idx = offset[ADDR_WIDTH+1:2];
  wire in_range = (addr >= ROM_BASE && addr < (ROM_BASE + SIZE_BYTES));

  // Memory initialization: default to NOP (addi x0, x0, 0 = 0x0000_0013)
  initial begin
    for (int i = 0; i < WORDS; i++) begin
      mem[i] = 32'h0000_0013;
    end
    if (HEX_FILE != "") begin
      $readmemh(HEX_FILE, mem);
    end
  end

  // Synchronous read response
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      rdata <= 32'h0;
      ready <= 1'b0;
    end else begin
      ready <= valid;
      if (valid && in_range) begin
        rdata <= mem[word_idx];
      end else begin
        rdata <= 32'h0;
      end
    end
  end

`ifndef SYNTHESIS
  // Simulation warning on illegal write attempts to ROM
  always @(posedge clk) begin
    if (rst_n && valid && |wstrb && in_range) begin
      $display("[ROM_SYNC WARNING] Attempted write to read-only ROM at addr 0x%08h (wdata=0x%08h, wstrb=%b)", addr, wdata, wstrb);
    end
  end
`endif

endmodule : rom_sync

`endif // ROM_SYNC_SV
