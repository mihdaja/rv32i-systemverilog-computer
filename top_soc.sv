// ============================================================================
// File: top_soc.sv
// Description: Top-Level System-on-Chip integrating RV32I Core, Interconnect,
//              Boot ROM, Main SRAM, UART transmitter, and Hardware Timer.
// ============================================================================

`timescale 1ns / 1ps

`ifndef TOP_SOC_SV
`define TOP_SOC_SV

`include "rv32i_pkg.sv"

module top_soc #(
  parameter     HEX_FILE           = "",
  parameter     ROM_HEX            = "",
  parameter     RAM_HEX            = "",
  parameter int CLK_FREQ           = 50_000_000,
  parameter int BAUD_RATE          = 115200,
  parameter bit SIM_CONSOLE_OUTPUT = 1
)(
  input  logic        clk,
  input  logic        rst_n,
  output logic        uart_tx_out,
  output logic        sim_exit_valid,
  output logic [31:0] sim_exit_data,
  input  logic        uart_rx_valid_in = 1'b0,
  input  logic [7:0]  uart_rx_data_in  = 8'h00,
  output logic        uart_rx_ready_out
);

  import rv32i_pkg::*;

  localparam ACTUAL_ROM_HEX = (ROM_HEX != "") ? ROM_HEX : HEX_FILE;

