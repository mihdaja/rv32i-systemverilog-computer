// ============================================================================
// File: system_timer.sv
// Description: 64-bit Hardware Real-Time Counter & Comparator for RV32I SoC.
//              Registers:
//                - 0x2000_0010: mtime lower 32 bits (increments each clock cycle).
//                - 0x2000_0014: mtime upper 32 bits.
//                - 0x2000_0018: mtimecmp lower 32 bits (read/write).
//                - 0x2000_001C: mtimecmp upper 32 bits (read/write).
//              Generates timer_irq interrupt signal when mtime >= mtimecmp.
// ============================================================================

`timescale 1ns / 1ps

`ifndef SYSTEM_TIMER_SV
`define SYSTEM_TIMER_SV

`include "rv32i_pkg.sv"

`ifdef USE_BUS_IF
module system_timer
  import rv32i_pkg::*;
(
  bus_if.slave  bus,
  output logic  timer_irq
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
module system_timer
  import rv32i_pkg::*;
(
  input  logic        clk,
  input  logic        rst_n,
  input  logic [31:0] addr,
  input  logic [31:0] wdata,
  input  logic [3:0]  wstrb,
  input  logic        valid,
  output logic [31:0] rdata,
  output logic        ready,
  output logic        timer_irq
);
`endif

  // 64-bit counter and compare registers
  logic [63:0] mtime;
  logic [63:0] mtimecmp;

  // Level-sensitive interrupt: asserted whenever mtime >= mtimecmp
  assign timer_irq = (mtime >= mtimecmp);

  // Address offset decode (0x0, 0x4, 0x8, 0xC)
  wire [1:0] reg_sel = addr[3:2];

  // Counter and Comparator update logic
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      mtime    <= 64'd0;
      mtimecmp <= 64'hFFFF_FFFF_FFFF_FFFF; // Max value to prevent spurious interrupts on boot
    end else begin
      // Handle mtime lower word write
      if (valid && (reg_sel == 2'b00) && |wstrb) begin
        if (wstrb[0]) mtime[ 7: 0] <= wdata[ 7: 0];
        if (wstrb[1]) mtime[15: 8] <= wdata[15: 8];
        if (wstrb[2]) mtime[23:16] <= wdata[23:16];
        if (wstrb[3]) mtime[31:24] <= wdata[31:24];
      end
      // Handle mtime upper word write
      else if (valid && (reg_sel == 2'b01) && |wstrb) begin
        if (wstrb[0]) mtime[39:32] <= wdata[ 7: 0];
        if (wstrb[1]) mtime[47:40] <= wdata[15: 8];
        if (wstrb[2]) mtime[55:48] <= wdata[23:16];
        if (wstrb[3]) mtime[63:56] <= wdata[31:24];
      end
      // Free-running increment when not being directly written
      else begin
        mtime <= mtime + 64'd1;
      end

      // Handle mtimecmp lower word write
      if (valid && (reg_sel == 2'b10) && |wstrb) begin
        if (wstrb[0]) mtimecmp[ 7: 0] <= wdata[ 7: 0];
        if (wstrb[1]) mtimecmp[15: 8] <= wdata[15: 8];
        if (wstrb[2]) mtimecmp[23:16] <= wdata[23:16];
        if (wstrb[3]) mtimecmp[31:24] <= wdata[31:24];
      end
      // Handle mtimecmp upper word write
      if (valid && (reg_sel == 2'b11) && |wstrb) begin
        if (wstrb[0]) mtimecmp[39:32] <= wdata[ 7: 0];
        if (wstrb[1]) mtimecmp[47:40] <= wdata[15: 8];
        if (wstrb[2]) mtimecmp[55:48] <= wdata[23:16];
        if (wstrb[3]) mtimecmp[63:56] <= wdata[31:24];
      end
    end
  end

  // Synchronous Bus Read Response
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      ready <= 1'b0;
      rdata <= 32'd0;
    end else begin
      ready <= valid;
      if (valid) begin
        case (reg_sel)
          2'b00:   rdata <= mtime[31:0];
          2'b01:   rdata <= mtime[63:32];
          2'b10:   rdata <= mtimecmp[31:0];
          2'b11:   rdata <= mtimecmp[63:32];
          default: rdata <= 32'd0;
        endcase
      end else begin
        rdata <= 32'd0;
      end
    end
  end

endmodule : system_timer

`endif // SYSTEM_TIMER_SV
