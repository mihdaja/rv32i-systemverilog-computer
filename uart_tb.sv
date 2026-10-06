// ============================================================================
// File: uart_tb.sv
// Description: Unit testbench for uart_tx serial transmitter module.
//              Verifies:
//                1. Initial line idle state and status register flags.
//                2. Serial framing (1 Start bit '0', 8 Data bits LSB-first, 1 Stop bit '1').
//                3. Precise bit timing (each bit held for CLK_DIV cycles).
//                4. Status flag transitions (ready -> busy -> ready).
//                5. Transmission of multiple patterns (0xA5, 0x3C, 0xFF, 0x00).
// ============================================================================

`timescale 1ns / 1ps

`include "rv32i_pkg.sv"

module uart_tb;
  import rv32i_pkg::*;

  // Parameters for fast simulation
  localparam int CLK_PERIOD = 20; // 50 MHz
  localparam int CLK_DIV    = 10; // 10 clock cycles per baud bit

  // Signals
  logic        clk;
  logic        rst_n;
  logic [31:0] addr;
  logic [31:0] wdata;
  logic [3:0]  wstrb;
  logic        valid;
  logic [31:0] rdata;
  logic        ready;
  logic        tx;

  // Verification statistics
  int error_count = 0;
  int test_count  = 0;

  // Clock generation
  always #(CLK_PERIOD / 2) clk = ~clk;

  // Device Under Test
  uart_tx #(
    .CLK_FREQ           (50_000_000),
    .BAUD_RATE          (5_000_000),
    .CLK_DIV            (CLK_DIV),
    .SIM_CONSOLE_OUTPUT (0)
  ) dut (
    .clk   (clk),
    .rst_n (rst_n),
    .addr  (addr),
    .wdata (wdata),
    .wstrb (wstrb),
    .valid (valid),
    .rdata (rdata),
    .ready (ready),
    .tx    (tx)
  );

  // Helper task: Write byte to UART TX register
  task automatic uart_write_byte(input [7:0] byte_data);
    @(posedge clk);
    addr  <= UART_REG_TXDATA;
    wdata <= {24'd0, byte_data};
    wstrb <= 4'b0001;
    valid <= 1'b1;
    do begin
      @(posedge clk);
      #1;
    end while (!ready);
    valid <= 1'b0;
    wstrb <= 4'b0000;
    addr  <= 32'd0;
    wdata <= 32'd0;
  endtask

  // Helper task: Read status register
  task automatic uart_read_status(output logic status_ready);
    @(posedge clk);
    addr  <= UART_REG_STATUS;
    wstrb <= 4'b0000;
    valid <= 1'b1;
    do begin
      @(posedge clk);
      #1;
    end while (!ready);
    status_ready = rdata[0];
    valid <= 1'b0;
    addr  <= 32'd0;
  endtask

  // Helper task: Verify serial frame transmission bit by bit
  task automatic verify_uart_frame(input [7:0] expected_byte);
    logic [7:0] captured_data;
    logic        bit_val;

    // 1. Wait for Start bit (falling edge on TX line)
    if (tx !== 1'b0) begin
      @(negedge tx);
    end
    #1;
    test_count++;
    if (tx !== 1'b0) begin
      $display("[FAIL] Expected Start bit '0', got %b", tx);
      error_count++;
    end else begin
      $display("[PASS] Detected Start bit '0'");
    end

    // Wait until center of Start bit to verify stable '0'
    repeat (CLK_DIV / 2) @(posedge clk);
    #1;
    test_count++;
    if (tx !== 1'b0) begin
      $display("[FAIL] Start bit center unstable, got %b", tx);
      error_count++;
    end else begin
      $display("[PASS] Start bit center stable at '0'");
    end

    // Advance to center of each of the 8 Data bits (LSB to MSB)
    for (int i = 0; i < 8; i++) begin
      repeat (CLK_DIV) @(posedge clk);
      #1;
      bit_val = tx;
      captured_data[i] = bit_val;
      test_count++;
      if (bit_val !== expected_byte[i]) begin
        $display("[FAIL] Data bit [%0d]: actual %b, expected %b", i, bit_val, expected_byte[i]);
        error_count++;
      end else begin
        $display("[PASS] Data bit [%0d]: %b (matches expected)", i, bit_val);
      end
    end

    // Advance to center of Stop bit
    repeat (CLK_DIV) @(posedge clk);
    #1;
    test_count++;
    if (tx !== 1'b1) begin
      $display("[FAIL] Expected Stop bit '1', got %b", tx);
      error_count++;
    end else begin
      $display("[PASS] Detected Stop bit '1'");
    end

    // Check full byte reconstruction
    test_count++;
    if (captured_data !== expected_byte) begin
      $display("[FAIL] Full frame mismatch: captured 0x%02h, expected 0x%02h", captured_data, expected_byte);
      error_count++;
    end else begin
      $display("[PASS] Full frame verified successfully: 0x%02h ('%c')", captured_data, (captured_data >= 32 && captured_data <= 126) ? captured_data : 8'h2E);
    end

    // Complete the remaining half of the Stop bit
    repeat (CLK_DIV / 2 + 1) @(posedge clk);
  endtask

  // Test sequence
  logic st;

  initial begin
    $display("=================================================================");
    $display("               STARTING UART TRANSMITTER UNIT TESTS              ");
    $display("=================================================================");

    clk   = 0;
    rst_n = 0;
    addr  = 32'd0;
    wdata = 32'd0;
    wstrb = 4'b0;
    valid = 1'b0;

    // Reset sequence
    #45;
    rst_n = 1;
    @(posedge clk);
    #1;

    // Check reset idle state
    test_count++;
    if (tx !== 1'b1) begin
      $display("[FAIL] TX line not HIGH on reset idle: %b", tx);
      error_count++;
    end else begin
      $display("[PASS] TX line initially HIGH (idle)");
    end

    uart_read_status(st);
    test_count++;
    if (st !== 1'b1) begin
      $display("[FAIL] Status register bit 0 not 1 (ready) on reset: %b", st);
      error_count++;
    end else begin
      $display("[PASS] Status register bit 0 is 1 (TX ready)");
    end

    // ------------------------------------------------------------------------
    // Test Case 1: Byte 0xA5 (1010_0101) - Alternating bit pattern
    // ------------------------------------------------------------------------
    $display("\n--- Test Case 1: Transmit 0xA5 (binary 1010_0101) ---");
    fork
      begin
        uart_write_byte(8'hA5);
        // Verify status bit transitions to busy
        uart_read_status(st);
        test_count++;
        if (st !== 1'b0) begin
          $display("[FAIL] Status register did not go busy during TX: %b", st);
          error_count++;
        end else begin
          $display("[PASS] Status register bit 0 is 0 (TX busy)");
        end
      end
      begin
        verify_uart_frame(8'hA5);
      end
    join

    // After frame finishes, check status register returns to ready
    @(posedge clk);
    uart_read_status(st);
    test_count++;
    if (st !== 1'b1) begin
      $display("[FAIL] Status register did not return to ready after TX: %b", st);
      error_count++;
    end else begin
      $display("[PASS] Status register bit 0 returned to 1 (TX ready)");
    end

    // ------------------------------------------------------------------------
    // Test Case 2: Byte 0x3C (0011_1100)
    // ------------------------------------------------------------------------
    $display("\n--- Test Case 2: Transmit 0x3C (binary 0011_1100) ---");
    fork
      begin
        uart_write_byte(8'h3C);
      end
      begin
        verify_uart_frame(8'h3C);
      end
    join

    // ------------------------------------------------------------------------
    // Test Case 3: Byte 0xFF (1111_1111) - All ones data
    // ------------------------------------------------------------------------
    $display("\n--- Test Case 3: Transmit 0xFF (binary 1111_1111) ---");
    fork
      begin
        uart_write_byte(8'hFF);
      end
      begin
        verify_uart_frame(8'hFF);
      end
    join

    // ------------------------------------------------------------------------
    // Test Case 4: Byte 0x00 (0000_0000) - All zeros data
    // ------------------------------------------------------------------------
    $display("\n--- Test Case 4: Transmit 0x00 (binary 0000_0000) ---");
    fork
      begin
        uart_write_byte(8'h00);
      end
      begin
        verify_uart_frame(8'h00);
      end
    join

    // ------------------------------------------------------------------------
    // Summary
    // ------------------------------------------------------------------------
    $display("\n=================================================================");
    $display("                        TEST SUMMARY                             ");
    $display("=================================================================");
    $display(" Total checks executed: %0d", test_count);
    $display(" Total errors encountered: %0d", error_count);

    if (error_count == 0) begin
      $display(" >>> ALL UART TRANSMITTER TESTS PASSED SUCCESSFULLY! <<<");
    end else begin
      $display(" >>> TESTBENCH FAILED WITH %0d ERRORS! <<<", error_count);
    end
    $display("=================================================================\n");

    repeat (10) @(posedge clk);
    $finish;
  end

endmodule : uart_tb
