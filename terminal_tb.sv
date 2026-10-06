`timescale 1ns / 1ps

module terminal_tb;

  localparam int CLK_FREQ_HZ = 1_843_200;
  localparam int BAUD_RATE   = 115_200;

  logic        clk;
  logic        rst_n;
  logic        uart_tx_out;
  logic        sim_exit_valid;
  logic [31:0] sim_exit_data;

  logic        uart_rx_valid_in;
  logic [7:0]  uart_rx_data_in;
  logic        uart_rx_ready_out;

  string rom_override = "sw/terminal_echo.hex";
  string ram_override = "sw/terminal_echo_ram.hex";

  top_soc #(
    .CLK_FREQ           (CLK_FREQ_HZ),
    .BAUD_RATE          (BAUD_RATE),
    .SIM_CONSOLE_OUTPUT (0)
  ) u_dut (
    .clk                (clk),
    .rst_n              (rst_n),
    .uart_tx_out        (uart_tx_out),
    .sim_exit_valid     (sim_exit_valid),
    .sim_exit_data      (sim_exit_data),
    .uart_rx_valid_in   (uart_rx_valid_in),
    .uart_rx_data_in    (uart_rx_data_in),
    .uart_rx_ready_out  (uart_rx_ready_out)
  );

  // Clock generation (100ns period)
  initial begin
    clk = 1'b0;
    forever #50 clk = ~clk;
  end

  // Initialization and client connection gating
  int is_connected = 0;
  initial begin
    uart_rx_valid_in = 1'b0;
    uart_rx_data_in  = 8'h00;
    rst_n            = 1'b0;

    $term_init();

    if ($value$plusargs("ROM_HEX=%s", rom_override)) begin
      $readmemh(rom_override, u_dut.u_rom.mem);
    end else begin
      $readmemh("sw/terminal_echo.hex", u_dut.u_rom.mem);
    end

    if ($value$plusargs("RAM_HEX=%s", ram_override)) begin
      $readmemh(ram_override, u_dut.u_ram.mem);
    end else begin
      $readmemh("sw/terminal_echo_ram.hex", u_dut.u_ram.mem);
    end

    // Hold CPU in reset until terminal client connects
    while (is_connected == 0) begin
      #500_000; // 500 us poll
      $term_wait_client(is_connected);
    end

    repeat (10) @(posedge clk);
    #1;
    rst_n = 1'b1;
  end

  // Monitor CPU exit trap
  always @(posedge clk) begin
    if (rst_n && sim_exit_valid) begin
      $display("\n[SIM_EXIT] CPU issued exit trap code: %0d", sim_exit_data);
      $finish(0);
    end
  end

  // Hardware UART sniffer: captures bytes transmitted by CPU and sends to VPI terminal
  localparam int CLK_DIV = CLK_FREQ_HZ / BAUD_RATE;
  localparam real BIT_TIME_NS = real'(CLK_DIV) * 100.0;
  logic [7:0] tx_byte;

  initial begin
    tx_byte = 8'h00;
    forever begin
      @(negedge uart_tx_out);
      if (!rst_n) continue;

      #(BIT_TIME_NS / 2.0);
      if (uart_tx_out == 1'b0) begin
        for (int i = 0; i < 8; i++) begin
          #(BIT_TIME_NS);
          tx_byte[i] = uart_tx_out;
        end
        #(BIT_TIME_NS);
        if (uart_tx_out == 1'b1) begin
          $term_tx(tx_byte);
        end
      end
    end
  end

  // Periodic poll from VPI terminal: feeds received bytes into CPU UART
  int rx_val_i;
  int rx_valid_i;
  int poll_cnt = 0;

  always @(posedge clk) begin
    if (rst_n) begin
      if (uart_rx_ready_out) begin
        if (poll_cnt >= 100) begin
          poll_cnt <= 0;
          $term_poll_rx(rx_val_i, rx_valid_i);
          if (rx_valid_i != 0) begin
            uart_rx_data_in  <= rx_val_i[7:0];
            uart_rx_valid_in <= 1'b1;
          end else begin
            uart_rx_valid_in <= 1'b0;
          end
        end else begin
          poll_cnt <= poll_cnt + 1;
          uart_rx_valid_in <= 1'b0;
        end
      end else begin
        uart_rx_valid_in <= 1'b0;
      end
    end
  end

endmodule
