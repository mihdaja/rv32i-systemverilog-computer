// ============================================================================
// File: bus_interconnect.sv
// Description: System bus interconnect router for RV32I SoC.
//              Routes memory-mapped transactions from the CPU master to slaves:
//                - ROM:   0x0000_0000 to 0x0000_3FFF (16 KB)
//                - RAM:   0x1000_0000 to 0x1000_FFFF (64 KB)
//                - UART:  0x2000_0000 to 0x2000_000F (16 B)
//                - Timer: 0x2000_0010 to 0x2000_001F (16 B)
//                - Trap:  0x2000_00FC (Host Simulation Exit)
// ============================================================================

`timescale 1ns / 1ps

`ifndef BUS_INTERCONNECT_SV
`define BUS_INTERCONNECT_SV

`include "rv32i_pkg.sv"

`ifdef USE_BUS_IF
module bus_interconnect
  import rv32i_pkg::*;
(
  bus_if.slave  cpu_bus,
  bus_if.master rom_bus,
  bus_if.master ram_bus,
  bus_if.master uart_bus,
  bus_if.master timer_bus,
  output logic        sim_exit_valid,
  output logic [31:0] sim_exit_data
);
  wire        clk       = cpu_bus.clk;
  wire        rst_n     = cpu_bus.rst_n;
  wire [31:0] cpu_addr  = cpu_bus.addr;
  wire [31:0] cpu_wdata = cpu_bus.wdata;
  wire [3:0]  cpu_wstrb = cpu_bus.wstrb;
  wire        cpu_valid = cpu_bus.valid;
  logic [31:0] cpu_rdata;
  logic        cpu_ready;
  assign cpu_bus.rdata = cpu_rdata;
  assign cpu_bus.ready = cpu_ready;

  logic [31:0] rom_addr;
  logic [31:0] rom_wdata;
  logic [3:0]  rom_wstrb;
  logic        rom_valid;
  wire  [31:0] rom_rdata = rom_bus.rdata;
  wire         rom_ready = rom_bus.ready;
  assign rom_bus.addr  = rom_addr;
  assign rom_bus.wdata = rom_wdata;
  assign rom_bus.wstrb = rom_wstrb;
  assign rom_bus.valid = rom_valid;

  logic [31:0] ram_addr;
  logic [31:0] ram_wdata;
  logic [3:0]  ram_wstrb;
  logic        ram_valid;
  wire  [31:0] ram_rdata = ram_bus.rdata;
  wire         ram_ready = ram_bus.ready;
  assign ram_bus.addr  = ram_addr;
  assign ram_bus.wdata = ram_wdata;
  assign ram_bus.wstrb = ram_wstrb;
  assign ram_bus.valid = ram_valid;

  logic [31:0] uart_addr;
  logic [31:0] uart_wdata;
  logic [3:0]  uart_wstrb;
  logic        uart_valid;
  wire  [31:0] uart_rdata = uart_bus.rdata;
  wire         uart_ready = uart_bus.ready;
  assign uart_bus.addr  = uart_addr;
  assign uart_bus.wdata = uart_wdata;
  assign uart_bus.wstrb = uart_wstrb;
  assign uart_bus.valid = uart_valid;

  logic [31:0] timer_addr;
  logic [31:0] timer_wdata;
  logic [3:0]  timer_wstrb;
  logic        timer_valid;
  wire  [31:0] timer_rdata = timer_bus.rdata;
  wire         timer_ready = timer_bus.ready;
  assign timer_bus.addr  = timer_addr;
  assign timer_bus.wdata = timer_wdata;
  assign timer_bus.wstrb = timer_wstrb;
  assign timer_bus.valid = timer_valid;

`else
module bus_interconnect
  import rv32i_pkg::*;
