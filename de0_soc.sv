// ============================================================================
// File: de0_soc.sv
// Description: Memory-optimized SoC instance tailored for Cyclone III EP3C16.
//              - 16 KB Boot ROM (16 M9K blocks)
//              - 32 KB Main SRAM (32 M9K blocks)
//              - Integrated hardware UART TX + UART RX
//              - 64-bit Hardware Real-Time Timer
// ============================================================================

`timescale 1ns / 1ps

`include "rv32i_pkg.sv"

module de0_soc #(
  parameter     ROM_HEX            = "sw/flappy_bird.hex",
  parameter     RAM_HEX            = "sw/flappy_bird_ram.hex",
  parameter int CLK_FREQ           = 50_000_000,
  parameter int BAUD_RATE          = 115_200
)(
  input  logic        clk,
  input  logic        rst_n,
  input  logic        uart_rx_pin,
  output logic        uart_tx_pin,
  output logic        uart_tx_active,
  output logic        uart_rx_active,
  output logic        timer_irq,
  output logic        sim_exit_valid,
  output logic [31:0] sim_exit_data,
  output logic [31:0] debug_pc,
  output logic [31:0] debug_inst
);

  import rv32i_pkg::*;

  // --------------------------------------------------------------------------
  // Interconnect Point-to-Point Signals
  // --------------------------------------------------------------------------

  // CPU Master
  logic [31:0] cpu_addr;
  logic [31:0] cpu_wdata;
  logic [3:0]  cpu_wstrb;
  logic        cpu_valid;
  logic [31:0] cpu_rdata;
  logic        cpu_ready;

  // ROM Slave
  logic [31:0] rom_addr;
  logic [31:0] rom_wdata;
  logic [3:0]  rom_wstrb;
  logic        rom_valid;
  logic [31:0] rom_rdata;
  logic        rom_ready;

  // RAM Slave
  logic [31:0] ram_addr;
  logic [31:0] ram_wdata;
  logic [3:0]  ram_wstrb;
  logic        ram_valid;
  logic [31:0] ram_rdata;
  logic        ram_ready;

  // UART Slave
  logic [31:0] uart_addr;
  logic [31:0] uart_wdata;
  logic [3:0]  uart_wstrb;
  logic        uart_valid;
  logic [31:0] uart_rdata;
  logic        uart_ready;

  // Timer Slave
  logic [31:0] timer_addr;
  logic [31:0] timer_wdata;
  logic [3:0]  timer_wstrb;
  logic        timer_valid;
  logic [31:0] timer_rdata;
  logic        timer_ready;

  // --------------------------------------------------------------------------
  // UART Receiver Hardware
  // --------------------------------------------------------------------------
  logic [7:0] rx_byte;
  logic       rx_byte_valid;
  logic       rx_byte_ready;

  uart_rx #(
    .CLK_FREQ  (CLK_FREQ),
    .BAUD_RATE (BAUD_RATE)
  ) u_uart_rx (
    .clk       (clk),
    .rst_n     (rst_n),
    .rx_pin    (uart_rx_pin),
    .rx_data   (rx_byte),
    .rx_valid  (rx_byte_valid),
    .rx_ready  (rx_byte_ready),
    .rx_busy   (uart_rx_active)
  );

  // --------------------------------------------------------------------------
  // RV32I Processor Core
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

  assign debug_pc   = u_core.pc;
  assign debug_inst = u_core.inst_reg;

  // --------------------------------------------------------------------------
  // Bus Interconnect Router
  // --------------------------------------------------------------------------
  bus_interconnect u_bus (
    .clk            (clk),
    .rst_n          (rst_n),

    .cpu_addr       (cpu_addr),
    .cpu_wdata      (cpu_wdata),
    .cpu_wstrb      (cpu_wstrb),
    .cpu_valid      (cpu_valid),
    .cpu_rdata      (cpu_rdata),
    .cpu_ready      (cpu_ready),

    .rom_addr       (rom_addr),
    .rom_wdata      (rom_wdata),
    .rom_wstrb      (rom_wstrb),
    .rom_valid      (rom_valid),
    .rom_rdata      (rom_rdata),
    .rom_ready      (rom_ready),

    .ram_addr       (ram_addr),
    .ram_wdata      (ram_wdata),
    .ram_wstrb      (ram_wstrb),
    .ram_valid      (ram_valid),
    .ram_rdata      (ram_rdata),
    .ram_ready      (ram_ready),

    .uart_addr      (uart_addr),
    .uart_wdata     (uart_wdata),
    .uart_wstrb     (uart_wstrb),
    .uart_valid     (uart_valid),
    .uart_rdata     (uart_rdata),
    .uart_ready     (uart_ready),

    .timer_addr     (timer_addr),
    .timer_wdata    (timer_wdata),
    .timer_wstrb    (timer_wstrb),
    .timer_valid    (timer_valid),
    .timer_rdata    (timer_rdata),
    .timer_ready    (timer_ready),

    .sim_exit_valid (sim_exit_valid),
    .sim_exit_data  (sim_exit_data)
  );

  // --------------------------------------------------------------------------
  // Boot ROM (16 KB = 4,096 words, fits in 16 M9K blocks)
  // --------------------------------------------------------------------------
  rom_sync #(
    .HEX_FILE   (ROM_HEX),
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
  // Main SRAM (32 KB = 8,192 words, fits in 32 M9K blocks)
  // --------------------------------------------------------------------------
  ram_sync #(
    .HEX_FILE   (RAM_HEX),
    .SIZE_BYTES (32768)
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
  // Memory-Mapped UART Controller (TX + RX)
  // --------------------------------------------------------------------------
  uart_tx #(
    .CLK_FREQ           (CLK_FREQ),
    .BAUD_RATE          (BAUD_RATE),
    .SIM_CONSOLE_OUTPUT (0)
  ) u_uart_tx (
    .clk          (clk),
    .rst_n        (rst_n),
    .addr         (uart_addr),
    .wdata        (uart_wdata),
    .wstrb        (uart_wstrb),
    .valid        (uart_valid),
    .rdata        (uart_rdata),
    .ready        (uart_ready),
    .tx           (uart_tx_pin),
    .rx_valid_in  (rx_byte_valid),
    .rx_data_in   (rx_byte),
    .rx_ready_out (rx_byte_ready)
  );

  assign uart_tx_active = u_uart_tx.tx_busy;

  // --------------------------------------------------------------------------
  // 64-bit Hardware Timer
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

endmodule : de0_soc
