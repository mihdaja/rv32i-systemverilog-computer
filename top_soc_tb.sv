// ============================================================================
// File: top_soc_tb.sv
// Description: Compliance & System Testbench for RV32I Computer SoC (top_soc).
//              Features:
//              - 50 MHz Clock generation (20ns period)
//              - Active-low reset sequencing
//              - Dynamic ROM & RAM preloading via plusargs (+ROM_HEX=, +RAM_HEX=)
//              - Simulation exit trap monitor (0x2000_00FC write interception)
//              - Hardware UART serial sniffer decoding 8N1 bitstream at 115200 baud
//              - Configurable watchdog cycle timeout
// ============================================================================

`timescale 1ns / 1ps

module top_soc_tb;

  // --------------------------------------------------------------------------
  // Simulation Timing & Parameters
  // --------------------------------------------------------------------------
  localparam int CLK_FREQ_HZ = 50_000_000;
  localparam int BAUD_RATE   = 115_200;
  localparam int ROM_SIZE    = 16384;
  localparam int RAM_SIZE    = 16384;

  // Default timeout in clock cycles (can be overridden with +TIMEOUT=<int>)
  int unsigned max_cycles = 500_000;
  int unsigned cycle_count = 0;

  // Plusarg string buffers
  string rom_override = "";
  string ram_override = "";

  // --------------------------------------------------------------------------
  // DUT Signals
  // --------------------------------------------------------------------------
  logic        clk;
  logic        rst_n;
  logic        uart_tx_out;
  logic        sim_exit_valid;
  logic [31:0] sim_exit_data;

  // --------------------------------------------------------------------------
  // DUT Instantiation
  // --------------------------------------------------------------------------
  top_soc #(
    .ROM_HEX            (""),
    .RAM_HEX            (""),
    .CLK_FREQ           (CLK_FREQ_HZ),
    .BAUD_RATE          (BAUD_RATE),
    .SIM_CONSOLE_OUTPUT (0)
  ) u_dut (
    .clk            (clk),
    .rst_n          (rst_n),
    .uart_tx_out    (uart_tx_out),
    .sim_exit_valid (sim_exit_valid),
    .sim_exit_data  (sim_exit_data)
  );

  // --------------------------------------------------------------------------
  // 50 MHz Clock Generation (20ns period, 10ns high / 10ns low)
  // --------------------------------------------------------------------------
  initial begin
    clk = 1'b0;
    forever #10 clk = ~clk;
  end

  // --------------------------------------------------------------------------
  // Reset Generation & Hex Preload Sequencing
  // --------------------------------------------------------------------------
  initial begin
    rst_n = 1'b0;

    // Check plusarg for custom timeout limit
    if ($value$plusargs("TIMEOUT=%d", max_cycles)) begin
      $display("[TB] Watchdog timeout configured to %0d cycles via plusarg", max_cycles);
    end

    // Dynamic ROM preload via plusarg
    if ($value$plusargs("ROM_HEX=%s", rom_override)) begin
      $display("[TB] Loading Boot ROM image from plusarg: %s", rom_override);
      $readmemh(rom_override, u_dut.u_rom.mem);
    end

    // Dynamic RAM preload via plusarg
    if ($value$plusargs("RAM_HEX=%s", ram_override)) begin
      $display("[TB] Loading Main SRAM image from plusarg: %s", ram_override);
      $readmemh(ram_override, u_dut.u_ram.mem);
    end

    // Hold reset low for 10 full clock cycles
    repeat (10) @(posedge clk);
    #1;
    rst_n = 1'b1;
    $display("[TB] Reset released at time %0t ps. SoC executing...", $time);
  end

  // --------------------------------------------------------------------------
  // Simulation Exit & Trap Monitor
  // --------------------------------------------------------------------------
  always @(posedge clk) begin
    if (rst_n && sim_exit_valid) begin
      $display("\n[SIM_EXIT] Trap code: 0x%08h (%0d)", sim_exit_data, sim_exit_data);
      if (sim_exit_data == 32'd1) begin
        $display(">>> TEST PASSED <<<\n");
        $finish(0);
      end else begin
        $display(">>> TEST FAILED with error code %0d <<<\n", sim_exit_data);
        $finish(0);
      end
    end
  end

  // --------------------------------------------------------------------------
  // Watchdog Cycle Counter
  // --------------------------------------------------------------------------
  always @(posedge clk) begin
    if (rst_n) begin
      cycle_count <= cycle_count + 1;
      if (cycle_count >= max_cycles) begin
        $display("\n>>> SIMULATION TIMEOUT <<<");
        $display("Watchdog timeout expired: reached %0d cycles without sim_exit_valid", max_cycles);
        $fatal(1, "Simulation watchdog expired!");
      end
    end
  end

  // --------------------------------------------------------------------------
  // Hardware UART Serial Sniffer / Monitor (8N1)
  // Samples uart_tx_out serial line at baud bit intervals
  // --------------------------------------------------------------------------
  localparam int CLK_DIV = CLK_FREQ_HZ / BAUD_RATE;
  localparam real BIT_TIME_NS = real'(CLK_DIV) * 20.0;

  logic [7:0] rx_byte;

  initial begin
    rx_byte = 8'h00;
    forever begin
      // Wait for Start bit falling edge
      @(negedge uart_tx_out);
      if (!rst_n) continue;

      // Sample at mid-point of start bit
      #(BIT_TIME_NS / 2.0);
      if (uart_tx_out == 1'b0) begin
        // Sample 8 data bits (LSB first)
        for (int i = 0; i < 8; i++) begin
          #(BIT_TIME_NS);
          rx_byte[i] = uart_tx_out;
        end

        // Wait for Stop bit
        #(BIT_TIME_NS);
        if (uart_tx_out == 1'b1) begin
          $write("%c", rx_byte);
          $fflush();
        end
      end
    end
  end

endmodule
