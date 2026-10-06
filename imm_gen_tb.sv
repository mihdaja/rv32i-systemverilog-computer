`timescale 1ns/1ps

import rv32i_pkg::*;

module imm_gen_tb;

  logic [31:0] inst;
  imm_src_e    imm_src;
  logic [31:0] imm;

  int test_count = 0;
  int error_count = 0;

  // DUT instantiation
  imm_gen dut (
    .inst(inst),
    .imm_src(imm_src),
    .imm(imm)
  );

  task check(
    input string       test_name,
    input logic [31:0] exp_imm
  );
    test_count++;
    #1; // propagate combinational logic
    if (imm !== exp_imm) begin
      $display("[FAIL] %s: inst=0x%08h, src=%s -> imm=0x%08h (exp 0x%08h)",
               test_name, inst, imm_src.name(), imm, exp_imm);
      error_count++;
    end else begin
      $display("[PASS] %s: imm=0x%08h", test_name, imm);
    end
  endtask

  initial begin
    $display("========================================");
    $display("Starting Immediate Generator Testbench");
    $display("========================================");

    // ----------------------------------------------------
    // 1. IMM_I format: 12-bit signed immediate from inst[31:20]
    // ----------------------------------------------------
    imm_src = IMM_I;

    // Positive: +1 (e.g. addi x1, x0, 1)
    inst = 32'h0010_0093;
    check("IMM_I positive (+1)", 32'h0000_0001);

    // Positive max: +2047 (0x7FF)
    inst = {12'h7FF, 20'h00000};
    check("IMM_I max positive (+2047)", 32'h0000_07FF);

    // Zero: 0
    inst = 32'h0000_0000;
    check("IMM_I zero (0)", 32'h0000_0000);

    // Negative: -1 (0xFFF -> sign extended to 0xFFFFFFFF)
    inst = 32'hFFF0_0093;
    check("IMM_I negative (-1)", 32'hFFFF_FFFF);

    // Negative: -4 (lw x2, -4(x1) -> 0xFFC...)
    inst = 32'hFFC0_A103;
    check("IMM_I negative (-4)", 32'hFFFF_FFFC);

    // Negative min: -2048 (0x800 -> 0xFFFFF800)
    inst = {12'h800, 20'h00000};
    check("IMM_I min negative (-2048)", 32'hFFFF_F800);

    // ----------------------------------------------------
    // 2. IMM_S format: 12-bit signed immediate {inst[31:25], inst[11:7]}
    // ----------------------------------------------------
    imm_src = IMM_S;

    // Positive: +8 (sw x2, 8(x1) -> inst[31:25]=0, inst[11:7]=8)
    inst = {7'b0000000, 5'd2, 5'd1, 3'b010, 5'b01000, 7'b0100011};
    check("IMM_S positive (+8)", 32'd8);

    // Positive max: +2047 (0x7FF -> {7'b0111111, 5'b11111})
    inst = {7'b0111111, 5'd0, 5'd0, 3'b000, 5'b11111, 7'b0100011};
    check("IMM_S max positive (+2047)", 32'h0000_07FF);

    // Negative: -8 (12-bit 0xFF8 -> {7'b1111111, 5'b11000})
    inst = {7'b1111111, 5'd2, 5'd1, 3'b010, 5'b11000, 7'b0100011};
    check("IMM_S negative (-8)", 32'hFFFF_FFF8);

    // Negative min: -2048 (12-bit 0x800 -> {7'b1000000, 5'b00000})
    inst = {7'b1000000, 5'd0, 5'd0, 3'b000, 5'b00000, 7'b0100011};
    check("IMM_S min negative (-2048)", 32'hFFFF_F800);

    // ----------------------------------------------------
    // 3. IMM_B format: 13-bit signed offset {inst[31], inst[7], inst[30:25], inst[11:8], 1'b0}
    // ----------------------------------------------------
    imm_src = IMM_B;

    // Positive: +16 (bit 4 = 1 -> inst[11:8] = 4'b1000)
    // inst[31]=0, inst[7]=0, inst[30:25]=0, inst[11:8]=4'b1000
    inst = {1'b0, 6'b000000, 5'd0, 5'd0, 3'b000, 4'b1000, 1'b0, 7'b1100011};
    check("IMM_B positive (+16)", 32'd16);

    // Positive max: +4094 (13-bit 0x0FFE -> inst[31]=0, inst[7]=1, inst[30:25]=6'b111111, inst[11:8]=4'b1111)
    inst = {1'b0, 6'b111111, 5'd0, 5'd0, 3'b000, 4'b1111, 1'b1, 7'b1100011};
    check("IMM_B max positive (+4094)", 32'h0000_0FFE);

    // Negative: -4 (13-bit 0x1FFC -> inst[31]=1, inst[7]=1, inst[30:25]=6'b111111, inst[11:8]=4'b1110)
    inst = {1'b1, 6'b111111, 5'd0, 5'd0, 3'b001, 4'b1110, 1'b1, 7'b1100011};
    check("IMM_B negative (-4)", 32'hFFFF_FFFC);

    // Negative min: -4096 (13-bit 0x1000 -> inst[31]=1, inst[7]=0, inst[30:25]=0, inst[11:8]=0)
    inst = {1'b1, 6'b000000, 5'd0, 5'd0, 3'b000, 4'b0000, 1'b0, 7'b1100011};
    check("IMM_B min negative (-4096)", 32'hFFFF_F000);

    // ----------------------------------------------------
    // 4. IMM_U format: 20-bit upper immediate {inst[31:12], 12'b0}
    // ----------------------------------------------------
    imm_src = IMM_U;

    // lui x1, 0x12345 -> {20'h12345, 12'h000}
    inst = {20'h12345, 5'd1, 7'b0110111};
    check("IMM_U positive upper (0x12345000)", 32'h1234_5000);

    // lui x1, 0x80000 -> {20'h80000, 12'h000}
    inst = {20'h80000, 5'd1, 7'b0110111};
    check("IMM_U MSB 1 upper (0x80000000)", 32'h8000_0000);

    // lui x1, 0xFFFFF -> {20'hFFFFF, 12'h000}
    inst = {20'hFFFFF, 5'd1, 7'b0110111};
    check("IMM_U all-ones upper (0xFFFFF000)", 32'hFFFF_F000);

    // ----------------------------------------------------
    // 5. IMM_J format: 21-bit signed offset {inst[31], inst[19:12], inst[20], inst[30:21], 1'b0}
    // ----------------------------------------------------
    imm_src = IMM_J;

    // Positive: +2048 (bit 11 = 1 -> inst[20] = 1, rest zero)
    // inst[31]=0, inst[19:12]=0, inst[20]=1, inst[30:21]=0
    inst = {1'b0, 10'b00_0000_0000, 1'b1, 8'h00, 5'd1, 7'b1101111};
    check("IMM_J positive (+2048)", 32'd2048);

    // Positive: +2 (bit 1 = 1 -> inst[21] = 1, rest zero)
    inst = {1'b0, 10'b00_0000_0001, 1'b0, 8'h00, 5'd1, 7'b1101111};
    check("IMM_J positive (+2)", 32'd2);

    // Positive max: +1048574 (21-bit 0x0FFFFE -> inst[31]=0, inst[19:12]=0xFF, inst[20]=1, inst[30:21]=10'h3FF)
    inst = {1'b0, 10'b11_1111_1111, 1'b1, 8'hFF, 5'd1, 7'b1101111};
    check("IMM_J max positive (+1048574)", 32'h000F_FFFE);

    // Negative: -4 (21-bit 0x1FFFFC)
    // bit 20: inst[31]=1
    // bit 19:12: inst[19:12]=8'hFF
    // bit 11: inst[20]=1
    // bit 10:1: 10'b11_1111_1110 -> inst[30:21] = 10'h3FE
    inst = {1'b1, 10'b11_1111_1110, 1'b1, 8'hFF, 5'd1, 7'b1101111};
    check("IMM_J negative (-4)", 32'hFFFF_FFFC);

    // Negative min: -1048576 (21-bit 0x100000 -> inst[31]=1, rest zero)
    inst = {1'b1, 10'b00_0000_0000, 1'b0, 8'h00, 5'd1, 7'b1101111};
    check("IMM_J min negative (-1048576)", 32'hFFF0_0000);

    // ----------------------------------------------------
    // 6. Default / Invalid format
    // ----------------------------------------------------
    imm_src = imm_src_e'(3'b111);
    inst = 32'hFFFF_FFFF;
    check("Default undefined imm_src", 32'd0);

    $display("========================================");
    if (error_count == 0) begin
      $display("Immediate Generator Testbench PASSED (%0d tests)", test_count);
    end else begin
      $display("Immediate Generator Testbench FAILED (%0d errors out of %0d tests)", error_count, test_count);
    end
    $display("========================================");

    if (error_count != 0) $stop;
    $finish;
  end

endmodule
