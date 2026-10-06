// ============================================================================
// File: bus_tb.sv
// Description: Comprehensive unit testbench for bus_interconnect and peripherals.
//              Verifies:
//                1. ROM address decode and read-only protection.
//                2. RAM address decode, full word and byte-strobe operations.
//                3. UART register decode, TX initiation, and status bit toggling.
//                4. System Timer increment, mtimecmp comparison, and IRQ generation.
//                5. Host simulation exit trap (0x2000_00FC).
//                6. Unmapped address handling and deadlock prevention.
// ============================================================================

`timescale 1ns / 1ps

`include "rv32i_pkg.sv"

module bus_tb;
  import rv32i_pkg::*;

  // Clock and reset signals
  logic clk;
  logic rst_n;

  // CPU Master bus signals
  logic [31:0] cpu_addr;
  logic [31:0] cpu_wdata;
  logic [3:0]  cpu_wstrb;
  logic        cpu_valid;
  logic [31:0] cpu_rdata;
  logic        cpu_ready;

  // ROM slave signals
  logic [31:0] rom_addr;
  logic [31:0] rom_wdata;
  logic [3:0]  rom_wstrb;
  logic        rom_valid;
  logic [31:0] rom_rdata;
  logic        rom_ready;

  // RAM slave signals
  logic [31:0] ram_addr;
  logic [31:0] ram_wdata;
  logic [3:0]  ram_wstrb;
  logic        ram_valid;
  logic [31:0] ram_rdata;
  logic        ram_ready;

  // UART slave signals
  logic [31:0] uart_addr;
  logic [31:0] uart_wdata;
  logic [3:0]  uart_wstrb;
  logic        uart_valid;
  logic [31:0] uart_rdata;
  logic        uart_ready;
  logic        uart_tx_line;

  // Timer slave signals
  logic [31:0] timer_addr;
  logic [31:0] timer_wdata;
  logic [3:0]  timer_wstrb;
  logic        timer_valid;
  logic [31:0] timer_rdata;
  logic        timer_ready;
  logic        timer_irq;

  // Sim exit signals
  logic        sim_exit_valid;
  logic [31:0] sim_exit_data;

  // Test statistics
  int error_count = 0;
  int test_count  = 0;

  // Clock generation: 50 MHz (20 ns period)
  always #10 clk = ~clk;

  // --------------------------------------------------------------------------
  // Device Under Test (DUT) & Peripheral Instantiations
  // --------------------------------------------------------------------------
  bus_interconnect u_interconnect (
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

  rom_sync #(
    .HEX_FILE   (""),
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

  ram_sync #(
    .HEX_FILE   (""),
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

  uart_tx #(
    .CLK_FREQ           (50_000_000),
    .BAUD_RATE          (5_000_000), // Fast baud for testing
    .CLK_DIV            (10),
    .SIM_CONSOLE_OUTPUT (0)
  ) u_uart (
    .clk   (clk),
    .rst_n (rst_n),
    .addr  (uart_addr),
    .wdata (uart_wdata),
    .wstrb (uart_wstrb),
    .valid (uart_valid),
    .rdata (uart_rdata),
    .ready (uart_ready),
    .tx    (uart_tx_line)
  );

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

  // --------------------------------------------------------------------------
  // Bus Master Helper Tasks
  // --------------------------------------------------------------------------
  task automatic bus_write(input [31:0] a, input [31:0] d, input [3:0] strb);
    @(posedge clk);
    cpu_addr  <= a;
    cpu_wdata <= d;
    cpu_wstrb <= strb;
    cpu_valid <= 1'b1;
    do begin
      @(posedge clk);
      #1;
    end while (!cpu_ready);
    cpu_valid <= 1'b0;
    cpu_wstrb <= 4'b0000;
    cpu_addr  <= 32'h0;
    cpu_wdata <= 32'h0;
  endtask

  task automatic bus_read(input [31:0] a, output [31:0] d);
    @(posedge clk);
    cpu_addr  <= a;
    cpu_wstrb <= 4'b0000;
    cpu_valid <= 1'b1;
    do begin
      @(posedge clk);
      #1;
    end while (!cpu_ready);
    d = cpu_rdata;
    cpu_valid <= 1'b0;
    cpu_addr  <= 32'h0;
  endtask

  task automatic check_val(input string tag, input [31:0] actual, input [31:0] expected);
    test_count++;
    if (actual !== expected) begin
      $display("[FAIL] %s: actual 0x%08h, expected 0x%08h", tag, actual, expected);
      error_count++;
    end else begin
      $display("[PASS] %s: 0x%08h", tag, actual);
    end
  endtask

  // --------------------------------------------------------------------------
  // Test Sequence
  // --------------------------------------------------------------------------
  logic [31:0] read_data;
  logic [31:0] t_initial, t_later;

  initial begin
    $display("=================================================================");
    $display("               STARTING SYSTEM BUS & PERIPHERAL TESTS            ");
    $display("=================================================================");

    clk       = 0;
    rst_n     = 0;
    cpu_addr  = 32'h0;
    cpu_wdata = 32'h0;
    cpu_wstrb = 4'b0;
    cpu_valid = 1'b0;

    // Apply Reset
    #45;
    rst_n = 1;
    @(posedge clk);
    #1;

    // ------------------------------------------------------------------------
    // 1. ROM Tests
    // ------------------------------------------------------------------------
    $display("\n--- 1. Boot ROM Tests ---");
    // Read word 0 (reset vector address)
    bus_read(ROM_BASE, read_data);
    check_val("ROM read at 0x0000_0000 (NOP instruction)", read_data, 32'h0000_0013);

    // Read word 1
    bus_read(ROM_BASE + 32'h4, read_data);
    check_val("ROM read at 0x0000_0004 (NOP instruction)", read_data, 32'h0000_0013);

    // Read last word in ROM (0x0000_3FFC)
    bus_read(ROM_END - 3, read_data);
    check_val("ROM read at 0x0000_3FFC (NOP instruction)", read_data, 32'h0000_0013);

    // Attempt illegal write to ROM
    bus_write(ROM_BASE, 32'hDEAD_BEEF, 4'b1111);
    bus_read(ROM_BASE, read_data);
    check_val("ROM write protection check (must still be 0x0000_0013)", read_data, 32'h0000_0013);

    // ------------------------------------------------------------------------
    // 2. RAM Tests (Byte enables & R/W)
    // ------------------------------------------------------------------------
    $display("\n--- 2. Main RAM Tests ---");
    // Full word write to RAM_BASE
    bus_write(RAM_BASE, 32'h1234_5678, 4'b1111);
    bus_read(RAM_BASE, read_data);
    check_val("RAM full word write/read at 0x1000_0000", read_data, 32'h1234_5678);

    // Byte write: Byte 0 (bits 7:0)
    bus_write(RAM_BASE, 32'h0000_00AA, 4'b0001);
    bus_read(RAM_BASE, read_data);
    check_val("RAM byte 0 write (0xAA) -> expect 0x1234_56AA", read_data, 32'h1234_56AA);

    // Byte write: Byte 1 (bits 15:8)
    bus_write(RAM_BASE, 32'h0000_BB00, 4'b0010);
    bus_read(RAM_BASE, read_data);
    check_val("RAM byte 1 write (0xBB) -> expect 0x1234_BBAA", read_data, 32'h1234_BBAA);

    // Byte write: Byte 2 (bits 23:16)
    bus_write(RAM_BASE, 32'h00CC_0000, 4'b0100);
    bus_read(RAM_BASE, read_data);
    check_val("RAM byte 2 write (0xCC) -> expect 0x12CC_BBAA", read_data, 32'h12CC_BBAA);

    // Byte write: Byte 3 (bits 31:24)
    bus_write(RAM_BASE, 32'hDD00_0000, 4'b1000);
    bus_read(RAM_BASE, read_data);
    check_val("RAM byte 3 write (0xDD) -> expect 0xDDCC_BBAA", read_data, 32'hDDCC_BBAA);

    // Halfword writes to address 0x1000_0004
    bus_write(RAM_BASE + 32'h4, 32'h0000_2211, 4'b0011); // Lower halfword
    bus_write(RAM_BASE + 32'h4, 32'h4433_0000, 4'b1100); // Upper halfword
    bus_read(RAM_BASE + 32'h4, read_data);
    check_val("RAM halfword writes at 0x1000_0004 -> expect 0x4433_2211", read_data, 32'h4433_2211);

    // RAM upper boundary test: 0x1000_FFFC
    bus_write(RAM_END - 3, 32'hCAFE_BABE, 4'b1111);
    bus_read(RAM_END - 3, read_data);
    check_val("RAM top boundary write/read at 0x1000_FFFC", read_data, 32'hCAFE_BABE);

    // ------------------------------------------------------------------------
    // 3. UART Peripheral Tests
    // ------------------------------------------------------------------------
    $display("\n--- 3. UART Peripheral Tests ---");
    // Read status register: bit 0 must be 1 (ready / idle)
    bus_read(UART_REG_STATUS, read_data);
    check_val("UART STATUS register initially idle (bit 0 == 1)", read_data[0], 1'b1);

    // Write ASCII character 'K' (0x4B) to TXDATA
    bus_write(UART_REG_TXDATA, 32'h0000_004B, 4'b0001);

    // Read STATUS register immediately: bit 0 must be 0 (busy transmitting)
    bus_read(UART_REG_STATUS, read_data);
    check_val("UART STATUS register during TX (bit 0 == 0)", read_data[0], 1'b0);

    // Wait for transmission to finish (10 baud cycles * 10 clk_div = 100 cycles)
    repeat (120) @(posedge clk);
    bus_read(UART_REG_STATUS, read_data);
    check_val("UART STATUS register after TX complete (bit 0 == 1)", read_data[0], 1'b1);

    // ------------------------------------------------------------------------
    // 4. System Timer Tests
    // ------------------------------------------------------------------------
    $display("\n--- 4. System Timer Tests ---");
    // Initial IRQ should be 0 (mtimecmp initialized to max)
    check_val("Timer IRQ initially deasserted (0)", timer_irq, 1'b0);

    // Read mtime lower word
    bus_read(TIMER_REG_MTIME_L, t_initial);
    $display("Timer initial mtime_l: %0d", t_initial);

    // Advance clock by 20 cycles
    repeat (20) @(posedge clk);

    bus_read(TIMER_REG_MTIME_L, t_later);
    $display("Timer later mtime_l: %0d", t_later);
    test_count++;
    if (t_later > t_initial) begin
      $display("[PASS] Timer mtime incremented properly (delta = %0d)", t_later - t_initial);
    end else begin
      $display("[FAIL] Timer mtime failed to increment (initial=%0d, later=%0d)", t_initial, t_later);
      error_count++;
    end

    // Program mtimecmp to trigger an interrupt
    // Set mtimecmp_h = 0
    bus_write(TIMER_REG_MTIMECMP_H, 32'h0000_0000, 4'b1111);
    // Read current mtime_l, set mtimecmp_l to current + 15
    bus_read(TIMER_REG_MTIME_L, read_data);
    bus_write(TIMER_REG_MTIMECMP_L, read_data + 32'd15, 4'b1111);

    // Verify IRQ is not yet asserted
    #1;
    check_val("Timer IRQ before threshold is reached", timer_irq, 1'b0);

    // Advance clock past the threshold
    repeat (25) @(posedge clk);
    #1;
    check_val("Timer IRQ asserted after mtime >= mtimecmp", timer_irq, 1'b1);

    // Clear interrupt by moving mtimecmp far into the future
    bus_write(TIMER_REG_MTIMECMP_H, 32'hFFFF_FFFF, 4'b1111);
    bus_write(TIMER_REG_MTIMECMP_L, 32'hFFFF_FFFF, 4'b1111);
    #1;
    check_val("Timer IRQ cleared after re-programming mtimecmp to max", timer_irq, 1'b0);

    // ------------------------------------------------------------------------
    // 5. Host Simulation Exit Trap (0x2000_00FC)
    // ------------------------------------------------------------------------
    $display("\n--- 5. Host Simulation Exit Trap Tests ---");
    bus_write(SIM_EXIT_ADDR, 32'h0000_0055, 4'b1111);
    check_val("Host trap exit code capture (0x0000_0055)", sim_exit_data, 32'h0000_0055);

    // ------------------------------------------------------------------------
    // 6. Unmapped Address Handling (Deadlock Prevention)
    // ------------------------------------------------------------------------
    $display("\n--- 6. Unmapped Address Handling ---");
    bus_read(32'h3000_0000, read_data);
    check_val("Unmapped address access returns poison word (0xDEAD_BEEF)", read_data, 32'hDEAD_BEEF);

    // ------------------------------------------------------------------------
    // Summary
    // ------------------------------------------------------------------------
    $display("\n=================================================================");
    $display("                        TEST SUMMARY                             ");
    $display("=================================================================");
    $display(" Total checks executed: %0d", test_count);
    $display(" Total errors encountered: %0d", error_count);

    if (error_count == 0) begin
      $display(" >>> ALL BUS & PERIPHERAL TESTS PASSED SUCCESSFULLY! <<<");
    end else begin
      $display(" >>> TESTBENCH FAILED WITH %0d ERRORS! <<<", error_count);
    end
    $display("=================================================================\n");

    @(posedge clk);
    $finish;
  end

endmodule : bus_tb
