// ============================================================================
// File: uart_tx.sv
// Description: Memory-mapped UART transmitter (8N1) for RV32I SoC.
//              Registers:
//                - 0x2000_0000: Write byte to TX shift register.
//                - 0x2000_0004: Status register (bit 0: 1 = ready/idle, 0 = busy).
//                - 0x2000_0008: Read RX data (reserved, returns 0).
//              Configurable baud rate clock divider.
//              Optionally outputs characters to simulation console.
// ============================================================================

`timescale 1ns / 1ps

`ifndef UART_TX_SV
`define UART_TX_SV

`include "rv32i_pkg.sv"

`ifdef USE_BUS_IF
module uart_tx
  import rv32i_pkg::*;
#(
  parameter int CLK_FREQ           = 50_000_000,
  parameter int BAUD_RATE          = 115200,
  parameter int CLK_DIV            = CLK_FREQ / BAUD_RATE,
  parameter bit SIM_CONSOLE_OUTPUT = 1
)(
  bus_if.slave  bus,
  output logic  tx
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
module uart_tx
  import rv32i_pkg::*;
#(
  parameter int CLK_FREQ           = 50_000_000,
  parameter int BAUD_RATE          = 115200,
  parameter int CLK_DIV            = CLK_FREQ / BAUD_RATE,
  parameter bit SIM_CONSOLE_OUTPUT = 1
)(
  input  logic        clk,
  input  logic        rst_n,
  input  logic [31:0] addr,
  input  logic [31:0] wdata,
  input  logic [3:0]  wstrb,
  input  logic        valid,
  output logic [31:0] rdata,
  output logic        ready,
  output logic        tx,
  input  logic        rx_valid_in = 1'b0,
  input  logic [7:0]  rx_data_in  = 8'h00,
  output logic        rx_ready_out
);
`endif

  // UART transmitter state definition
  typedef enum logic [1:0] {
    STATE_IDLE  = 2'b00,
    STATE_START = 2'b01,
    STATE_DATA  = 2'b10,
    STATE_STOP  = 2'b11
  } uart_state_t;

  uart_state_t state;
  logic [31:0] baud_cnt;
  logic [2:0]  bit_idx;
  logic [7:0]  tx_shift;
  logic        tx_busy;
  logic        tx_reg;
  logic [7:0]  rx_buffer;
  logic        rx_valid_reg;

  assign rx_ready_out = !rx_valid_reg;

  assign tx = tx_reg;
  wire tx_ready = !tx_busy;

  // Address offset decode
  wire [1:0] reg_sel = addr[3:2];

  // UART Transmitter FSM & Baud Rate Generator
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state    <= STATE_IDLE;
      baud_cnt <= 32'd0;
      bit_idx  <= 3'd0;
      tx_shift <= 8'd0;
      tx_busy  <= 1'b0;
      tx_reg   <= 1'b1; // Idle line is HIGH
    end else begin
      case (state)
        STATE_IDLE: begin
          tx_reg  <= 1'b1;
          bit_idx <= 3'd0;
          if (valid && (reg_sel == 2'b00) && wstrb[0] && !tx_busy) begin
            tx_shift <= wdata[7:0];
            tx_busy  <= 1'b1;
            baud_cnt <= 32'd0;
            state    <= STATE_START;
            tx_reg   <= 1'b0; // Start bit is LOW
`ifndef SYNTHESIS
            if (SIM_CONSOLE_OUTPUT) begin
              $write("%c", wdata[7:0]);
              $fflush();
            end
`endif
          end else begin
            tx_busy <= 1'b0;
          end
        end

        STATE_START: begin
          tx_reg <= 1'b0; // Start bit
          if (baud_cnt >= CLK_DIV - 1) begin
            baud_cnt <= 32'd0;
            state    <= STATE_DATA;
            bit_idx  <= 3'd0;
            tx_reg   <= tx_shift[0]; // First data bit (LSB)
          end else begin
            baud_cnt <= baud_cnt + 1'b1;
          end
        end

        STATE_DATA: begin
          tx_reg <= tx_shift[bit_idx];
          if (baud_cnt >= CLK_DIV - 1) begin
            baud_cnt <= 32'd0;
            if (bit_idx == 3'd7) begin
              state   <= STATE_STOP;
              tx_reg  <= 1'b1; // Stop bit is HIGH
            end else begin
              bit_idx <= bit_idx + 1'b1;
              tx_reg  <= tx_shift[bit_idx + 1'b1];
            end
          end else begin
            baud_cnt <= baud_cnt + 1'b1;
          end
        end

        STATE_STOP: begin
          tx_reg <= 1'b1; // Stop bit
          if (baud_cnt >= CLK_DIV - 1) begin
            baud_cnt <= 32'd0;
            state    <= STATE_IDLE;
            tx_busy  <= 1'b0;
          end else begin
            baud_cnt <= baud_cnt + 1'b1;
          end
        end

        default: begin
          state    <= STATE_IDLE;
          tx_busy  <= 1'b0;
          tx_reg   <= 1'b1;
          baud_cnt <= 32'd0;
        end
      endcase
    end
  end

  // Synchronous Bus Read Response
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      ready        <= 1'b0;
      rdata        <= 32'd0;
      rx_buffer    <= 8'd0;
      rx_valid_reg <= 1'b0;
    end else begin
      ready <= valid;
      if (valid) begin
        case (reg_sel)
          2'b00: begin
            rdata <= {24'd0, rx_buffer};
            if (wstrb == 4'b0000) begin
              rx_valid_reg <= 1'b0;
            end
          end
          2'b01: begin
            rdata <= {30'd0, rx_valid_reg, tx_ready};
          end
          2'b10: begin
            rdata <= {24'd0, rx_buffer};
            rx_valid_reg <= 1'b0;
          end
          default: rdata <= 32'd0;
        endcase
      end else begin
        rdata <= 32'd0;
      end

      if (rx_valid_in && (!rx_valid_reg || (valid && (reg_sel == 2'b00 || reg_sel == 2'b10)))) begin
        rx_buffer    <= rx_data_in;
        rx_valid_reg <= 1'b1;
      end
    end
  end

endmodule : uart_tx

`endif // UART_TX_SV