`ifdef USE_BUS_IF
  // System Bus Interfaces
  bus_if cpu_bus   (.clk(clk), .rst_n(rst_n));
  bus_if rom_bus   (.clk(clk), .rst_n(rst_n));
  bus_if ram_bus   (.clk(clk), .rst_n(rst_n));
  bus_if uart_bus  (.clk(clk), .rst_n(rst_n));
  bus_if timer_bus (.clk(clk), .rst_n(rst_n));

  // RV32I Processor Core
  rv32i_core u_core (
    .bus (cpu_bus.master)
  );

  // Bus Interconnect Router
  bus_interconnect u_bus (
    .cpu_bus        (cpu_bus.slave),
    .rom_bus        (rom_bus.master),
    .ram_bus        (ram_bus.master),
    .uart_bus       (uart_bus.master),
    .timer_bus      (timer_bus.master),
    .sim_exit_valid (sim_exit_valid),
    .sim_exit_data  (sim_exit_data)
  );

  // Synchronous Boot ROM (16 KB)
  rom_sync #(
    .HEX_FILE   (ACTUAL_ROM_HEX),
    .SIZE_BYTES (16384)
  ) u_rom (
    .bus (rom_bus.slave)
  );

  // Synchronous Main SRAM (64 KB)
  ram_sync #(
    .HEX_FILE   (RAM_HEX),
    .SIZE_BYTES (65536)
  ) u_ram (
    .bus (ram_bus.slave)
  );

  // Memory-Mapped UART Transmitter
  uart_tx #(
    .CLK_FREQ           (CLK_FREQ),
    .BAUD_RATE          (BAUD_RATE),
    .SIM_CONSOLE_OUTPUT (SIM_CONSOLE_OUTPUT)
  ) u_uart (
    .bus (uart_bus.slave),
    .tx  (uart_tx_out)
  );

  // 64-bit Hardware Timer
  logic timer_irq;
  system_timer u_timer (
    .bus       (timer_bus.slave),
    .timer_irq (timer_irq)
  );

`else
  // --------------------------------------------------------------------------
  // Interconnect Point-to-Point Wires
  // --------------------------------------------------------------------------

  // CPU Master Bus
  logic [31:0] cpu_addr;
  logic [31:0] cpu_wdata;
  logic [3:0]  cpu_wstrb;
  logic        cpu_valid;
  logic [31:0] cpu_rdata;
  logic        cpu_ready;

  // ROM Slave Bus
  logic [31:0] rom_addr;
  logic [31:0] rom_wdata;
  logic [3:0]  rom_wstrb;
  logic        rom_valid;
  logic [31:0] rom_rdata;
  logic        rom_ready;

  // RAM Slave Bus
  logic [31:0] ram_addr;
  logic [31:0] ram_wdata;
  logic [3:0]  ram_wstrb;
  logic        ram_valid;
  logic [31:0] ram_rdata;
  logic        ram_ready;

  // UART Slave Bus
  logic [31:0] uart_addr;
  logic [31:0] uart_wdata;
  logic [3:0]  uart_wstrb;
  logic        uart_valid;
  logic [31:0] uart_rdata;
  logic        uart_ready;

  // Timer Slave Bus
  logic [31:0] timer_addr;
  logic [31:0] timer_wdata;
  logic [3:0]  timer_wstrb;
  logic        timer_valid;
  logic [31:0] timer_rdata;
  logic        timer_ready;

  // Timer Interrupt
  logic        timer_irq;

  // --------------------------------------------------------------------------
  // RV32I Processor Core Instance
  // --------------------------------------------------------------------------
  rv32i_core u_core (
    .clk       (clk),
    .rst_n     (rst_n),
    .bus_addr  (cpu_addr),
    .bus_wdata (cpu_wdata),
    .bus_wstrb (cpu_wstrb),
    .bus_valid (cpu_valid),
    .bus_rdata (cpu_rdata),
    .bus_ready (cpu_ready)
  );

  // --------------------------------------------------------------------------
  // Bus Interconnect Router Instance
  // --------------------------------------------------------------------------
  bus_interconnect u_bus (
    .clk            (clk),
    .rst_n          (rst_n),

    // CPU Master Interface
    .cpu_addr       (cpu_addr),
    .cpu_wdata      (cpu_wdata),
    .cpu_wstrb      (cpu_wstrb),
    .cpu_valid      (cpu_valid),
    .cpu_rdata      (cpu_rdata),
    .cpu_ready      (cpu_ready),

    // ROM Slave Interface
    .rom_addr       (rom_addr),
    .rom_wdata      (rom_wdata),
    .rom_wstrb      (rom_wstrb),
    .rom_valid      (rom_valid),
    .rom_rdata      (rom_rdata),
    .rom_ready      (rom_ready),

    // RAM Slave Interface
    .ram_addr       (ram_addr),
    .ram_wdata      (ram_wdata),
    .ram_wstrb      (ram_wstrb),
    .ram_valid      (ram_valid),
    .ram_rdata      (ram_rdata),
    .ram_ready      (ram_ready),

    // UART Slave Interface
    .uart_addr      (uart_addr),
    .uart_wdata     (uart_wdata),
    .uart_wstrb     (uart_wstrb),
    .uart_valid     (uart_valid),
    .uart_rdata     (uart_rdata),
    .uart_ready     (uart_ready),

    // Timer Slave Interface
    .timer_addr     (timer_addr),
    .timer_wdata    (timer_wdata),
    .timer_wstrb    (timer_wstrb),
    .timer_valid    (timer_valid),
    .timer_rdata    (timer_rdata),
    .timer_ready    (timer_ready),

    // Simulation Trap Interface
    .sim_exit_valid (sim_exit_valid),
    .sim_exit_data  (sim_exit_data)
  );

  // --------------------------------------------------------------------------
  // Boot ROM Instance (16 KB)
  // --------------------------------------------------------------------------
  rom_sync #(
    .HEX_FILE   (ACTUAL_ROM_HEX),
    .SIZE_BYTES (16384)
  ) u_rom (
    .clk   (clk),
    .rst_n (rst_n),
    .addr  (rom_addr),
    .wdata (rom_wdata),
    .wstrb (rom_wstrb),
    .valid (rom_valid),
    .rdata (rom_rdata),
    .ready (rom_ready)
  );

  // --------------------------------------------------------------------------
  // Main SRAM Instance (64 KB)
  // --------------------------------------------------------------------------
  ram_sync #(
    .HEX_FILE   (RAM_HEX),
    .SIZE_BYTES (65536)
  ) u_ram (
    .clk   (clk),
    .rst_n (rst_n),
    .addr  (ram_addr),
    .wdata (ram_wdata),
    .wstrb (ram_wstrb),
    .valid (ram_valid),
    .rdata (ram_rdata),
    .ready (ram_ready)
  );

  // --------------------------------------------------------------------------
  // UART Transmitter Peripheral Instance
  // --------------------------------------------------------------------------
  uart_tx #(
    .CLK_FREQ           (CLK_FREQ),
    .BAUD_RATE          (BAUD_RATE),
    .SIM_CONSOLE_OUTPUT (SIM_CONSOLE_OUTPUT)
  ) u_uart (
    .clk   (clk),
    .rst_n (rst_n),
    .addr  (uart_addr),
    .wdata (uart_wdata),
    .wstrb (uart_wstrb),
    .valid (uart_valid),
    .rdata        (uart_rdata),
    .ready        (uart_ready),
    .tx           (uart_tx_out),
    .rx_valid_in  (uart_rx_valid_in),
    .rx_data_in   (uart_rx_data_in),
    .rx_ready_out (uart_rx_ready_out)
  );

  // --------------------------------------------------------------------------
  // System Real-Time Timer Instance
  // --------------------------------------------------------------------------
  system_timer u_timer (
    .clk       (clk),
    .rst_n     (rst_n),
    .addr      (timer_addr),
    .wdata     (timer_wdata),
    .wstrb     (timer_wstrb),
    .valid     (timer_valid),
    .rdata     (timer_rdata),
    .ready     (timer_ready),
    .timer_irq (timer_irq)
  );

`endif

endmodule : top_soc

`endif // TOP_SOC_SV
