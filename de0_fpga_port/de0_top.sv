// ============================================================================
// File: de0_top.sv
// Description: Top-level board wrapper for Altera/Terasic DE0 Education Board
//              (Cyclone III EP3C16F484C6) for TU Delft CSE 2420 Digital Systems.
//
// Board Pin Mapping:
//   - CLOCK_50       : PIN_G21 (50 MHz on-board oscillator)
//   - BUTTON[0]      : PIN_H2  (Active-low push button -> System Reset)
//   - BUTTON[1]      : PIN_G3  (Active-low push button -> User Input)
//   - BUTTON[2]      : PIN_F1  (Active-low push button -> User Input)
//   - SW[9:0]        : PIN_D2, E4, E3, H7, J7, G5, G4, H6, H5, J6
//   - HEX0..HEX3     : 4x 7-Segment Displays (Active-Low Cathodes)
//   - LEDG[9:0]      : 10x Green Status LEDs
//   - UART_TXD       : PIN_B8  (RS-232 DB9 Connector via MAX3232)
//   - UART_RXD       : PIN_A8  (RS-232 DB9 Connector via MAX3232)
//   - GPIO0_D[0]     : PIN_D3  (Header pin for 3.3V USB-UART TX bridge)
//   - GPIO0_D[1]     : PIN_C3  (Header pin for 3.3V USB-UART RX bridge)
// ============================================================================

`timescale 1ns / 1ps

module de0_top (
  // 50 MHz Master Clock
  input  logic        CLOCK_50,

  // Push Buttons (Active-Low: 0 when pressed, 1 when idle)
  input  logic [2:0]  BUTTON,

  // Slide Switches (1 when UP, 0 when DOWN)
  input  logic [9:0]  SW,

  // 10 Green LEDs (1 = ON, 0 = OFF)
  output logic [9:0]  LEDG,

  // 4x 7-Segment Displays (Active-Low: 0 = Segment ON)
  output logic [6:0]  HEX0_D,
  output logic        HEX0_DP,
  output logic [6:0]  HEX1_D,
  output logic        HEX1_DP,
  output logic [6:0]  HEX2_D,
  output logic        HEX2_DP,
  output logic [6:0]  HEX3_D,
  output logic        HEX3_DP,

  // RS-232 DB9 Serial Port
  output logic        UART_TXD,
  input  logic        UART_RXD,
  output logic        UART_CTS,
  input  logic        UART_RTS,

  // GPIO Header Pins (Optional 3.3V USB-to-UART bridge)
  inout  logic [33:0] GPIO0_D
);

  // --------------------------------------------------------------------------
  // Reset Synchronizer (Active-Low)
  // BUTTON[0] is physically active-low (0 when pressed).
  // SW[0] provides an optional manual reset override (UP = Reset).
  // --------------------------------------------------------------------------
  logic rst_sync1, rst_n;
  wire  raw_reset_n = BUTTON[0] & (~SW[0]);

  always_ff @(posedge CLOCK_50 or negedge raw_reset_n) begin
    if (!raw_reset_n) begin
      rst_sync1 <= 1'b0;
      rst_n     <= 1'b0;
    end else begin
      rst_sync1 <= 1'b1;
      rst_n     <= rst_sync1;
    end
  end

  // --------------------------------------------------------------------------
  // UART Input Multiplexing
  // SW[1] = 0 -> RS-232 DB9 serial port (PIN_A8)
  // SW[1] = 1 -> GPIO0 header pin (PIN_C3) for standard USB-UART adapter
  // --------------------------------------------------------------------------
  wire uart_rx_mux = SW[1] ? GPIO0_D[1] : UART_RXD;
  logic uart_tx_out;

  // Drive both the DB9 RS-232 port and the GPIO pin simultaneously
  assign UART_TXD   = uart_tx_out;
  assign GPIO0_D[0] = uart_tx_out;

  // RS-232 Flow control tie-offs
  assign UART_CTS = 1'b0; // Clear To Send asserted (active-low in RS232 standard)

  // --------------------------------------------------------------------------
  // SoC Instance
  // --------------------------------------------------------------------------
  logic        uart_tx_active;
  logic        uart_rx_active;
  logic        timer_irq;
  logic        sim_exit_valid;
  logic [31:0] sim_exit_data;
  logic [31:0] debug_pc;
  logic [31:0] debug_inst;

  de0_soc u_soc (
    .clk            (CLOCK_50),
    .rst_n          (rst_n),
    .uart_rx_pin    (uart_rx_mux),
    .uart_tx_pin    (uart_tx_out),
    .uart_tx_active (uart_tx_active),
    .uart_rx_active (uart_rx_active),
    .timer_irq      (timer_irq),
    .sim_exit_valid (sim_exit_valid),
    .sim_exit_data  (sim_exit_data),
    .debug_pc       (debug_pc),
    .debug_inst     (debug_inst)
  );

  // --------------------------------------------------------------------------
  // LED Status Indicators
  // --------------------------------------------------------------------------
  assign LEDG[0]   = sim_exit_valid;                    // Game Over / Trap indicator
  assign LEDG[1]   = uart_tx_active;                    // UART Transmitting
  assign LEDG[2]   = uart_rx_active;                    // UART Receiving
  assign LEDG[3]   = timer_irq;                         // Real-Time Timer IRQ
  assign LEDG[9:4] = sim_exit_data[5:0];                // Exit/Score status bits

  // --------------------------------------------------------------------------
  // 7-Segment Display Output Multiplexing
  // SW[3:2]:
  //   00 : Program Counter (debug_pc[15:0])
  //   01 : Instruction Word Lower Half (debug_inst[15:0])
  //   10 : Instruction Word Upper Half (debug_inst[31:16])
  //   11 : Simulation Exit / Result Code (sim_exit_data[15:0])
  // --------------------------------------------------------------------------
  wire [1:0] disp_mode = SW[3:2];
  wire [15:0] hex_display_val = (disp_mode == 2'b00) ? debug_pc[15:0] :
                                (disp_mode == 2'b01) ? debug_inst[15:0] :
                                (disp_mode == 2'b10) ? debug_inst[31:16] :
                                                       sim_exit_data[15:0];

  seven_seg_decoder u_hex0 (.hex_digit(hex_display_val[3:0]),   .seg_out(HEX0_D));
  seven_seg_decoder u_hex1 (.hex_digit(hex_display_val[7:4]),   .seg_out(HEX1_D));
  seven_seg_decoder u_hex2 (.hex_digit(hex_display_val[11:8]),  .seg_out(HEX2_D));
  seven_seg_decoder u_hex3 (.hex_digit(hex_display_val[15:12]), .seg_out(HEX3_D));

  // Decimal points off (1 = off for active-low)
  assign HEX0_DP = 1'b1;
  assign HEX1_DP = 1'b1;
  assign HEX2_DP = 1'b1;
  assign HEX3_DP = 1'b1;

endmodule : de0_top
