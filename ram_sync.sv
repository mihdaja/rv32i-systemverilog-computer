// ============================================================================
// File: ram_sync.sv
// Description: Synchronous Main SRAM for RV32I SoC.
//              Supports 4-bit byte write strobes (wstrb[3:0]) for sb, sh, sw.
//              Supports optional initialization via HEX_FILE parameter.
//              Provides 1-cycle read/write access with write-first forwarding.
// ============================================================================

`timescale 1ns / 1ps

`ifndef RAM_SYNC_SV
`define RAM_SYNC_SV

`include "rv32i_pkg.sv"

`ifdef USE_BUS_IF
module ram_sync
  import rv32i_pkg::*;
#(
  parameter HEX_FILE   = "",
  parameter int    SIZE_BYTES = 65536
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
module ram_sync
  import rv32i_pkg::*;
#(
  parameter HEX_FILE   = "",
  parameter int    SIZE_BYTES = 65536
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

  // Memory geometry
  localparam int unsigned WORDS      = SIZE_BYTES / 4;
  localparam int unsigned ADDR_WIDTH = (WORDS > 1) ? $clog2(WORDS) : 1;

  // RAM storage
  logic [31:0] mem [0:WORDS-1];

  // Address offset relative to RAM_BASE (0x1000_0000)
  wire [31:0] offset   = addr - RAM_BASE;
  wire [ADDR_WIDTH-1:0] word_idx = offset[ADDR_WIDTH+1:2];
  wire in_range = (addr >= RAM_BASE && addr < (RAM_BASE + SIZE_BYTES));

  // Memory initialization: zero-initialize all words, then load hex if specified
  initial begin
    for (int i = 0; i < WORDS; i++) begin
      mem[i] = 32'h0;
    end
    if (HEX_FILE != "") begin
      $readmemh(HEX_FILE, mem);
    end
  end

  // Synchronous read / write with byte enable masking
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      rdata <= 32'h0;
      ready <= 1'b0;
    end else begin
      ready <= valid;
      if (valid && in_range) begin
        // Byte write strobes
        if (wstrb[0]) mem[word_idx][ 7: 0] <= wdata[ 7: 0];
        if (wstrb[1]) mem[word_idx][15: 8] <= wdata[15: 8];
        if (wstrb[2]) mem[word_idx][23:16] <= wdata[23:16];
        if (wstrb[3]) mem[word_idx][31:24] <= wdata[31:24];

        // Write-first read forwarding: newly written bytes are reflected immediately in rdata
        rdata[ 7: 0] <= wstrb[0] ? wdata[ 7: 0] : mem[word_idx][ 7: 0];
        rdata[15: 8] <= wstrb[1] ? wdata[15: 8] : mem[word_idx][15: 8];
        rdata[23:16] <= wstrb[2] ? wdata[23:16] : mem[word_idx][23:16];
        rdata[31:24] <= wstrb[3] ? wdata[31:24] : mem[word_idx][31:24];
      end else begin
        rdata <= 32'h0;
      end
    end
  end

endmodule : ram_sync

`endif // RAM_SYNC_SV
