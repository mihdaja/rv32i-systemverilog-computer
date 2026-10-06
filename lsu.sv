// ============================================================================
// File: lsu.sv
// Description: Load/Store Unit (LSU) for RV32I processor.
//              Handles byte and halfword alignment, sign/zero extension for
//              loads, and byte strobe generation with data shifting for stores.
// ============================================================================

`ifndef LSU_SV
`define LSU_SV

`timescale 1ns / 1ps

import rv32i_pkg::*;

module lsu (
  input  mem_op_e    mem_op,
  input  logic [31:0] addr,
  input  logic [31:0] reg_wdata,
  input  logic [31:0] bus_rdata,
  output logic [31:0] reg_rdata,
  output logic [31:0] bus_wdata,
  output logic [3:0]  bus_wstrb
);

  logic [1:0] byte_offset;
  assign byte_offset = addr[1:0];

  // --------------------------------------------------------------------------
  // Read Data Formatting (Load Operations)
  // --------------------------------------------------------------------------
  always @* begin
    case (mem_op)
      MEM_OP_LB: begin
        case (byte_offset)
          2'b00:   reg_rdata = {{24{bus_rdata[7]}},  bus_rdata[7:0]};
          2'b01:   reg_rdata = {{24{bus_rdata[15]}}, bus_rdata[15:8]};
          2'b10:   reg_rdata = {{24{bus_rdata[23]}}, bus_rdata[23:16]};
          2'b11:   reg_rdata = {{24{bus_rdata[31]}}, bus_rdata[31:24]};
          default: reg_rdata = 32'h0000_0000;
        endcase
      end

      MEM_OP_LBU: begin
        case (byte_offset)
          2'b00:   reg_rdata = {24'b0, bus_rdata[7:0]};
          2'b01:   reg_rdata = {24'b0, bus_rdata[15:8]};
          2'b10:   reg_rdata = {24'b0, bus_rdata[23:16]};
          2'b11:   reg_rdata = {24'b0, bus_rdata[31:24]};
          default: reg_rdata = 32'h0000_0000;
        endcase
      end

      MEM_OP_LH: begin
        case (byte_offset[1])
          1'b0:    reg_rdata = {{16{bus_rdata[15]}}, bus_rdata[15:0]};
          1'b1:    reg_rdata = {{16{bus_rdata[31]}}, bus_rdata[31:16]};
          default: reg_rdata = 32'h0000_0000;
        endcase
      end

      MEM_OP_LHU: begin
        case (byte_offset[1])
          1'b0:    reg_rdata = {16'b0, bus_rdata[15:0]};
          1'b1:    reg_rdata = {16'b0, bus_rdata[31:16]};
          default: reg_rdata = 32'h0000_0000;
        endcase
      end

      MEM_OP_LW: begin
        reg_rdata = bus_rdata;
      end

      default: begin
        reg_rdata = 32'h0000_0000;
      end
    endcase
  end

  // --------------------------------------------------------------------------
  // Write Strobe and Write Data Formatting (Store Operations)
  // --------------------------------------------------------------------------
  always @* begin
    case (mem_op)
      MEM_OP_SB: begin
        case (byte_offset)
          2'b00: begin
            bus_wstrb = 4'b0001;
            bus_wdata = {24'b0, reg_wdata[7:0]};
          end
          2'b01: begin
            bus_wstrb = 4'b0010;
            bus_wdata = {16'b0, reg_wdata[7:0], 8'b0};
          end
          2'b10: begin
            bus_wstrb = 4'b0100;
            bus_wdata = {8'b0, reg_wdata[7:0], 16'b0};
          end
          2'b11: begin
            bus_wstrb = 4'b1000;
            bus_wdata = {reg_wdata[7:0], 24'b0};
          end
          default: begin
            bus_wstrb = 4'b0000;
            bus_wdata = 32'h0000_0000;
          end
        endcase
      end

      MEM_OP_SH: begin
        case (byte_offset[1])
          1'b0: begin
            bus_wstrb = 4'b0011;
            bus_wdata = {16'b0, reg_wdata[15:0]};
          end
          1'b1: begin
            bus_wstrb = 4'b1100;
            bus_wdata = {reg_wdata[15:0], 16'b0};
          end
          default: begin
            bus_wstrb = 4'b0000;
            bus_wdata = 32'h0000_0000;
          end
        endcase
      end

      MEM_OP_SW: begin
        bus_wstrb = 4'b1111;
        bus_wdata = reg_wdata;
      end

      default: begin
        bus_wstrb = 4'b0000;
        bus_wdata = 32'h0000_0000;
      end
    endcase
  end

endmodule : lsu

`endif // LSU_SV
