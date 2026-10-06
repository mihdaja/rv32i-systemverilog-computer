// ============================================================================
// File: uart_rx.sv
// Description: Hardware UART 8N1 Serial Receiver with metastability synchronizer,
//              mid-bit majority/center sampling, and FIFO/handshake interface.
// ============================================================================

`timescale 1ns / 1ps

module uart_rx #(
  parameter int CLK_FREQ  = 50_000_000,
  parameter int BAUD_RATE = 115_200
)(
  input  logic       clk,
  input  logic       rst_n,
  input  logic       rx_pin,         // Physical FPGA serial input pin
  output logic [7:0] rx_data,        // Received byte
  output logic       rx_valid,       // 1-cycle strobe or latched valid
  input  logic       rx_ready,       // Consumer ready handshake
  output logic       rx_busy         // High while actively receiving frame
);

  localparam int CLK_DIV = CLK_FREQ / BAUD_RATE; // e.g. 50,000,000 / 115,200 = 434
  localparam int HALF_DIV = CLK_DIV / 2;

  // --------------------------------------------------------------------------
  // 2-stage input synchronizer to prevent metastability
  // --------------------------------------------------------------------------
  logic rx_sync1, rx_sync;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      rx_sync1 <= 1'b1;
      rx_sync  <= 1'b1;
    end else begin
      rx_sync1 <= rx_pin;
      rx_sync  <= rx_sync1;
    end
  end

  // --------------------------------------------------------------------------
  // Receiver FSM
  // --------------------------------------------------------------------------
  typedef enum logic [1:0] {
    STATE_IDLE  = 2'b00,
    STATE_START = 2'b01,
    STATE_DATA  = 2'b10,
    STATE_STOP  = 2'b11
  } rx_state_t;

  rx_state_t  state;
  logic [31:0] baud_cnt;
  logic [2:0]  bit_idx;
  logic [7:0]  shift_reg;
  logic [7:0]  data_out_reg;
  logic        valid_reg;

  assign rx_data  = data_out_reg;
  assign rx_valid = valid_reg;
  assign rx_busy  = (state != STATE_IDLE);

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state        <= STATE_IDLE;
      baud_cnt     <= 32'd0;
      bit_idx      <= 3'd0;
      shift_reg    <= 8'd0;
      data_out_reg <= 8'd0;
      valid_reg    <= 1'b0;
    end else begin
      // Handshake acknowledge: clear valid when consumer reads
      if (valid_reg && rx_ready) begin
        valid_reg <= 1'b0;
      end

      case (state)
        STATE_IDLE: begin
          baud_cnt <= 32'd0;
          bit_idx  <= 3'd0;
          // Falling edge: start bit detected (line goes LOW)
          if (!rx_sync) begin
            state <= STATE_START;
          end
        end

        STATE_START: begin
          // Sample in the middle of start bit to confirm it is valid
          if (baud_cnt >= HALF_DIV - 1) begin
            baud_cnt <= 32'd0;
            if (!rx_sync) begin
              state <= STATE_DATA; // Valid start bit
            end else begin
              state <= STATE_IDLE; // False glitch, reject
            end
          end else begin
            baud_cnt <= baud_cnt + 1'b1;
          end
        end

        STATE_DATA: begin
          if (baud_cnt >= CLK_DIV - 1) begin
            baud_cnt           <= 32'd0;
            shift_reg[bit_idx] <= rx_sync;
            if (bit_idx == 3'd7) begin
              state <= STATE_STOP;
            end else begin
              bit_idx <= bit_idx + 1'b1;
            end
          end else begin
            baud_cnt <= baud_cnt + 1'b1;
          end
        end

        STATE_STOP: begin
          // Stop bit sampling (expected HIGH)
          if (baud_cnt >= CLK_DIV - 1) begin
            baud_cnt <= 32'd0;
            state    <= STATE_IDLE;
            if (rx_sync) begin
              data_out_reg <= shift_reg;
              valid_reg    <= 1'b1; // New character ready
            end
          end else begin
            baud_cnt <= baud_cnt + 1'b1;
          end
        end

        default: begin
          state <= STATE_IDLE;
        end
      endcase
    end
  end

endmodule : uart_rx
