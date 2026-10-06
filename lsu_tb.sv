// ============================================================================
// File: lsu_tb.sv
// Description: Unit testbench for Load/Store Unit (LSU):
//              - LB, LBU, LH, LHU, LW read data alignment & sign/zero extension
//              - SB, SH, SW write strobe masking and data lane shifting
// ============================================================================

`timescale 1ns / 1ps

import rv32i_pkg::*;

module lsu_tb;

  int unsigned error_count = 0;
  int unsigned test_count  = 0;

  // DUT signals
  mem_op_e    mem_op;
  logic [31:0] addr;
  logic [31:0] reg_wdata;
  logic [31:0] bus_rdata;
  logic [31:0] reg_rdata;
  logic [31:0] bus_wdata;
  logic [3:0]  bus_wstrb;

  // DUT instantiation
  lsu u_lsu (
    .mem_op    (mem_op),
    .addr      (addr),
    .reg_wdata (reg_wdata),
    .bus_rdata (bus_rdata),
    .reg_rdata (reg_rdata),
    .bus_wdata (bus_wdata),
    .bus_wstrb (bus_wstrb)
  );

  // --------------------------------------------------------------------------
  // Check Tasks
  // --------------------------------------------------------------------------
  task automatic check_load(
    input string       name,
    input mem_op_e     op,
    input logic [31:0] test_addr,
    input logic [31:0] test_bus_rdata,
    input logic [31:0] exp_reg_rdata
  );
    test_count++;
    mem_op    = op;
    addr      = test_addr;
    bus_rdata = test_bus_rdata;
    reg_wdata = 32'h0;
    #1;

    if (reg_rdata !== exp_reg_rdata || bus_wstrb !== 4'b0000) begin
      $display("[FAIL] %s: addr=0x%08h bus_rdata=0x%08h | Expected reg_rdata=0x%08h wstrb=0000, Got reg_rdata=0x%08h wstrb=%b",
               name, test_addr, test_bus_rdata, exp_reg_rdata, reg_rdata, bus_wstrb);
      error_count++;
    end else begin
      $display("[PASS] %s (reg_rdata=0x%08h)", name, reg_rdata);
    end
  endtask

  task automatic check_store(
    input string       name,
    input mem_op_e     op,
    input logic [31:0] test_addr,
    input logic [31:0] test_reg_wdata,
    input logic [31:0] exp_bus_wdata,
    input logic [3:0]  exp_bus_wstrb
  );
    test_count++;
    mem_op    = op;
    addr      = test_addr;
    reg_wdata = test_reg_wdata;
    bus_rdata = 32'h0;
    #1;

    if (bus_wdata !== exp_bus_wdata || bus_wstrb !== exp_bus_wstrb) begin
      $display("[FAIL] %s: addr=0x%08h reg_wdata=0x%08h | Expected bus_wdata=0x%08h wstrb=%b, Got bus_wdata=0x%08h wstrb=%b",
               name, test_addr, test_reg_wdata, exp_bus_wdata, exp_bus_wstrb, bus_wdata, bus_wstrb);
      error_count++;
    end else begin
      $display("[PASS] %s (bus_wdata=0x%08h, wstrb=%b)", name, bus_wdata, bus_wstrb);
    end
  endtask

  // --------------------------------------------------------------------------
  // Test Execution
  // --------------------------------------------------------------------------
  initial begin
    $display("===============================================================");
    $display("Starting Load/Store Unit Testbench (lsu_tb)");
    $display("===============================================================");

    // ------------------------------------------------------------------------
    // Part 1: Load Operations (Sign extension, Zero extension, Alignment)
    // ------------------------------------------------------------------------
    $display("\n--- Testing Load Instructions (LB, LBU, LH, LHU, LW) ---");

    // Raw test word: Byte 3 = 0x81 (neg), Byte 2 = 0x7E (pos), Byte 1 = 0xF0 (neg), Byte 0 = 0x0F (pos)
    // bus_rdata = 32'h817E_F00F

    // LB: Byte 0 (positive: 0x0F -> 0x0000_000F)
    check_load("LB Byte 0 (pos)", MEM_OP_LB, 32'h1000_0000, 32'h817E_F00F, 32'h0000_000F);

    // LB: Byte 1 (negative: 0xF0 -> 0xFFFF_FFF0)
    check_load("LB Byte 1 (neg)", MEM_OP_LB, 32'h1000_0001, 32'h817E_F00F, 32'hFFFF_FFF0);

    // LB: Byte 2 (positive: 0x7E -> 0x0000_007E)
    check_load("LB Byte 2 (pos)", MEM_OP_LB, 32'h1000_0002, 32'h817E_F00F, 32'h0000_007E);

    // LB: Byte 3 (negative: 0x81 -> 0xFFFF_FF81)
    check_load("LB Byte 3 (neg)", MEM_OP_LB, 32'h1000_0003, 32'h817E_F00F, 32'hFFFF_FF81);

    // LBU: Byte 0 (positive: 0x0F -> 0x0000_000F)
    check_load("LBU Byte 0", MEM_OP_LBU, 32'h1000_0000, 32'h817E_F00F, 32'h0000_000F);

    // LBU: Byte 1 (negative bit set: 0xF0 -> 0x0000_00F0)
    check_load("LBU Byte 1 (zero-ext)", MEM_OP_LBU, 32'h1000_0001, 32'h817E_F00F, 32'h0000_00F0);

    // LBU: Byte 2 (0x7E -> 0x0000_007E)
    check_load("LBU Byte 2", MEM_OP_LBU, 32'h1000_0002, 32'h817E_F00F, 32'h0000_007E);

    // LBU: Byte 3 (0x81 -> 0x0000_0081)
    check_load("LBU Byte 3 (zero-ext)", MEM_OP_LBU, 32'h1000_0003, 32'h817E_F00F, 32'h0000_0081);

    // LH: Halfword 0 (0xF00F -> negative MSB -> 0xFFFF_F00F)
    check_load("LH Halfword 0 (neg)", MEM_OP_LH, 32'h1000_0000, 32'h817E_F00F, 32'hFFFF_F00F);

    // LH: Halfword 1 (0x817E -> negative MSB -> 0xFFFF_817E)
    check_load("LH Halfword 1 (neg)", MEM_OP_LH, 32'h1000_0002, 32'h817E_F00F, 32'hFFFF_817E);

    // LH: Positive halfword test with 32'h1234_7ABC
    check_load("LH Halfword 0 (pos)", MEM_OP_LH, 32'h1000_0000, 32'h1234_7ABC, 32'h0000_7ABC);
    check_load("LH Halfword 1 (pos)", MEM_OP_LH, 32'h1000_0002, 32'h1234_7ABC, 32'h0000_1234);

    // LHU: Halfword 0 (0xF00F -> 0x0000_F00F)
    check_load("LHU Halfword 0", MEM_OP_LHU, 32'h1000_0000, 32'h817E_F00F, 32'h0000_F00F);

    // LHU: Halfword 1 (0x817E -> 0x0000_817E)
    check_load("LHU Halfword 1", MEM_OP_LHU, 32'h1000_0002, 32'h817E_F00F, 32'h0000_817E);

    // LW: Full 32-bit word
    check_load("LW Word 1", MEM_OP_LW, 32'h1000_0000, 32'hDEAD_BEEF, 32'hDEAD_BEEF);
    check_load("LW Word 2", MEM_OP_LW, 32'h1000_0004, 32'h1234_5678, 32'h1234_5678);

    // ------------------------------------------------------------------------
    // Part 2: Store Operations (Write strobes & byte shifting)
    // ------------------------------------------------------------------------
    $display("\n--- Testing Store Instructions (SB, SH, SW) ---");

    // SB: Store byte 0xAB from rs2[7:0] at offset 0
    check_store("SB Offset 0", MEM_OP_SB, 32'h1000_0000, 32'h1234_56AB, 32'h0000_00AB, 4'b0001);

    // SB: Store byte 0xCD from rs2[7:0] at offset 1
    check_store("SB Offset 1", MEM_OP_SB, 32'h1000_0001, 32'h1234_56CD, 32'h0000_CD00, 4'b0010);

    // SB: Store byte 0xEF from rs2[7:0] at offset 2
    check_store("SB Offset 2", MEM_OP_SB, 32'h1000_0002, 32'h1234_56EF, 32'h00EF_0000, 4'b0100);

    // SB: Store byte 0x42 from rs2[7:0] at offset 3
    check_store("SB Offset 3", MEM_OP_SB, 32'h1000_0003, 32'h1234_5642, 32'h4200_0000, 4'b1000);

    // SH: Store halfword 0xCAFE from rs2[15:0] at halfword 0 (offset 0)
    check_store("SH Halfword 0", MEM_OP_SH, 32'h1000_0000, 32'hBABE_CAFE, 32'h0000_CAFE, 4'b0011);

    // SH: Store halfword 0xCAFE from rs2[15:0] at halfword 1 (offset 2)
    check_store("SH Halfword 1", MEM_OP_SH, 32'h1000_0002, 32'hBABE_CAFE, 32'hCAFE_0000, 4'b1100);

    // SW: Store word 0xFEED_FACE from rs2[31:0]
    check_store("SW Full Word", MEM_OP_SW, 32'h1000_0000, 32'hFEED_FACE, 32'hFEED_FACE, 4'b1111);

    // ------------------------------------------------------------------------
    // Summary
    // ------------------------------------------------------------------------
    $display("\n===============================================================");
    $display("LSU Testbench Finished: %0d tests run, %0d errors", test_count, error_count);
    $display("===============================================================");
    if (error_count == 0) begin
      $display("RESULT: ALL LSU TESTS PASSED!");
    end else begin
      $display("RESULT: %0d TESTS FAILED!", error_count);
    end
    $finish;
  end

endmodule
