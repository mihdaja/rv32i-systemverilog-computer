`timescale 1ns/1ps

import rv32i_pkg::*;

module alu_tb;

  logic [31:0] a;
  logic [31:0] b;
  alu_op_e     alu_op;
  logic [31:0] result;
  logic        zero;

  int test_count = 0;
  int error_count = 0;

  // DUT instantiation
  alu dut (
    .a(a),
    .b(b),
    .alu_op(alu_op),
    .result(result),
    .zero(zero)
  );

  task check(
    input string       test_name,
    input logic [31:0] exp_result,
    input logic        exp_zero
  );
    test_count++;
    #1; // propagate combinational logic
    if (result !== exp_result || zero !== exp_zero) begin
      $display("[FAIL] %s: a=0x%08h, b=0x%08h, op=%s -> result=0x%08h (exp 0x%08h), zero=%b (exp %b)",
               test_name, a, b, alu_op.name(), result, exp_result, zero, exp_zero);
      error_count++;
    end else begin
      $display("[PASS] %s: result=0x%08h, zero=%b", test_name, result, zero);
    end
  endtask

  initial begin
    $display("========================================");
    $display("Starting ALU Testbench");
    $display("========================================");

    // 1. ALU_ADD
    alu_op = ALU_ADD;
    a = 32'd10; b = 32'd25;
    check("ADD simple", 32'd35, 1'b0);

    a = 32'hFFFF_FFFF; b = 32'd1;
    check("ADD overflow wrap-around", 32'h0000_0000, 1'b1);

    a = 32'h7FFF_FFFF; b = 32'h0000_0001;
    check("ADD positive overflow into negative", 32'h8000_0000, 1'b0);

    a = -32'd10; b = 32'd10;
    check("ADD opposite sign zero", 32'd0, 1'b1);

    // 2. ALU_SUB
    alu_op = ALU_SUB;
    a = 32'd50; b = 32'd20;
    check("SUB simple", 32'd30, 1'b0);

    a = 32'd20; b = 32'd20;
    check("SUB equal operands zero", 32'd0, 1'b1);

    a = 32'd0; b = 32'd1;
    check("SUB underflow wrap", 32'hFFFF_FFFF, 1'b0);

    a = 32'h8000_0000; b = 32'd1;
    check("SUB underflow min-negative", 32'h7FFF_FFFF, 1'b0);

    // 3. ALU_SLL
    alu_op = ALU_SLL;
    a = 32'h0000_0001; b = 32'd4;
    check("SLL by 4", 32'h0000_0010, 1'b0);

    a = 32'h0000_0001; b = 32'd31;
    check("SLL by 31", 32'h8000_0000, 1'b0);

    a = 32'hFFFF_FFFF; b = 32'd0;
    check("SLL by 0", 32'hFFFF_FFFF, 1'b0);

    a = 32'h0000_0001; b = 32'hFFFF_FFE4; // b[4:0] = 4 (0x04)
    check("SLL ignore upper bits of shift amount", 32'h0000_0010, 1'b0);

    // 4. ALU_SLT (signed)
    alu_op = ALU_SLT;
    a = 32'd10; b = 32'd20;
    check("SLT pos < pos (true)", 32'd1, 1'b0);

    a = 32'd20; b = 32'd10;
    check("SLT pos < pos (false)", 32'd0, 1'b1);

    a = 32'd15; b = 32'd15;
    check("SLT pos == pos (false)", 32'd0, 1'b1);

    a = -32'd5; b = 32'd5;
    check("SLT neg < pos (true)", 32'd1, 1'b0);

    a = 32'd5; b = -32'd5;
    check("SLT pos < neg (false)", 32'd0, 1'b1);

    a = -32'd10; b = -32'd5;
    check("SLT neg < neg (true)", 32'd1, 1'b0);

    a = -32'd5; b = -32'd10;
    check("SLT neg < neg (false)", 32'd0, 1'b1);

    a = 32'h8000_0000; b = 32'h7FFF_FFFF;
    check("SLT min-int < max-int", 32'd1, 1'b0);

    // 5. ALU_SLTU (unsigned)
    alu_op = ALU_SLTU;
    a = 32'd10; b = 32'd20;
    check("SLTU small < large (true)", 32'd1, 1'b0);

    a = 32'd20; b = 32'd10;
    check("SLTU large < small (false)", 32'd0, 1'b1);

    a = 32'h0000_0005; b = 32'hFFFF_FFFF;
    check("SLTU 5 < 0xFFFFFFFF (true)", 32'd1, 1'b0);

    a = 32'hFFFF_FFFF; b = 32'h0000_0005;
    check("SLTU 0xFFFFFFFF < 5 (false)", 32'd0, 1'b1);

    a = 32'h8000_0000; b = 32'h7FFF_FFFF;
    check("SLTU 0x80000000 < 0x7FFFFFFF (false)", 32'd0, 1'b1);

    // 6. ALU_XOR
    alu_op = ALU_XOR;
    a = 32'hAAAA_AAAA; b = 32'h5555_5555;
    check("XOR complementary", 32'hFFFF_FFFF, 1'b0);

    a = 32'h1234_5678; b = 32'h1234_5678;
    check("XOR identical zero", 32'h0000_0000, 1'b1);

    // 7. ALU_SRL (logical shift right)
    alu_op = ALU_SRL;
    a = 32'h8000_0000; b = 32'd1;
    check("SRL by 1 zero fill", 32'h4000_0000, 1'b0);

    a = 32'h8000_0000; b = 32'd31;
    check("SRL by 31", 32'h0000_0001, 1'b0);

    a = 32'hFFFF_FFFF; b = 32'h0000_0024; // shift amount 4
    check("SRL ignore high bits of b", 32'h0FFF_FFFF, 1'b0);

    // 8. ALU_SRA (arithmetic shift right)
    alu_op = ALU_SRA;
    a = 32'h8000_0000; b = 32'd1;
    check("SRA negative sign extension by 1", 32'hC000_0000, 1'b0);

    a = 32'h8000_0000; b = 32'd31;
    check("SRA negative sign extension by 31", 32'hFFFF_FFFF, 1'b0);

    a = 32'h4000_0000; b = 32'd2;
    check("SRA positive sign bit 0", 32'h1000_0000, 1'b0);

    a = 32'hF000_0000; b = 32'hFFFF_FF84; // shift amount 4
    check("SRA ignore high bits of b", 32'hFF00_0000, 1'b0);

    // 9. ALU_OR
    alu_op = ALU_OR;
    a = 32'hF0F0_0000; b = 32'h0F0F_0000;
    check("OR bits", 32'hFFFF_0000, 1'b0);

    a = 32'd0; b = 32'd0;
    check("OR zero", 32'd0, 1'b1);

    // 10. ALU_AND
    alu_op = ALU_AND;
    a = 32'hFFFF_0000; b = 32'h00FF_FF00;
    check("AND bits", 32'h00FF_0000, 1'b0);

    a = 32'hAAAA_AAAA; b = 32'h5555_5555;
    check("AND disjoint zero", 32'd0, 1'b1);

    // 11. ALU_PASS_B
    alu_op = ALU_PASS_B;
    a = 32'hDEAD_BEEF; b = 32'hCAFE_BABE;
    check("PASS_B non-zero", 32'hCAFE_BABE, 1'b0);

    a = 32'hDEAD_BEEF; b = 32'd0;
    check("PASS_B zero", 32'd0, 1'b1);

    $display("========================================");
    if (error_count == 0) begin
      $display("ALU Testbench PASSED (%0d tests)", test_count);
    end else begin
      $display("ALU Testbench FAILED (%0d errors out of %0d tests)", error_count, test_count);
    end
    $display("========================================");

    if (error_count != 0) $stop;
    $finish;
  end

endmodule