(
  input  logic        clk,
  input  logic        rst_n,

  // CPU Master Interface
  input  logic [31:0] cpu_addr,
  input  logic [31:0] cpu_wdata,
  input  logic [3:0]  cpu_wstrb,
  input  logic        cpu_valid,
  output logic [31:0] cpu_rdata,
  output logic        cpu_ready,

  // ROM Slave Interface
  output logic [31:0] rom_addr,
  output logic [31:0] rom_wdata,
  output logic [3:0]  rom_wstrb,
  output logic        rom_valid,
  input  logic [31:0] rom_rdata,
  input  logic        rom_ready,

  // RAM Slave Interface
  output logic [31:0] ram_addr,
  output logic [31:0] ram_wdata,
  output logic [3:0]  ram_wstrb,
  output logic        ram_valid,
  input  logic [31:0] ram_rdata,
  input  logic        ram_ready,

  // UART Slave Interface
  output logic [31:0] uart_addr,
  output logic [31:0] uart_wdata,
  output logic [3:0]  uart_wstrb,
  output logic        uart_valid,
  input  logic [31:0] uart_rdata,
  input  logic        uart_ready,

  // Timer Slave Interface
  output logic [31:0] timer_addr,
  output logic [31:0] timer_wdata,
  output logic [3:0]  timer_wstrb,
  output logic        timer_valid,
  input  logic [31:0] timer_rdata,
  input  logic        timer_ready,

  // Host Simulation Trap (0x2000_00FC)
  output logic        sim_exit_valid,
  output logic [31:0] sim_exit_data
);
`endif

  // --------------------------------------------------------------------------
  // Address Decoding Logic
  // --------------------------------------------------------------------------
  logic sel_rom;
  logic sel_ram;
  logic sel_uart;
  logic sel_timer;
  logic sel_sim;
  logic sel_unmapped;

  always_comb begin
    sel_rom      = (cpu_addr >= ROM_BASE   && cpu_addr <= ROM_END);
    sel_ram      = (cpu_addr >= RAM_BASE   && cpu_addr <= RAM_END);
    sel_uart     = (cpu_addr >= UART_BASE  && cpu_addr <= UART_END);
    sel_timer    = (cpu_addr >= TIMER_BASE && cpu_addr <= TIMER_END);
    sel_sim      = (cpu_addr == SIM_EXIT_ADDR);
    sel_unmapped = !(sel_rom || sel_ram || sel_uart || sel_timer || sel_sim);
  end

  // --------------------------------------------------------------------------
  // Request Routing
  // --------------------------------------------------------------------------
  // Broadcast address and write data; gate valid and strobes per target slave
  assign rom_addr    = cpu_addr;
  assign rom_wdata   = cpu_wdata;
  assign rom_wstrb   = sel_rom ? cpu_wstrb : 4'b0000;
  assign rom_valid   = cpu_valid && sel_rom;

  assign ram_addr    = cpu_addr;
  assign ram_wdata   = cpu_wdata;
  assign ram_wstrb   = sel_ram ? cpu_wstrb : 4'b0000;
  assign ram_valid   = cpu_valid && sel_ram;

  assign uart_addr   = cpu_addr;
  assign uart_wdata  = cpu_wdata;
  assign uart_wstrb  = sel_uart ? cpu_wstrb : 4'b0000;
  assign uart_valid  = cpu_valid && sel_uart;

  assign timer_addr  = cpu_addr;
  assign timer_wdata = cpu_wdata;
  assign timer_wstrb = sel_timer ? cpu_wstrb : 4'b0000;
  assign timer_valid = cpu_valid && sel_timer;

  // --------------------------------------------------------------------------
  // Response Multiplexing
  // --------------------------------------------------------------------------
  always_comb begin
    if (sel_rom) begin
      cpu_rdata = rom_rdata;
      cpu_ready = rom_ready;
    end else if (sel_ram) begin
      cpu_rdata = ram_rdata;
      cpu_ready = ram_ready;
    end else if (sel_uart) begin
      cpu_rdata = uart_rdata;
      cpu_ready = uart_ready;
    end else if (sel_timer) begin
      cpu_rdata = timer_rdata;
      cpu_ready = timer_ready;
    end else if (sel_sim) begin
      cpu_rdata = sim_exit_data;
      cpu_ready = cpu_valid;
    end else begin
      // Unmapped address: acknowledge immediately with poison word to prevent CPU hang
      cpu_rdata = 32'hDEAD_BEEF;
      cpu_ready = cpu_valid;
    end
  end

  // --------------------------------------------------------------------------
  // Host Simulation Exit Trap Register (0x2000_00FC)
  // --------------------------------------------------------------------------
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      sim_exit_valid <= 1'b0;
      sim_exit_data  <= 32'b0;
    end else begin
      if (cpu_valid && sel_sim && |cpu_wstrb) begin
        sim_exit_valid <= 1'b1;
        sim_exit_data  <= cpu_wdata;
      end else begin
        sim_exit_valid <= 1'b0;
      end
    end
  end

endmodule : bus_interconnect

`endif // BUS_INTERCONNECT_SV
