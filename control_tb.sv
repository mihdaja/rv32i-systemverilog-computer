// ============================================================================
// File: control_tb.sv
// Description: Unit testbench for Control & Fetch path:
//              - pc_reg (PC register reset and enable)
//              - next_pc_gen (PC+4, Branch taken/not taken, JAL, JALR with LSB clearing)
//              - decoder (Full instruction set decode verification)
// ============================================================================

`timescale 1ns / 1ps

import rv32i_pkg::*;

module control_tb;

  int unsigned error_count = 0;
  int unsigned test_count  = 0;

  // --------------------------------------------------------------------------
  // Signals for pc_reg & next_pc_gen
  // --------------------------------------------------------------------------
  logic        clk;
  logic        rst_n;
  logic        pc_en;
  logic [31:0] next_pc;
  logic [31:0] current_pc;
  logic [31:0] pc_plus_4;

  logic [31:0] imm;
  logic [31:0] rs1_data;
  logic        branch_taken;
  logic        jump;
  logic        jump_reg;

  // DUT: PC Register
  pc_reg u_pc_reg (
    .clk     (clk),
    .rst_n   (rst_n),
    .en      (pc_en),
    .next_pc (next_pc),
    .pc      (current_pc)
  );

  // DUT: Next PC Generator
  next_pc_gen u_next_pc_gen (
    .pc           (current_pc),
    .imm          (imm),
    .rs1_data     (rs1_data),
    .branch_taken (branch_taken),
    .jump         (jump),
    .jump_reg     (jump_reg),
    .next_pc      (next_pc),
    .pc_plus_4    (pc_plus_4)
  );

  // --------------------------------------------------------------------------
  // Signals for decoder
  // --------------------------------------------------------------------------
  logic [31:0]   dec_inst;
  opcode_e       dec_opcode;
  logic [4:0]    dec_rd;
  logic [2:0]    dec_funct3;
  logic [4:0]    dec_rs1;
  logic [4:0]    dec_rs2;
  logic [6:0]    dec_funct7;
  ctrl_signals_t dec_ctrl;

  // DUT: Decoder
  decoder u_decoder (
    .inst   (dec_inst),
    .opcode (dec_opcode),
    .rd     (dec_rd),
    .funct3 (dec_funct3),
    .rs1    (dec_rs1),
    .rs2    (dec_rs2),
    .funct7 (dec_funct7),
    .ctrl   (dec_ctrl)
  );

  // Clock generation: 10ns period (100MHz)
  always #5 clk = ~clk;

  // --------------------------------------------------------------------------
  // Decoder Check Task
  // --------------------------------------------------------------------------
  task automatic check_decoder(
    input string        name,
    input logic [31:0]  inst_val,
    input opcode_e      exp_opcode,
    input logic [4:0]   exp_rd,
    input logic [2:0]   exp_funct3,
    input logic [4:0]   exp_rs1,
    input logic [4:0]   exp_rs2,
    input logic [6:0]   exp_funct7,
    input logic         exp_reg_write,
    input alu_src_a_e   exp_alu_src_a,
    input alu_src_b_e   exp_alu_src_b,
    input alu_op_e      exp_alu_op,
    input logic         exp_mem_read,
    input logic         exp_mem_write,
    input mem_op_e      exp_mem_op,
    input branch_op_e   exp_branch_op,
    input logic         exp_jump,
    input logic         exp_jump_reg,
    input wb_sel_e      exp_wb_sel,
    input imm_src_e     exp_imm_src,
    input logic         exp_is_illegal
  );
    test_count++;
    dec_inst = inst_val;
    #1; // propagate combinational logic

    if (dec_opcode !== exp_opcode ||
        dec_rd !== exp_rd ||
        dec_funct3 !== exp_funct3 ||
        dec_rs1 !== exp_rs1 ||
        dec_rs2 !== exp_rs2 ||
        dec_funct7 !== exp_funct7 ||
        dec_ctrl.reg_write !== exp_reg_write ||
        dec_ctrl.alu_src_a !== exp_alu_src_a ||
        dec_ctrl.alu_src_b !== exp_alu_src_b ||
        dec_ctrl.alu_op !== exp_alu_op ||
        dec_ctrl.mem_read !== exp_mem_read ||
        dec_ctrl.mem_write !== exp_mem_write ||
        dec_ctrl.mem_op !== exp_mem_op ||
        dec_ctrl.branch_op !== exp_branch_op ||
        dec_ctrl.jump !== exp_jump ||
        dec_ctrl.jump_reg !== exp_jump_reg ||
        dec_ctrl.wb_sel !== exp_wb_sel ||
        dec_ctrl.imm_src !== exp_imm_src ||
        dec_ctrl.is_illegal !== exp_is_illegal) begin
      $display("[FAIL] %s: mismatch for instruction 0x%08h", name, inst_val);
      $display("  Got:      op=%b rd=%0d f3=%b rs1=%0d rs2=%0d f7=%b",
               dec_opcode, dec_rd, dec_funct3, dec_rs1, dec_rs2, dec_funct7);
      $display("            rw=%b srcA=%b srcB=%b alu=%b mr=%b mw=%b mop=%b br=%b j=%b jr=%b wb=%b imm=%b ill=%b",
               dec_ctrl.reg_write, dec_ctrl.alu_src_a, dec_ctrl.alu_src_b, dec_ctrl.alu_op,
               dec_ctrl.mem_read, dec_ctrl.mem_write, dec_ctrl.mem_op, dec_ctrl.branch_op,
               dec_ctrl.jump, dec_ctrl.jump_reg, dec_ctrl.wb_sel, dec_ctrl.imm_src, dec_ctrl.is_illegal);
      $display("  Expected: op=%b rd=%0d f3=%b rs1=%0d rs2=%0d f7=%b",
               exp_opcode, exp_rd, exp_funct3, exp_rs1, exp_rs2, exp_funct7);
      $display("            rw=%b srcA=%b srcB=%b alu=%b mr=%b mw=%b mop=%b br=%b j=%b jr=%b wb=%b imm=%b ill=%b",
               exp_reg_write, exp_alu_src_a, exp_alu_src_b, exp_alu_op,
               exp_mem_read, exp_mem_write, exp_mem_op, exp_branch_op,
               exp_jump, exp_jump_reg, exp_wb_sel, exp_imm_src, exp_is_illegal);
      error_count++;
    end else begin
      $display("[PASS] %s", name);
    end
  endtask

  // --------------------------------------------------------------------------
  // Test Execution
  // --------------------------------------------------------------------------
  initial begin
    $display("===============================================================");
    $display("Starting Control & Fetch Unit Testbench (control_tb)");
    $display("===============================================================");

    clk          = 0;
    rst_n        = 0;
    pc_en        = 0;
    imm          = 32'd0;
    rs1_data     = 32'd0;
    branch_taken = 0;
    jump         = 0;
    jump_reg     = 0;
    dec_inst     = 32'd0;

    // ------------------------------------------------------------------------
    // Part 1: PC Register & Next-PC Generation
    // ------------------------------------------------------------------------
    $display("\n--- Testing PC Register & Next-PC Generator ---");

    // 1. Asynchronous Reset verification
    #2;
    test_count++;
    if (current_pc !== RESET_VECTOR) begin
      $display("[FAIL] PC reset: Expected 0x%08h, got 0x%08h", RESET_VECTOR, current_pc);
      error_count++;
    end else begin
      $display("[PASS] PC reset vector initialized to 0x%08h", RESET_VECTOR);
    end

    // 2. Sequential incrementing with en=1
    @(posedge clk);
    #1;
    rst_n = 1;
    pc_en = 1;

    @(posedge clk);
    #1;
    test_count++;
    if (current_pc !== 32'h0000_0004 || pc_plus_4 !== 32'h0000_0008) begin
      $display("[FAIL] PC+4 step 1: Expected PC=0x4, pc_plus_4=0x8; got PC=0x%08h, pc_plus_4=0x%08h",
               current_pc, pc_plus_4);
      error_count++;
    end else begin
      $display("[PASS] PC increment step 1: PC=0x%08h", current_pc);
    end

    @(posedge clk);
    #1;
    test_count++;
    if (current_pc !== 32'h0000_0008) begin
      $display("[FAIL] PC+4 step 2: Expected PC=0x8, got 0x%08h", current_pc);
      error_count++;
    end else begin
      $display("[PASS] PC increment step 2: PC=0x%08h", current_pc);
    end

    // 3. Enable gating: when en=0, PC holds value
    pc_en = 0;
    @(posedge clk);
    #1;
    test_count++;
    if (current_pc !== 32'h0000_0008) begin
      $display("[FAIL] PC enable gating: Expected PC=0x8, got 0x%08h", current_pc);
      error_count++;
    end else begin
      $display("[PASS] PC enable gating holds value when en=0");
    end

    pc_en = 1;

    // 4. Branch Not Taken
    branch_taken = 0;
    imm = 32'h0000_0020;
    #1;
    test_count++;
    if (next_pc !== 32'h0000_000C) begin
      $display("[FAIL] Branch not taken: Expected next_pc=0xC, got 0x%08h", next_pc);
      error_count++;
    end else begin
      $display("[PASS] Branch not taken correctly defaults to PC+4 (0x%08h)", next_pc);
    end

    // 5. Branch Taken
    branch_taken = 1;
    imm = 32'h0000_0020; // Target = current_pc(0x8) + 0x20 = 0x28
    #1;
    test_count++;
    if (next_pc !== 32'h0000_0028) begin
      $display("[FAIL] Branch taken: Expected next_pc=0x28, got 0x%08h", next_pc);
      error_count++;
    end else begin
      $display("[PASS] Branch taken computes PC + imm (0x%08h)", next_pc);
    end

    @(posedge clk); // PC becomes 0x28
    #1;
    branch_taken = 0;

    // 6. Direct Jump (JAL)
    jump = 1;
    imm = 32'h0000_0100; // Target = 0x28 + 0x100 = 0x128
    #1;
    test_count++;
    if (next_pc !== 32'h0000_0128) begin
      $display("[FAIL] JAL target: Expected next_pc=0x128, got 0x%08h", next_pc);
      error_count++;
    end else begin
      $display("[PASS] JAL target computes PC + imm (0x%08h)", next_pc);
    end

    @(posedge clk); // PC becomes 0x128
    #1;
    jump = 0;

    // 7. Indirect Jump (JALR) with LSB bit-clear
    jump_reg = 1;
    rs1_data = 32'h1000_0045;
    imm      = 32'h0000_0003; // Sum = 0x1000_0048, bit 0 cleared -> 0x1000_0048
    #1;
    test_count++;
    if (next_pc !== 32'h1000_0048) begin
      $display("[FAIL] JALR target: Expected next_pc=0x10000048, got 0x%08h", next_pc);
      error_count++;
    end else begin
      $display("[PASS] JALR target computes (rs1 + imm) & ~1 (0x%08h)", next_pc);
    end

    // Test JALR with odd sum to explicitly test bit-0 masking
    rs1_data = 32'h2000_0000;
    imm      = 32'h0000_0005; // Sum = 0x2000_0005, bit 0 cleared -> 0x2000_0004
    #1;
    test_count++;
    if (next_pc !== 32'h2000_0004) begin
      $display("[FAIL] JALR LSB clear: Expected next_pc=0x20000004, got 0x%08h", next_pc);
      error_count++;
    end else begin
      $display("[PASS] JALR LSB clear (0x2000_0005 -> 0x2000_0004)");
    end

    // 8. Priority Check: jump_reg > jump > branch_taken
    jump_reg     = 1;
    jump         = 1;
    branch_taken = 1;
    rs1_data     = 32'h3000_0000;
    imm          = 32'h0000_0010;
    #1;
    test_count++;
    if (next_pc !== 32'h3000_0010) begin
      $display("[FAIL] Priority jump_reg: Expected next_pc=0x30000010, got 0x%08h", next_pc);
      error_count++;
    end else begin
      $display("[PASS] Priority check: jump_reg takes precedence over jump and branch");
    end

    jump_reg = 0;
    #1;
    test_count++;
    // current_pc is 0x128, imm is 0x10 -> jump target = 0x138
    if (next_pc !== 32'h0000_0138) begin
      $display("[FAIL] Priority jump: Expected next_pc=0x138, got 0x%08h", next_pc);
      error_count++;
    end else begin
      $display("[PASS] Priority check: jump takes precedence over branch_taken");
    end

    jump = 0;
    branch_taken = 0;

    // ------------------------------------------------------------------------
    // Part 2: Decoder Comprehensive Tests
    // ------------------------------------------------------------------------
    $display("\n--- Testing Instruction Decoder ---");

    // 2.1 R-type Instructions
    // ADD: rd=1, rs1=2, rs2=3, funct3=000, funct7=0000000
    check_decoder("R-type ADD",
      {7'b0000000, 5'd3, 5'd2, 3'b000, 5'd1, 7'b0110011},
      OPCODE_OP, 5'd1, 3'b000, 5'd2, 5'd3, 7'b0000000,
      1'b1, ALU_SRC_A_RS1, ALU_SRC_B_RS2, ALU_ADD,
      1'b0, 1'b0, MEM_OP_LW, BRANCH_NONE, 1'b0, 1'b0,
      WB_ALU, IMM_I, 1'b0);

    // SUB: rd=4, rs1=5, rs2=6, funct3=000, funct7=0100000
    check_decoder("R-type SUB",
      {7'b0100000, 5'd6, 5'd5, 3'b000, 5'd4, 7'b0110011},
      OPCODE_OP, 5'd4, 3'b000, 5'd5, 5'd6, 7'b0100000,
      1'b1, ALU_SRC_A_RS1, ALU_SRC_B_RS2, ALU_SUB,
      1'b0, 1'b0, MEM_OP_LW, BRANCH_NONE, 1'b0, 1'b0,
      WB_ALU, IMM_I, 1'b0);

    // SLL: rd=7, rs1=8, rs2=9, funct3=001, funct7=0000000
    check_decoder("R-type SLL",
      {7'b0000000, 5'd9, 5'd8, 3'b001, 5'd7, 7'b0110011},
      OPCODE_OP, 5'd7, 3'b001, 5'd8, 5'd9, 7'b0000000,
      1'b1, ALU_SRC_A_RS1, ALU_SRC_B_RS2, ALU_SLL,
      1'b0, 1'b0, MEM_OP_LW, BRANCH_NONE, 1'b0, 1'b0,
      WB_ALU, IMM_I, 1'b0);

    // SLT: rd=10, rs1=11, rs2=12, funct3=010, funct7=0000000
    check_decoder("R-type SLT",
      {7'b0000000, 5'd12, 5'd11, 3'b010, 5'd10, 7'b0110011},
      OPCODE_OP, 5'd10, 3'b010, 5'd11, 5'd12, 7'b0000000,
      1'b1, ALU_SRC_A_RS1, ALU_SRC_B_RS2, ALU_SLT,
      1'b0, 1'b0, MEM_OP_LW, BRANCH_NONE, 1'b0, 1'b0,
      WB_ALU, IMM_I, 1'b0);

    // SLTU: rd=13, rs1=14, rs2=15, funct3=011, funct7=0000000
    check_decoder("R-type SLTU",
      {7'b0000000, 5'd15, 5'd14, 3'b011, 5'd13, 7'b0110011},
      OPCODE_OP, 5'd13, 3'b011, 5'd14, 5'd15, 7'b0000000,
      1'b1, ALU_SRC_A_RS1, ALU_SRC_B_RS2, ALU_SLTU,
      1'b0, 1'b0, MEM_OP_LW, BRANCH_NONE, 1'b0, 1'b0,
      WB_ALU, IMM_I, 1'b0);

    // XOR: rd=16, rs1=17, rs2=18, funct3=100, funct7=0000000
    check_decoder("R-type XOR",
      {7'b0000000, 5'd18, 5'd17, 3'b100, 5'd16, 7'b0110011},
      OPCODE_OP, 5'd16, 3'b100, 5'd17, 5'd18, 7'b0000000,
      1'b1, ALU_SRC_A_RS1, ALU_SRC_B_RS2, ALU_XOR,
      1'b0, 1'b0, MEM_OP_LW, BRANCH_NONE, 1'b0, 1'b0,
      WB_ALU, IMM_I, 1'b0);

    // SRL: rd=19, rs1=20, rs2=21, funct3=101, funct7=0000000
    check_decoder("R-type SRL",
      {7'b0000000, 5'd21, 5'd20, 3'b101, 5'd19, 7'b0110011},
      OPCODE_OP, 5'd19, 3'b101, 5'd20, 5'd21, 7'b0000000,
      1'b1, ALU_SRC_A_RS1, ALU_SRC_B_RS2, ALU_SRL,
      1'b0, 1'b0, MEM_OP_LW, BRANCH_NONE, 1'b0, 1'b0,
      WB_ALU, IMM_I, 1'b0);

    // SRA: rd=22, rs1=23, rs2=24, funct3=101, funct7=0100000
    check_decoder("R-type SRA",
      {7'b0100000, 5'd24, 5'd23, 3'b101, 5'd22, 7'b0110011},
      OPCODE_OP, 5'd22, 3'b101, 5'd23, 5'd24, 7'b0100000,
      1'b1, ALU_SRC_A_RS1, ALU_SRC_B_RS2, ALU_SRA,
      1'b0, 1'b0, MEM_OP_LW, BRANCH_NONE, 1'b0, 1'b0,
      WB_ALU, IMM_I, 1'b0);

    // OR: rd=25, rs1=26, rs2=27, funct3=110, funct7=0000000
    check_decoder("R-type OR",
      {7'b0000000, 5'd27, 5'd26, 3'b110, 5'd25, 7'b0110011},
      OPCODE_OP, 5'd25, 3'b110, 5'd26, 5'd27, 7'b0000000,
      1'b1, ALU_SRC_A_RS1, ALU_SRC_B_RS2, ALU_OR,
      1'b0, 1'b0, MEM_OP_LW, BRANCH_NONE, 1'b0, 1'b0,
      WB_ALU, IMM_I, 1'b0);

    // AND: rd=28, rs1=29, rs2=30, funct3=111, funct7=0000000
    check_decoder("R-type AND",
      {7'b0000000, 5'd30, 5'd29, 3'b111, 5'd28, 7'b0110011},
      OPCODE_OP, 5'd28, 3'b111, 5'd29, 5'd30, 7'b0000000,
      1'b1, ALU_SRC_A_RS1, ALU_SRC_B_RS2, ALU_AND,
      1'b0, 1'b0, MEM_OP_LW, BRANCH_NONE, 1'b0, 1'b0,
      WB_ALU, IMM_I, 1'b0);

    // 2.2 I-type ALU Instructions
    // ADDI: imm=12'h042 (imm[11:5]=7'b0000010, imm[4:0]=5'd2), rs1=1, funct3=000, rd=2
    check_decoder("I-type ADDI",
      {12'h042, 5'd1, 3'b000, 5'd2, 7'b0010011},
      OPCODE_OP_IMM, 5'd2, 3'b000, 5'd1, 5'd2, 7'b0000010,
      1'b1, ALU_SRC_A_RS1, ALU_SRC_B_IMM, ALU_ADD,
      1'b0, 1'b0, MEM_OP_LW, BRANCH_NONE, 1'b0, 1'b0,
      WB_ALU, IMM_I, 1'b0);

    // SLTI: imm=12'hFF0 (imm[11:5]=7'b1111111, imm[4:0]=5'd16), rs1=3, funct3=010, rd=4
    check_decoder("I-type SLTI",
      {12'hFF0, 5'd3, 3'b010, 5'd4, 7'b0010011},
      OPCODE_OP_IMM, 5'd4, 3'b010, 5'd3, 5'd16, 7'b1111111,
      1'b1, ALU_SRC_A_RS1, ALU_SRC_B_IMM, ALU_SLT,
      1'b0, 1'b0, MEM_OP_LW, BRANCH_NONE, 1'b0, 1'b0,
      WB_ALU, IMM_I, 1'b0);

    // SLTIU: imm=12'h010 (imm[11:5]=7'b0000000, imm[4:0]=5'd16), rs1=5, funct3=011, rd=6
    check_decoder("I-type SLTIU",
      {12'h010, 5'd5, 3'b011, 5'd6, 7'b0010011},
      OPCODE_OP_IMM, 5'd6, 3'b011, 5'd5, 5'd16, 7'b0000000,
      1'b1, ALU_SRC_A_RS1, ALU_SRC_B_IMM, ALU_SLTU,
      1'b0, 1'b0, MEM_OP_LW, BRANCH_NONE, 1'b0, 1'b0,
      WB_ALU, IMM_I, 1'b0);

    // XORI: imm=12'h0AA (imm[11:5]=7'b0000101, imm[4:0]=5'd10), rs1=7, funct3=100, rd=8
    check_decoder("I-type XORI",
      {12'h0AA, 5'd7, 3'b100, 5'd8, 7'b0010011},
      OPCODE_OP_IMM, 5'd8, 3'b100, 5'd7, 5'd10, 7'b0000101,
      1'b1, ALU_SRC_A_RS1, ALU_SRC_B_IMM, ALU_XOR,
      1'b0, 1'b0, MEM_OP_LW, BRANCH_NONE, 1'b0, 1'b0,
      WB_ALU, IMM_I, 1'b0);

    // ORI: imm=12'h055 (imm[11:5]=7'b0000010, imm[4:0]=5'd21), rs1=9, funct3=110, rd=10
    check_decoder("I-type ORI",
      {12'h055, 5'd9, 3'b110, 5'd10, 7'b0010011},
      OPCODE_OP_IMM, 5'd10, 3'b110, 5'd9, 5'd21, 7'b0000010,
      1'b1, ALU_SRC_A_RS1, ALU_SRC_B_IMM, ALU_OR,
      1'b0, 1'b0, MEM_OP_LW, BRANCH_NONE, 1'b0, 1'b0,
      WB_ALU, IMM_I, 1'b0);

    // ANDI: imm=12'h00F (imm[11:5]=7'b0000000, imm[4:0]=5'd15), rs1=11, funct3=111, rd=12
    check_decoder("I-type ANDI",
      {12'h00F, 5'd11, 3'b111, 5'd12, 7'b0010011},
      OPCODE_OP_IMM, 5'd12, 3'b111, 5'd11, 5'd15, 7'b0000000,
      1'b1, ALU_SRC_A_RS1, ALU_SRC_B_IMM, ALU_AND,
      1'b0, 1'b0, MEM_OP_LW, BRANCH_NONE, 1'b0, 1'b0,
      WB_ALU, IMM_I, 1'b0);

    // SLLI
    check_decoder("I-type SLLI",
      {7'b0000000, 5'd4, 5'd13, 3'b001, 5'd14, 7'b0010011},
      OPCODE_OP_IMM, 5'd14, 3'b001, 5'd13, 5'd4, 7'b0000000,
      1'b1, ALU_SRC_A_RS1, ALU_SRC_B_IMM, ALU_SLL,
      1'b0, 1'b0, MEM_OP_LW, BRANCH_NONE, 1'b0, 1'b0,
      WB_ALU, IMM_I, 1'b0);

    // SRLI
    check_decoder("I-type SRLI",
      {7'b0000000, 5'd5, 5'd15, 3'b101, 5'd16, 7'b0010011},
      OPCODE_OP_IMM, 5'd16, 3'b101, 5'd15, 5'd5, 7'b0000000,
      1'b1, ALU_SRC_A_RS1, ALU_SRC_B_IMM, ALU_SRL,
      1'b0, 1'b0, MEM_OP_LW, BRANCH_NONE, 1'b0, 1'b0,
      WB_ALU, IMM_I, 1'b0);

    // SRAI
    check_decoder("I-type SRAI",
      {7'b0100000, 5'd6, 5'd17, 3'b101, 5'd18, 7'b0010011},
      OPCODE_OP_IMM, 5'd18, 3'b101, 5'd17, 5'd6, 7'b0100000,
      1'b1, ALU_SRC_A_RS1, ALU_SRC_B_IMM, ALU_SRA,
      1'b0, 1'b0, MEM_OP_LW, BRANCH_NONE, 1'b0, 1'b0,
      WB_ALU, IMM_I, 1'b0);

    // 2.3 Load Instructions
    // LB
    check_decoder("Load LB",
      {12'h010, 5'd1, 3'b000, 5'd2, 7'b0000011},
      OPCODE_LOAD, 5'd2, 3'b000, 5'd1, 5'd16, 7'b0000000,
      1'b1, ALU_SRC_A_RS1, ALU_SRC_B_IMM, ALU_ADD,
      1'b1, 1'b0, MEM_OP_LB, BRANCH_NONE, 1'b0, 1'b0,
      WB_MEM, IMM_I, 1'b0);

    // LH
    check_decoder("Load LH",
      {12'h020, 5'd3, 3'b001, 5'd4, 7'b0000011},
      OPCODE_LOAD, 5'd4, 3'b001, 5'd3, 5'd0, 7'b0000001,
      1'b1, ALU_SRC_A_RS1, ALU_SRC_B_IMM, ALU_ADD,
      1'b1, 1'b0, MEM_OP_LH, BRANCH_NONE, 1'b0, 1'b0,
      WB_MEM, IMM_I, 1'b0);

    // LW
    check_decoder("Load LW",
      {12'h030, 5'd5, 3'b010, 5'd6, 7'b0000011},
      OPCODE_LOAD, 5'd6, 3'b010, 5'd5, 5'd16, 7'b0000001,
      1'b1, ALU_SRC_A_RS1, ALU_SRC_B_IMM, ALU_ADD,
      1'b1, 1'b0, MEM_OP_LW, BRANCH_NONE, 1'b0, 1'b0,
      WB_MEM, IMM_I, 1'b0);

    // LBU
    check_decoder("Load LBU",
      {12'h040, 5'd7, 3'b100, 5'd8, 7'b0000011},
      OPCODE_LOAD, 5'd8, 3'b100, 5'd7, 5'd0, 7'b0000010,
      1'b1, ALU_SRC_A_RS1, ALU_SRC_B_IMM, ALU_ADD,
      1'b1, 1'b0, MEM_OP_LBU, BRANCH_NONE, 1'b0, 1'b0,
      WB_MEM, IMM_I, 1'b0);

    // LHU
    check_decoder("Load LHU",
      {12'h050, 5'd9, 3'b101, 5'd10, 7'b0000011},
      OPCODE_LOAD, 5'd10, 3'b101, 5'd9, 5'd16, 7'b0000010,
      1'b1, ALU_SRC_A_RS1, ALU_SRC_B_IMM, ALU_ADD,
      1'b1, 1'b0, MEM_OP_LHU, BRANCH_NONE, 1'b0, 1'b0,
      WB_MEM, IMM_I, 1'b0);

    // 2.4 Store Instructions
    // SB
    check_decoder("Store SB",
      {7'b0000000, 5'd2, 5'd1, 3'b000, 5'b00100, 7'b0100011},
      OPCODE_STORE, 5'd4, 3'b000, 5'd1, 5'd2, 7'b0000000,
      1'b0, ALU_SRC_A_RS1, ALU_SRC_B_IMM, ALU_ADD,
      1'b0, 1'b1, MEM_OP_SB, BRANCH_NONE, 1'b0, 1'b0,
      WB_ALU, IMM_S, 1'b0);

    // SH
    check_decoder("Store SH",
      {7'b0000000, 5'd4, 5'd3, 3'b001, 5'b01000, 7'b0100011},
      OPCODE_STORE, 5'd8, 3'b001, 5'd3, 5'd4, 7'b0000000,
      1'b0, ALU_SRC_A_RS1, ALU_SRC_B_IMM, ALU_ADD,
      1'b0, 1'b1, MEM_OP_SH, BRANCH_NONE, 1'b0, 1'b0,
      WB_ALU, IMM_S, 1'b0);

    // SW
    check_decoder("Store SW",
      {7'b0000000, 5'd6, 5'd5, 3'b010, 5'b01100, 7'b0100011},
      OPCODE_STORE, 5'd12, 3'b010, 5'd5, 5'd6, 7'b0000000,
      1'b0, ALU_SRC_A_RS1, ALU_SRC_B_IMM, ALU_ADD,
      1'b0, 1'b1, MEM_OP_SW, BRANCH_NONE, 1'b0, 1'b0,
      WB_ALU, IMM_S, 1'b0);

    // 2.5 Branch Instructions
    // BEQ
    check_decoder("Branch BEQ",
      {1'b0, 6'b000000, 5'd2, 5'd1, 3'b000, 4'b0100, 1'b0, 7'b1100011},
      OPCODE_BRANCH, 5'd8, 3'b000, 5'd1, 5'd2, 7'b0000000,
      1'b0, ALU_SRC_A_RS1, ALU_SRC_B_RS2, ALU_SUB,
      1'b0, 1'b0, MEM_OP_LW, BRANCH_BEQ, 1'b0, 1'b0,
      WB_ALU, IMM_B, 1'b0);

    // BNE
    check_decoder("Branch BNE",
      {1'b0, 6'b000000, 5'd4, 5'd3, 3'b001, 4'b0100, 1'b0, 7'b1100011},
      OPCODE_BRANCH, 5'd8, 3'b001, 5'd3, 5'd4, 7'b0000000,
      1'b0, ALU_SRC_A_RS1, ALU_SRC_B_RS2, ALU_SUB,
      1'b0, 1'b0, MEM_OP_LW, BRANCH_BNE, 1'b0, 1'b0,
      WB_ALU, IMM_B, 1'b0);

    // BLT
    check_decoder("Branch BLT",
      {1'b0, 6'b000000, 5'd6, 5'd5, 3'b100, 4'b0100, 1'b0, 7'b1100011},
      OPCODE_BRANCH, 5'd8, 3'b100, 5'd5, 5'd6, 7'b0000000,
      1'b0, ALU_SRC_A_RS1, ALU_SRC_B_RS2, ALU_SUB,
      1'b0, 1'b0, MEM_OP_LW, BRANCH_BLT, 1'b0, 1'b0,
      WB_ALU, IMM_B, 1'b0);

    // BGE
    check_decoder("Branch BGE",
      {1'b0, 6'b000000, 5'd8, 5'd7, 3'b101, 4'b0100, 1'b0, 7'b1100011},
      OPCODE_BRANCH, 5'd8, 3'b101, 5'd7, 5'd8, 7'b0000000,
      1'b0, ALU_SRC_A_RS1, ALU_SRC_B_RS2, ALU_SUB,
      1'b0, 1'b0, MEM_OP_LW, BRANCH_BGE, 1'b0, 1'b0,
      WB_ALU, IMM_B, 1'b0);

    // BLTU
    check_decoder("Branch BLTU",
      {1'b0, 6'b000000, 5'd10, 5'd9, 3'b110, 4'b0100, 1'b0, 7'b1100011},
      OPCODE_BRANCH, 5'd8, 3'b110, 5'd9, 5'd10, 7'b0000000,
      1'b0, ALU_SRC_A_RS1, ALU_SRC_B_RS2, ALU_SUB,
      1'b0, 1'b0, MEM_OP_LW, BRANCH_BLTU, 1'b0, 1'b0,
      WB_ALU, IMM_B, 1'b0);

    // BGEU
    check_decoder("Branch BGEU",
      {1'b0, 6'b000000, 5'd12, 5'd11, 3'b111, 4'b0100, 1'b0, 7'b1100011},
      OPCODE_BRANCH, 5'd8, 3'b111, 5'd11, 5'd12, 7'b0000000,
      1'b0, ALU_SRC_A_RS1, ALU_SRC_B_RS2, ALU_SUB,
      1'b0, 1'b0, MEM_OP_LW, BRANCH_BGEU, 1'b0, 1'b0,
      WB_ALU, IMM_B, 1'b0);

    // 2.6 U-type Instructions
    // LUI: inst = {20'h12345, 5'd1, 7'b0110111}
    // 20'h12345 = 20'b0001001_00011_01000_101
    // inst[31:25] = 7'b0001001, inst[24:20] = 5'd3, inst[19:15] = 5'd8, inst[14:12] = 3'b101
    check_decoder("U-type LUI",
      {20'h12345, 5'd1, 7'b0110111},
      OPCODE_LUI, 5'd1, 3'b101, 5'd8, 5'd3, 7'b0001001,
      1'b1, ALU_SRC_A_ZERO, ALU_SRC_B_IMM, ALU_PASS_B,
      1'b0, 1'b0, MEM_OP_LW, BRANCH_NONE, 1'b0, 1'b0,
      WB_IMM, IMM_U, 1'b0);

    // AUIPC: inst = {20'h54321, 5'd2, 7'b0010111}
    // 20'h54321 = 20'b0101010_00011_00100_001
    // inst[31:25] = 7'b0101010, inst[24:20] = 5'd3, inst[19:15] = 5'd4, inst[14:12] = 3'b001
    check_decoder("U-type AUIPC",
      {20'h54321, 5'd2, 7'b0010111},
      OPCODE_AUIPC, 5'd2, 3'b001, 5'd4, 5'd3, 7'b0101010,
      1'b1, ALU_SRC_A_PC, ALU_SRC_B_IMM, ALU_ADD,
      1'b0, 1'b0, MEM_OP_LW, BRANCH_NONE, 1'b0, 1'b0,
      WB_ALU, IMM_U, 1'b0);

    // 2.7 Jumps
    // JAL
    check_decoder("J-type JAL",
      {1'b0, 10'd0, 1'b0, 8'd0, 5'd1, 7'b1101111},
      OPCODE_JAL, 5'd1, 3'b000, 5'd0, 5'd0, 7'b0000000,
      1'b1, ALU_SRC_A_PC, ALU_SRC_B_FOUR, ALU_ADD,
      1'b0, 1'b0, MEM_OP_LW, BRANCH_NONE, 1'b1, 1'b0,
      WB_PC4, IMM_J, 1'b0);

    // JALR
    check_decoder("I-type JALR",
      {12'h008, 5'd2, 3'b000, 5'd1, 7'b1100111},
      OPCODE_JALR, 5'd1, 3'b000, 5'd2, 5'd8, 7'b0000000,
      1'b1, ALU_SRC_A_PC, ALU_SRC_B_FOUR, ALU_ADD,
      1'b0, 1'b0, MEM_OP_LW, BRANCH_NONE, 1'b0, 1'b1,
      WB_PC4, IMM_I, 1'b0);

    // 2.8 System & Fence
    // FENCE
    check_decoder("FENCE",
      32'h0000_000F,
      OPCODE_FENCE, 5'd0, 3'b000, 5'd0, 5'd0, 7'b0000000,
      1'b0, ALU_SRC_A_RS1, ALU_SRC_B_RS2, ALU_ADD,
      1'b0, 1'b0, MEM_OP_LW, BRANCH_NONE, 1'b0, 1'b0,
      WB_ALU, IMM_I, 1'b0);

    // ECALL (SYSTEM)
    check_decoder("ECALL (SYSTEM)",
      32'h0000_0073,
      OPCODE_SYSTEM, 5'd0, 3'b000, 5'd0, 5'd0, 7'b0000000,
      1'b0, ALU_SRC_A_RS1, ALU_SRC_B_RS2, ALU_ADD,
      1'b0, 1'b0, MEM_OP_LW, BRANCH_NONE, 1'b0, 1'b0,
      WB_ALU, IMM_I, 1'b0);

    // 2.9 Illegal Instructions
    // Invalid Opcode
    dec_inst = 32'h0000_007F; // 7'b1111111 is illegal
    #1;
    test_count++;
    if (!dec_ctrl.is_illegal || dec_ctrl.reg_write) begin
      $display("[FAIL] Illegal Opcode not flagged");
      error_count++;
    end else begin
      $display("[PASS] Illegal opcode flagged is_illegal=1");
    end

    // Invalid funct7 for ADD
    dec_inst = {7'b1111111, 5'd3, 5'd2, 3'b000, 5'd1, 7'b0110011};
    #1;
    test_count++;
    if (!dec_ctrl.is_illegal) begin
      $display("[FAIL] Illegal funct7 for R-type not flagged");
      error_count++;
    end else begin
      $display("[PASS] Illegal funct7 for R-type flagged is_illegal=1");
    end

    // Invalid funct3 for LOAD
    dec_inst = {12'h000, 5'd1, 3'b111, 5'd2, 7'b0000011};
    #1;
    test_count++;
    if (!dec_ctrl.is_illegal) begin
      $display("[FAIL] Illegal funct3 for LOAD not flagged");
      error_count++;
    end else begin
      $display("[PASS] Illegal funct3 for LOAD flagged is_illegal=1");
    end

    // Invalid funct3 for JALR
    dec_inst = {12'h000, 5'd1, 3'b001, 5'd2, 7'b1100111};
    #1;
    test_count++;
    if (!dec_ctrl.is_illegal) begin
      $display("[FAIL] Illegal funct3 for JALR not flagged");
      error_count++;
    end else begin
      $display("[PASS] Illegal funct3 for JALR flagged is_illegal=1");
    end

    // ------------------------------------------------------------------------
    // Summary
    // ------------------------------------------------------------------------
    $display("\n===============================================================");
    $display("Control & Fetch Testbench Finished: %0d tests run, %0d errors", test_count, error_count);
    $display("===============================================================");
    if (error_count == 0) begin
      $display("RESULT: ALL CONTROL TESTS PASSED!");
    end else begin
      $display("RESULT: %0d TESTS FAILED!", error_count);
    end
    $finish;
  end

endmodule
