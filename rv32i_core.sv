// ============================================================================
// File: rv32i_core.sv
// Description: Multi-cycle RV32I processor core integrating fetch, decode,
//              execute, and memory stages with a single system bus master interface.
// ============================================================================

`timescale 1ns / 1ps

`ifndef RV32I_CORE_SV
`define RV32I_CORE_SV

`include "rv32i_pkg.sv"

`ifdef USE_BUS_IF
module rv32i_core
  import rv32i_pkg::*;
(
  bus_if.master bus
);
  wire        clk       = bus.clk;
  wire        rst_n     = bus.rst_n;
  logic [31:0] bus_addr;
  logic [31:0] bus_wdata;
  logic [3:0]  bus_wstrb;
  logic        bus_valid;
  wire  [31:0] bus_rdata = bus.rdata;
  wire         bus_ready = bus.ready;

  assign bus.addr  = bus_addr;
  assign bus.wdata = bus_wdata;
  assign bus.wstrb = bus_wstrb;
  assign bus.valid = bus_valid;

`else
module rv32i_core
  import rv32i_pkg::*;
(
  input  logic        clk,
  input  logic        rst_n,
  output logic [31:0] bus_addr,
  output logic [31:0] bus_wdata,
  output logic [3:0]  bus_wstrb,
  output logic        bus_valid,
  input  logic [31:0] bus_rdata,
  input  logic        bus_ready
);
`endif

  // --------------------------------------------------------------------------
  // Core FSM State Definitions
  // --------------------------------------------------------------------------
  typedef enum logic [1:0] {
    S_FETCH = 2'b00,
    S_EXEC  = 2'b01,
    S_MEM   = 2'b10
  } state_e;

  state_e state, next_state;

  // Pipeline handshake guard: prevents accepting leftover ready on cycle 0 of S_FETCH
  logic fetch_wait;

  // --------------------------------------------------------------------------
  // Internal Registers & Signals
  // --------------------------------------------------------------------------
  logic [31:0] inst_reg;

  // Program Counter signals
  logic        pc_en;
  logic [31:0] next_pc;
  logic [31:0] pc;
  logic [31:0] pc_plus_4;

  // Decoder signals
  opcode_e       opcode;
  logic [4:0]    rd;
  logic [2:0]    funct3;
  logic [4:0]    rs1;
  logic [4:0]    rs2;
  logic [6:0]    funct7;
  ctrl_signals_t ctrl;

  // Discrete control wires (ensures clean synthesis and quiet elaboration)
  wire alu_src_a_e ctrl_alu_src_a = ctrl.alu_src_a;
  wire alu_src_b_e ctrl_alu_src_b = ctrl.alu_src_b;
  wire alu_op_e    ctrl_alu_op    = ctrl.alu_op;
  wire branch_op_e ctrl_branch_op = ctrl.branch_op;
  wire wb_sel_e    ctrl_wb_sel    = ctrl.wb_sel;
  wire mem_op_e    ctrl_mem_op    = ctrl.mem_op;
  wire             ctrl_reg_write = ctrl.reg_write;
  wire             ctrl_mem_read  = ctrl.mem_read;
  wire             ctrl_mem_write = ctrl.mem_write;
  wire             ctrl_jump      = ctrl.jump;
  wire             ctrl_jump_reg  = ctrl.jump_reg;
  wire imm_src_e   ctrl_imm_src   = ctrl.imm_src;

  // Immediate generator signals
  logic [31:0] imm;

  // Register file signals
  logic        rf_we;
  logic [31:0] rf_wdata;
  logic [31:0] rs1_data;
  logic [31:0] rs2_data;

  // ALU signals
  logic [31:0] alu_in_a;
  logic [31:0] alu_in_b;
  logic [31:0] alu_result;
  logic        alu_zero;

  // Branch evaluation signal
  logic        branch_taken;

  // LSU signals
  logic [31:0] lsu_reg_rdata;
  logic [31:0] lsu_bus_wdata;
  logic [3:0]  lsu_bus_wstrb;

  // Memory instruction helper
  wire is_mem = ctrl_mem_read | ctrl_mem_write;

  // --------------------------------------------------------------------------
  // Program Counter Register
  // --------------------------------------------------------------------------
  pc_reg u_pc_reg (
    .clk     (clk),
    .rst_n   (rst_n),
    .en      (pc_en),
    .next_pc (next_pc),
    .pc      (pc)
  );

  // --------------------------------------------------------------------------
  // Next Program Counter Generator
  // --------------------------------------------------------------------------
  next_pc_gen u_next_pc_gen (
    .pc           (pc),
    .imm          (imm),
    .rs1_data     (rs1_data),
    .branch_taken (branch_taken),
    .jump         (ctrl_jump),
    .jump_reg     (ctrl_jump_reg),
    .next_pc      (next_pc),
    .pc_plus_4    (pc_plus_4)
  );

  // --------------------------------------------------------------------------
  // Instruction Decoder
  // --------------------------------------------------------------------------
  decoder u_decoder (
    .inst   (inst_reg),
    .opcode (opcode),
    .rd     (rd),
    .funct3 (funct3),
    .rs1    (rs1),
    .rs2    (rs2),
    .funct7 (funct7),
    .ctrl   (ctrl)
  );

  // --------------------------------------------------------------------------
  // Immediate Generator
  // --------------------------------------------------------------------------
  imm_gen u_imm_gen (
    .inst    (inst_reg),
    .imm_src (ctrl_imm_src),
    .imm     (imm)
  );

  // --------------------------------------------------------------------------
  // Register File
  // --------------------------------------------------------------------------
  reg_file u_reg_file (
    .clk    (clk),
    .rst_n  (rst_n),
    .we     (rf_we),
    .waddr  (rd),
    .wdata  (rf_wdata),
    .raddr1 (rs1),
    .raddr2 (rs2),
    .rdata1 (rs1_data),
    .rdata2 (rs2_data)
  );

  // --------------------------------------------------------------------------
  // Branch Condition Evaluation
  // --------------------------------------------------------------------------
  always_comb begin
    case (ctrl_branch_op)
      BRANCH_BEQ:  branch_taken = (rs1_data == rs2_data);
      BRANCH_BNE:  branch_taken = (rs1_data != rs2_data);
      BRANCH_BLT:  branch_taken = ($signed(rs1_data) < $signed(rs2_data));
      BRANCH_BGE:  branch_taken = ($signed(rs1_data) >= $signed(rs2_data));
      BRANCH_BLTU: branch_taken = (rs1_data < rs2_data);
      BRANCH_BGEU: branch_taken = (rs1_data >= rs2_data);
      default:     branch_taken = 1'b0;
    endcase
  end

  // --------------------------------------------------------------------------
  // ALU Operand Multiplexers & ALU
  // --------------------------------------------------------------------------
  always_comb begin
    case (ctrl_alu_src_a)
      ALU_SRC_A_RS1:  alu_in_a = rs1_data;
      ALU_SRC_A_PC:   alu_in_a = pc;
      ALU_SRC_A_ZERO: alu_in_a = 32'd0;
      default:        alu_in_a = rs1_data;
    endcase
  end

  always_comb begin
    case (ctrl_alu_src_b)
      ALU_SRC_B_RS2:  alu_in_b = rs2_data;
      ALU_SRC_B_IMM:  alu_in_b = imm;
      ALU_SRC_B_FOUR: alu_in_b = 32'd4;
      default:        alu_in_b = rs2_data;
    endcase
  end

  alu u_alu (
    .a      (alu_in_a),
    .b      (alu_in_b),
    .alu_op (ctrl_alu_op),
    .result (alu_result),
    .zero   (alu_zero)
  );

  // --------------------------------------------------------------------------
  // Load/Store Unit (LSU)
  // --------------------------------------------------------------------------
  lsu u_lsu (
    .mem_op    (ctrl_mem_op),
    .addr      (alu_result),
    .reg_wdata (rs2_data),
    .bus_rdata (bus_rdata),
    .reg_rdata (lsu_reg_rdata),
    .bus_wdata (lsu_bus_wdata),
    .bus_wstrb (lsu_bus_wstrb)
  );

  // --------------------------------------------------------------------------
  // Writeback Data Selection
  // --------------------------------------------------------------------------
  always_comb begin
    case (ctrl_wb_sel)
      WB_ALU:  rf_wdata = alu_result;
      WB_MEM:  rf_wdata = lsu_reg_rdata;
      WB_PC4:  rf_wdata = pc_plus_4;
      WB_IMM:  rf_wdata = imm;
      default: rf_wdata = alu_result;
    endcase
  end

  // --------------------------------------------------------------------------
  // Execution FSM: Sequential State Register & Instruction Latch
  // --------------------------------------------------------------------------
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state      <= S_FETCH;
      fetch_wait <= 1'b1;
      inst_reg   <= 32'h0000_0013; // NOP (addi x0, x0, 0)
    end else begin
      state <= next_state;

      // Track fetch entry to ensure at least 1 cycle for memory latency
      if (state != S_FETCH) begin
        fetch_wait <= 1'b1;
      end else begin
        fetch_wait <= 1'b0;
      end

      // Latch fetched instruction only after new PC request has been sampled
      if (state == S_FETCH && bus_ready && !fetch_wait) begin
        inst_reg <= bus_rdata;
      end
    end
  end

  // --------------------------------------------------------------------------
  // Execution FSM: Next-State Combinational Logic
  // --------------------------------------------------------------------------
  always_comb begin
    next_state = state;
    case (state)
      S_FETCH: begin
        if (bus_ready && !fetch_wait) begin
          next_state = S_EXEC;
        end
      end

      S_EXEC: begin
        if (is_mem) begin
          next_state = S_MEM;
        end else begin
          next_state = S_FETCH;
        end
      end

      S_MEM: begin
        if (bus_ready) begin
          next_state = S_FETCH;
        end
      end

      default: next_state = S_FETCH;
    endcase
  end

  // --------------------------------------------------------------------------
  // Execution FSM: Bus & Datapath Control Outputs
  // --------------------------------------------------------------------------
  always_comb begin
    // Default inactive signals
    bus_addr  = 32'd0;
    bus_wdata = 32'd0;
    bus_wstrb = 4'b0000;
    bus_valid = 1'b0;
    pc_en     = 1'b0;
    rf_we     = 1'b0;

    case (state)
      S_FETCH: begin
        bus_addr  = pc;
        bus_valid = 1'b1;
        bus_wdata = 32'd0;
        bus_wstrb = 4'b0000;
        pc_en     = 1'b0;
        rf_we     = 1'b0;
      end

      S_EXEC: begin
        bus_addr  = 32'd0;
        bus_valid = 1'b0;
        bus_wdata = 32'd0;
        bus_wstrb = 4'b0000;
        if (!is_mem) begin
          rf_we = ctrl_reg_write;
          pc_en = 1'b1;
        end else begin
          rf_we = 1'b0;
          pc_en = 1'b0;
        end
      end

      S_MEM: begin
        bus_addr  = alu_result;
        bus_wdata = lsu_bus_wdata;
        bus_wstrb = ctrl_mem_write ? lsu_bus_wstrb : 4'b0000;
        bus_valid = 1'b1;
        if (bus_ready) begin
          rf_we = ctrl_reg_write;
          pc_en = 1'b1;
        end else begin
          rf_we = 1'b0;
          pc_en = 1'b0;
        end
      end

      default: begin
        bus_addr  = 32'd0;
        bus_wdata = 32'd0;
        bus_wstrb = 4'b0000;
        bus_valid = 1'b0;
        pc_en     = 1'b0;
        rf_we     = 1'b0;
      end
    endcase
  end

endmodule : rv32i_core

`endif // RV32I_CORE_SV
