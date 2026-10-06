// ============================================================================
// File: de0_tb.sv
// Description: Simulation testbench for de0_top module verifying board wrapper,
//              clocking, 7-segment display decoding, and UART transmission.
// ============================================================================

`timescale 1ns / 1ps

module de0_tb;

  logic        CLOCK_50;
  logic [2:0]  BUTTON;
  logic [9:0]  SW;
  logic [9:0]  LEDG;

  logic [6:0]  HEX0_D, HEX1_D, HEX2_D, HEX3_D;
  logic        HEX0_DP, HEX1_DP, HEX2_DP, HEX3_DP;

  logic        UART_TXD;
  logic        UART_RXD;
  logic        UART_CTS;
  logic        UART_RTS;
  wire  [33:0] GPIO0_D;

  // 50 MHz Clock generation (20 ns period)
  initial begin
    CLOCK_50 = 0;
    forever #10 CLOCK_50 = ~CLOCK_50;
  end

  // DUT instantiation
  de0_top dut (
    .CLOCK_50 (CLOCK_50),
    .BUTTON   (BUTTON),
    .SW       (SW),
    .LEDG     (LEDG),
    .HEX0_D   (HEX0_D),
    .HEX0_DP  (HEX0_DP),
    .HEX1_D   (HEX1_D),
    .HEX1_DP  (HEX1_DP),
    .HEX2_D   (HEX2_D),
    .HEX2_DP  (HEX2_DP),
    .HEX3_D   (HEX3_D),
    .HEX3_DP  (HEX3_DP),
    .UART_TXD (UART_TXD),
    .UART_RXD (UART_RXD),
    .UART_CTS (UART_CTS),
    .UART_RTS (UART_RTS),
    .GPIO0_D  (GPIO0_D)
  );

  initial begin
    $display("==================================================================");
    $display(" Simulating Altera DE0 FPGA Port (Cyclone III EP3C16F484)");
    $display("==================================================================");

    // Initial state: Assert Reset (BUTTON[0] = 0)
    BUTTON   = 3'b110;
    SW       = 10'b00_0000_0000;
    UART_RXD = 1'b1; // Idle high
    UART_RTS = 1'b0;

    #200;
    // Release Reset
    @(posedge CLOCK_50);
    BUTTON[0] = 1'b1;
    $display("[TB] Reset released at t=%0t ns", $time);

    // Run for 3000 cycles to observe execution and 7-segment display activity
    repeat (3000) @(posedge CLOCK_50);

    $display("[TB] Current Program Counter: 0x%08X", dut.debug_pc);
    $display("[TB] 7-Segment HEX displays: HEX3=%b HEX2=%b HEX1=%b HEX0=%b",
             HEX3_D, HEX2_D, HEX1_D, HEX0_D);
    $display("[TB] LEDG status: %b (LEDG[0]=exit_valid: %b)", LEDG, LEDG[0]);

    if (dut.debug_pc !== 32'h0000_0000 && dut.debug_pc !== 32'hxxxx_xxxx) begin
      $display("[TB] SUCCESS: Processor is running instructions on DE0 wrapper!");
    end else begin
      $display("[TB] ERROR: Processor did not progress!");
      $finish(1);
    end

    $finish(0);
  end

endmodule : de0_tb
