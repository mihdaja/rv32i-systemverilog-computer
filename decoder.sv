// ============================================================================
// File: decoder.sv
// Description: RV32I Instruction Decoder.
//              Decodes 32-bit instructions into architectural register indices,
//              funct fields, opcode, and control signals for the execution
//              and memory pipelines.
// ============================================================================

`ifndef DECODER_SV
`define DECODER_SV

`timescale 1ns / 1ps

import rv32i_pkg::*;

module decoder (
  input  logic [31:0]    inst,
  output opcode_e        opcode,
  output logic [4:0]     rd,
  output logic [2:0]     funct3,
  output logic [4:0]     rs1,
  output logic [4:0]     rs2,
  output logic [6:0]     funct7,
  output ctrl_signals_t  ctrl
);

  assign opcode = opcode_e'(inst[6:0]);
  assign rd     = inst[11:7];
  assign funct3 = inst[14:12];
  assign rs1    = inst[19:15];
  assign rs2    = inst[24:20];
  assign funct7 = inst[31:25];

  always_comb begin
    // Default safe control values
    ctrl.reg_write  = 1'b0;
    ctrl.alu_src_a  = ALU_SRC_A_RS1;
    ctrl.alu_src_b  = ALU_SRC_B_RS2;
    ctrl.alu_op     = ALU_ADD;
    ctrl.mem_read   = 1'b0;
    ctrl.mem_write  = 1'b0;
    ctrl.mem_op     = MEM_OP_LW;
    ctrl.branch_op  = BRANCH_NONE;
    ctrl.jump       = 1'b0;
    ctrl.jump_reg   = 1'b0;
    ctrl.wb_sel     = WB_ALU;
    ctrl.imm_src    = IMM_I;
    ctrl.is_illegal = 1'b0;

    case (opcode)
      // ----------------------------------------------------------------------
      // R-type: Register-Register Arithmetic and Logical Instructions
      // ----------------------------------------------------------------------
      OPCODE_OP: begin
        ctrl.reg_write = 1'b1;
        ctrl.alu_src_a = ALU_SRC_A_RS1;
        ctrl.alu_src_b = ALU_SRC_B_RS2;
        ctrl.wb_sel    = WB_ALU;

        case (funct3)
          FUNCT3_ADD_SUB: begin
            if (funct7 == FUNCT7_STANDARD) begin
              ctrl.alu_op = ALU_ADD;
            end else if (funct7 == FUNCT7_ALT) begin
              ctrl.alu_op = ALU_SUB;
            end else begin
              ctrl.is_illegal = 1'b1;
            end
          end

          FUNCT3_SLL: begin
            if (funct7 == FUNCT7_STANDARD) begin
              ctrl.alu_op = ALU_SLL;
            end else begin
              ctrl.is_illegal = 1'b1;
            end
          end

          FUNCT3_SLT: begin
            if (funct7 == FUNCT7_STANDARD) begin
              ctrl.alu_op = ALU_SLT;
            end else begin
              ctrl.is_illegal = 1'b1;
            end
          end

          FUNCT3_SLTU: begin
            if (funct7 == FUNCT7_STANDARD) begin
              ctrl.alu_op = ALU_SLTU;
            end else begin
              ctrl.is_illegal = 1'b1;
            end
          end

          FUNCT3_XOR: begin
            if (funct7 == FUNCT7_STANDARD) begin
              ctrl.alu_op = ALU_XOR;
            end else begin
              ctrl.is_illegal = 1'b1;
            end
          end

          FUNCT3_SRL_SRA: begin
            if (funct7 == FUNCT7_STANDARD) begin
              ctrl.alu_op = ALU_SRL;
            end else if (funct7 == FUNCT7_ALT) begin
              ctrl.alu_op = ALU_SRA;
            end else begin
              ctrl.is_illegal = 1'b1;
            end
          end

          FUNCT3_OR: begin
            if (funct7 == FUNCT7_STANDARD) begin
              ctrl.alu_op = ALU_OR;
            end else begin
              ctrl.is_illegal = 1'b1;
            end
          end

          FUNCT3_AND: begin
            if (funct7 == FUNCT7_STANDARD) begin
              ctrl.alu_op = ALU_AND;
            end else begin
              ctrl.is_illegal = 1'b1;
            end
          end

          default: begin
            ctrl.is_illegal = 1'b1;
          end
        endcase
      end

      // ----------------------------------------------------------------------
      // I-type: Register-Immediate Arithmetic and Logical Instructions
      // ----------------------------------------------------------------------
      OPCODE_OP_IMM: begin
        ctrl.reg_write = 1'b1;
        ctrl.alu_src_a = ALU_SRC_A_RS1;
        ctrl.alu_src_b = ALU_SRC_B_IMM;
        ctrl.wb_sel    = WB_ALU;
        ctrl.imm_src   = IMM_I;

        case (funct3)
          FUNCT3_ADD_SUB: begin
            ctrl.alu_op = ALU_ADD; // ADDI
          end

          FUNCT3_SLL: begin
            // SLLI: funct7 must be standard (zeros)
            if (funct7 == FUNCT7_STANDARD) begin
              ctrl.alu_op = ALU_SLL;
            end else begin
              ctrl.is_illegal = 1'b1;
            end
          end

          FUNCT3_SLT: begin
            ctrl.alu_op = ALU_SLT; // SLTI
          end

          FUNCT3_SLTU: begin
            ctrl.alu_op = ALU_SLTU; // SLTIU
          end

          FUNCT3_XOR: begin
            ctrl.alu_op = ALU_XOR; // XORI
          end

          FUNCT3_SRL_SRA: begin
            // SRLI / SRAI: distinguished by bit 30 (funct7)
            if (funct7 == FUNCT7_STANDARD) begin
              ctrl.alu_op = ALU_SRL; // SRLI
            end else if (funct7 == FUNCT7_ALT) begin
              ctrl.alu_op = ALU_SRA; // SRAI
            end else begin
              ctrl.is_illegal = 1'b1;
            end
          end

          FUNCT3_OR: begin
            ctrl.alu_op = ALU_OR; // ORI
          end

          FUNCT3_AND: begin
            ctrl.alu_op = ALU_AND; // ANDI
          end

          default: begin
            ctrl.is_illegal = 1'b1;
          end
        endcase
      end

      // ----------------------------------------------------------------------
      // Load Instructions (LB, LH, LW, LBU, LHU)
      // ----------------------------------------------------------------------
      OPCODE_LOAD: begin
        ctrl.reg_write = 1'b1;
        ctrl.alu_src_a = ALU_SRC_A_RS1;
        ctrl.alu_src_b = ALU_SRC_B_IMM;
        ctrl.alu_op    = ALU_ADD; // Compute effective address: rs1 + offset
        ctrl.mem_read  = 1'b1;
        ctrl.wb_sel    = WB_MEM;
        ctrl.imm_src   = IMM_I;

        case (funct3)
          FUNCT3_LB:  ctrl.mem_op = MEM_OP_LB;
          FUNCT3_LH:  ctrl.mem_op = MEM_OP_LH;
          FUNCT3_LW:  ctrl.mem_op = MEM_OP_LW;
          FUNCT3_LBU: ctrl.mem_op = MEM_OP_LBU;
          FUNCT3_LHU: ctrl.mem_op = MEM_OP_LHU;
          default:    ctrl.is_illegal = 1'b1;
        endcase
      end

      // ----------------------------------------------------------------------
      // Store Instructions (SB, SH, SW)
      // ----------------------------------------------------------------------
      OPCODE_STORE: begin
        ctrl.reg_write = 1'b0;
        ctrl.alu_src_a = ALU_SRC_A_RS1;
        ctrl.alu_src_b = ALU_SRC_B_IMM;
        ctrl.alu_op    = ALU_ADD; // Compute effective address: rs1 + offset
        ctrl.mem_write = 1'b1;
        ctrl.imm_src   = IMM_S;

        case (funct3)
          FUNCT3_SB: ctrl.mem_op = MEM_OP_SB;
          FUNCT3_SH: ctrl.mem_op = MEM_OP_SH;
          FUNCT3_SW: ctrl.mem_op = MEM_OP_SW;
          default:   ctrl.is_illegal = 1'b1;
        endcase
      end

      // ----------------------------------------------------------------------
      // Conditional Branch Instructions (BEQ, BNE, BLT, BGE, BLTU, BGEU)
      // ----------------------------------------------------------------------
      OPCODE_BRANCH: begin
        ctrl.reg_write = 1'b0;
        ctrl.alu_src_a = ALU_SRC_A_RS1;
        ctrl.alu_src_b = ALU_SRC_B_RS2;
        ctrl.alu_op    = ALU_SUB;
        ctrl.imm_src   = IMM_B;

        case (funct3)
          FUNCT3_BEQ:  ctrl.branch_op = BRANCH_BEQ;
          FUNCT3_BNE:  ctrl.branch_op = BRANCH_BNE;
          FUNCT3_BLT:  ctrl.branch_op = BRANCH_BLT;
          FUNCT3_BGE:  ctrl.branch_op = BRANCH_BGE;
          FUNCT3_BLTU: ctrl.branch_op = BRANCH_BLTU;
          FUNCT3_BGEU: ctrl.branch_op = BRANCH_BGEU;
          default:     ctrl.is_illegal = 1'b1;
        endcase
      end

      // ----------------------------------------------------------------------
      // U-type: LUI (Load Upper Immediate)
      // ----------------------------------------------------------------------
      OPCODE_LUI: begin
        ctrl.reg_write = 1'b1;
        ctrl.alu_src_a = ALU_SRC_A_ZERO;
        ctrl.alu_src_b = ALU_SRC_B_IMM;
        ctrl.alu_op    = ALU_PASS_B;
        ctrl.wb_sel    = WB_IMM;
        ctrl.imm_src   = IMM_U;
      end

      // ----------------------------------------------------------------------
      // U-type: AUIPC (Add Upper Immediate to PC)
      // ----------------------------------------------------------------------
      OPCODE_AUIPC: begin
        ctrl.reg_write = 1'b1;
        ctrl.alu_src_a = ALU_SRC_A_PC;
        ctrl.alu_src_b = ALU_SRC_B_IMM;
        ctrl.alu_op    = ALU_ADD;
        ctrl.wb_sel    = WB_ALU;
        ctrl.imm_src   = IMM_U;
      end

      // ----------------------------------------------------------------------
      // J-type: JAL (Jump and Link)
      // ----------------------------------------------------------------------
      OPCODE_JAL: begin
        ctrl.reg_write = 1'b1;
        ctrl.alu_src_a = ALU_SRC_A_PC;
        ctrl.alu_src_b = ALU_SRC_B_FOUR;
        ctrl.alu_op    = ALU_ADD;
        ctrl.jump      = 1'b1;
        ctrl.wb_sel    = WB_PC4;
        ctrl.imm_src   = IMM_J;
      end

      // ----------------------------------------------------------------------
      // I-type: JALR (Jump and Link Register)
      // ----------------------------------------------------------------------
      OPCODE_JALR: begin
        if (funct3 == 3'b000) begin
          ctrl.reg_write = 1'b1;
          ctrl.alu_src_a = ALU_SRC_A_PC;
          ctrl.alu_src_b = ALU_SRC_B_FOUR;
          ctrl.alu_op    = ALU_ADD;
          ctrl.jump_reg  = 1'b1;
          ctrl.wb_sel    = WB_PC4;
          ctrl.imm_src   = IMM_I;
        end else begin
          ctrl.is_illegal = 1'b1;
        end
      end

      // ----------------------------------------------------------------------
      // FENCE: Memory Ordering Fence (handled as benign NOP)
      // ----------------------------------------------------------------------
      OPCODE_FENCE: begin
        ctrl.reg_write = 1'b0;
        ctrl.mem_read  = 1'b0;
        ctrl.mem_write = 1'b0;
        ctrl.imm_src   = IMM_I;
      end

      // ----------------------------------------------------------------------
      // SYSTEM: ECALL, EBREAK, CSR (handled as benign pass)
      // ----------------------------------------------------------------------
      OPCODE_SYSTEM: begin
        ctrl.reg_write = 1'b0;
        ctrl.mem_read  = 1'b0;
        ctrl.mem_write = 1'b0;
        ctrl.imm_src   = IMM_I;
      end

      // ----------------------------------------------------------------------
      // Default: Undefined opcode / illegal instruction
      // ----------------------------------------------------------------------
      default: begin
        ctrl.is_illegal = 1'b1;
        ctrl.reg_write  = 1'b0;
      end
    endcase
  end

endmodule : decoder

`endif // DECODER_SV
