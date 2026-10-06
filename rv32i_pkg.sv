`ifndef RV32I_PKG_SV
`define RV32I_PKG_SV

// ============================================================================
// File: rv32i_pkg.sv
// Description: Shared package and bus interface for RV32I processor and SoC.
//              Contains architectural parameters, opcode definitions, control
//              structures, memory map constants, and bus interface contracts.
// ============================================================================

package rv32i_pkg;

  // --------------------------------------------------------------------------
  // Architectural Parameters
  // --------------------------------------------------------------------------
  localparam int unsigned XLEN          = 32;
  localparam int unsigned RF_ADDR_WIDTH = 5;
  localparam int unsigned RF_NUM_REGS   = 32;
  localparam logic [31:0] RESET_VECTOR  = 32'h0000_0000;

  // --------------------------------------------------------------------------
  // RISC-V RV32I Base Opcodes (inst[6:0])
  // --------------------------------------------------------------------------
  typedef enum logic [6:0] {
    OPCODE_OP       = 7'b011_0011, // R-type ALU: ADD, SUB, SLL, SLT, SLTU, XOR, SRL, SRA, OR, AND
    OPCODE_OP_IMM   = 7'b001_0011, // I-type ALU: ADDI, SLTI, SLTIU, XORI, ORI, ANDI, SLLI, SRLI, SRAI
    OPCODE_LOAD     = 7'b000_0011, // I-type Load: LB, LH, LW, LBU, LHU
    OPCODE_STORE    = 7'b010_0011, // S-type Store: SB, SH, SW
    OPCODE_BRANCH   = 7'b110_0011, // B-type Branch: BEQ, BNE, BLT, BGE, BLTU, BGEU
    OPCODE_JAL      = 7'b110_1111, // J-type Jump: JAL
    OPCODE_JALR     = 7'b110_0111, // I-type Jump: JALR
    OPCODE_LUI      = 7'b011_0111, // U-type: Load Upper Immediate
    OPCODE_AUIPC    = 7'b001_0111, // U-type: Add Upper Immediate to PC
    OPCODE_SYSTEM   = 7'b111_0011, // System: ECALL, EBREAK, CSR
    OPCODE_FENCE    = 7'b000_1111  // Memory ordering fence
  } opcode_e;

  // --------------------------------------------------------------------------
  // Funct3 Field Encodings
  // --------------------------------------------------------------------------

  // ALU funct3 (R-type and I-type)
  localparam logic [2:0] FUNCT3_ADD_SUB = 3'b000;
  localparam logic [2:0] FUNCT3_SLL     = 3'b001;
  localparam logic [2:0] FUNCT3_SLT     = 3'b010;
  localparam logic [2:0] FUNCT3_SLTU    = 3'b011;
  localparam logic [2:0] FUNCT3_XOR     = 3'b100;
  localparam logic [2:0] FUNCT3_SRL_SRA = 3'b101;
  localparam logic [2:0] FUNCT3_OR      = 3'b110;
  localparam logic [2:0] FUNCT3_AND     = 3'b111;

  // Branch funct3
  localparam logic [2:0] FUNCT3_BEQ     = 3'b000;
  localparam logic [2:0] FUNCT3_BNE     = 3'b001;
  localparam logic [2:0] FUNCT3_BLT     = 3'b100;
  localparam logic [2:0] FUNCT3_BGE     = 3'b101;
  localparam logic [2:0] FUNCT3_BLTU    = 3'b110;
  localparam logic [2:0] FUNCT3_BGEU    = 3'b111;

  // Load funct3
  localparam logic [2:0] FUNCT3_LB      = 3'b000;
  localparam logic [2:0] FUNCT3_LH      = 3'b001;
  localparam logic [2:0] FUNCT3_LW      = 3'b010;
  localparam logic [2:0] FUNCT3_LBU     = 3'b100;
  localparam logic [2:0] FUNCT3_LHU     = 3'b101;

  // Store funct3
  localparam logic [2:0] FUNCT3_SB      = 3'b000;
  localparam logic [2:0] FUNCT3_SH      = 3'b001;
  localparam logic [2:0] FUNCT3_SW      = 3'b010;

  // Funct7 Field Encodings
  localparam logic [6:0] FUNCT7_STANDARD = 7'b000_0000;
  localparam logic [6:0] FUNCT7_ALT      = 7'b010_0000; // SUB, SRA

  // --------------------------------------------------------------------------
  // Datapath & Control Enumerations
  // --------------------------------------------------------------------------

  // ALU Operation selector
  typedef enum logic [3:0] {
    ALU_ADD    = 4'b0000,
    ALU_SUB    = 4'b0001,
    ALU_SLL    = 4'b0010,
    ALU_SLT    = 4'b0011,
    ALU_SLTU   = 4'b0100,
    ALU_XOR    = 4'b0101,
    ALU_SRL    = 4'b0110,
    ALU_SRA    = 4'b0111,
    ALU_OR     = 4'b1000,
    ALU_AND    = 4'b1001,
    ALU_PASS_B = 4'b1010
  } alu_op_e;

  // Immediate generation source format
  typedef enum logic [2:0] {
    IMM_I = 3'b000, // I-type: 12-bit signed immediate (loads, ALU imm, jalr)
    IMM_S = 3'b001, // S-type: 12-bit signed immediate (stores)
    IMM_B = 3'b010, // B-type: 13-bit signed branch target offset
    IMM_U = 3'b011, // U-type: 20-bit upper immediate (lui, auipc)
    IMM_J = 3'b100  // J-type: 21-bit signed jump target offset (jal)
  } imm_src_e;

  // Branch condition evaluation type
  typedef enum logic [2:0] {
    BRANCH_NONE = 3'b000,
    BRANCH_BEQ  = 3'b001,
    BRANCH_BNE  = 3'b010,
    BRANCH_BLT  = 3'b011,
    BRANCH_BGE  = 3'b100,
    BRANCH_BLTU = 3'b101,
    BRANCH_BGEU = 3'b110
  } branch_op_e;

  // ALU input source A selector
  typedef enum logic [1:0] {
    ALU_SRC_A_RS1  = 2'b00,
    ALU_SRC_A_PC   = 2'b01,
    ALU_SRC_A_ZERO = 2'b10
  } alu_src_a_e;

  // ALU input source B selector
  typedef enum logic [1:0] {
    ALU_SRC_B_RS2  = 2'b00,
    ALU_SRC_B_IMM  = 2'b01,
    ALU_SRC_B_FOUR = 2'b10
  } alu_src_b_e;

  // Register writeback source selector
  typedef enum logic [1:0] {
    WB_ALU = 2'b00, // ALU computation result
    WB_MEM = 2'b01, // Memory read data from LSU
    WB_PC4 = 2'b10, // PC + 4 link address (jal, jalr)
    WB_IMM = 2'b11  // Immediate value (direct lui bypass)
  } wb_sel_e;

  // Memory access size & sign extension for LSU
  typedef enum logic [2:0] {
    MEM_OP_LB  = 3'b000, // 8-bit sign-extended load
    MEM_OP_LH  = 3'b001, // 16-bit sign-extended load
    MEM_OP_LW  = 3'b010, // 32-bit load
    MEM_OP_LBU = 3'b100, // 8-bit zero-extended load
    MEM_OP_LHU = 3'b101, // 16-bit zero-extended load
    MEM_OP_SB  = 3'b011, // 8-bit store
    MEM_OP_SH  = 3'b110, // 16-bit store
    MEM_OP_SW  = 3'b111  // 32-bit store
  } mem_op_e;

  // --------------------------------------------------------------------------
  // Control Word Structure
  // --------------------------------------------------------------------------
  typedef struct packed {
    logic       reg_write;   // Register file write enable
    alu_src_a_e alu_src_a;   // ALU operand A mux selector
    alu_src_b_e alu_src_b;   // ALU operand B mux selector
    alu_op_e    alu_op;      // ALU operation code
    logic       mem_read;    // Data memory read enable
    logic       mem_write;   // Data memory write enable
    mem_op_e    mem_op;      // Memory access type (size / sign extension)
    branch_op_e branch_op;   // Branch evaluation mode
    logic       jump;        // Unconditional jump (jal)
    logic       jump_reg;    // Indirect jump (jalr)
    wb_sel_e    wb_sel;      // Writeback destination mux selector
    imm_src_e   imm_src;     // Immediate generator extraction format
    logic       is_illegal;  // Undefined opcode or unsupported instruction flag
  } ctrl_signals_t;

  // --------------------------------------------------------------------------
  // Interconnect Bus Packet Definitions
  // --------------------------------------------------------------------------

  // Bus request packet (Master -> Slave)
  typedef struct packed {
    logic [31:0] addr;   // Byte address
    logic [31:0] wdata;  // Write data
    logic [3:0]  wstrb;  // Active-high byte write strobe mask
    logic        valid;  // Request valid strobe
  } bus_req_t;

  // Bus response packet (Slave -> Master)
  typedef struct packed {
    logic [31:0] rdata;  // Read data
    logic        ready;  // Slave acknowledge / completion strobe
  } bus_resp_t;

  // --------------------------------------------------------------------------
  // Memory Map Constants
  // --------------------------------------------------------------------------

  // Boot ROM (16 KB, read-only)
  localparam logic [31:0] ROM_BASE   = 32'h0000_0000;
  localparam logic [31:0] ROM_SIZE   = 32'h0000_4000;
  localparam logic [31:0] ROM_END    = ROM_BASE + ROM_SIZE - 1; // 0x0000_3FFF

  // Main SRAM (64 KB, read/write)
  localparam logic [31:0] RAM_BASE   = 32'h1000_0000;
  localparam logic [31:0] RAM_SIZE   = 32'h0001_0000;
  localparam logic [31:0] RAM_END    = RAM_BASE + RAM_SIZE - 1; // 0x1000_FFFF

  // UART Peripheral (16 B, read/write)
  localparam logic [31:0] UART_BASE  = 32'h2000_0000;
  localparam logic [31:0] UART_SIZE  = 32'h0000_0010;
  localparam logic [31:0] UART_END   = UART_BASE + UART_SIZE - 1; // 0x2000_000F

  // UART Register Offsets & Absolute Addresses
  localparam logic [31:0] UART_REG_TXDATA  = 32'h2000_0000; // W: TX byte
  localparam logic [31:0] UART_REG_STATUS  = 32'h2000_0004; // R: Bit 0 = TX ready
  localparam logic [31:0] UART_REG_RXDATA  = 32'h2000_0008; // R: RX byte

  // Hardware Timer (16 B, read/write)
  localparam logic [31:0] TIMER_BASE = 32'h2000_0010;
  localparam logic [31:0] TIMER_SIZE = 32'h0000_0010;
  localparam logic [31:0] TIMER_END  = TIMER_BASE + TIMER_SIZE - 1; // 0x2000_001F

  // Timer Register Offsets & Absolute Addresses
  localparam logic [31:0] TIMER_REG_MTIME_L    = 32'h2000_0010; // 64-bit cycle counter low
  localparam logic [31:0] TIMER_REG_MTIME_H    = 32'h2000_0014; // 64-bit cycle counter high
  localparam logic [31:0] TIMER_REG_MTIMECMP_L = 32'h2000_0018; // Compare register low
  localparam logic [31:0] TIMER_REG_MTIMECMP_H = 32'h2000_001C; // Compare register high

  // Simulation Trap / Exit Register
  localparam logic [31:0] SIM_EXIT_ADDR        = 32'h2000_00FC;

endpackage : rv32i_pkg

// ============================================================================
// System Bus Interface Definition
// ============================================================================
interface bus_if (
  input logic clk,
  input logic rst_n
);
  logic [31:0] addr;
  logic [31:0] wdata;
  logic [31:0] rdata;
  logic [3:0]  wstrb;
  logic        valid;
  logic        ready;

  // Master port (CPU Core / DMA)
  modport master (
    input  clk,
    input  rst_n,
    input  rdata,
    input  ready,
    output addr,
    output wdata,
    output wstrb,
    output valid
  );

  // Slave port (ROM, RAM, Peripherals)
  modport slave (
    input  clk,
    input  rst_n,
    input  addr,
    input  wdata,
    input  wstrb,
    input  valid,
    output rdata,
    output ready
  );

  // Passive Monitor port (Verification testbenches / debuggers)
  modport monitor (
    input clk,
    input rst_n,
    input addr,
    input wdata,
    input rdata,
    input wstrb,
    input valid,
    input ready
  );

endinterface : bus_if

`endif // RV32I_PKG_SV
