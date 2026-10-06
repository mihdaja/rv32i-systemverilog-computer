# ============================================================================
# File: basic_math.s
# Description: RV32I ALU arithmetic, logical, shift, comparison and RAM test.
# Stores intermediate results to RAM (0x10000000).
# On completion:
#   Success: writes 0x00000001 to SIM_EXIT_ADDR (0x200000FC).
#   Failure: writes test failure code (0x000001xx) to SIM_EXIT_ADDR.
# ============================================================================

    .section .text.init, "ax", @progbits
    .globl _start

_start:
    # Set stack pointer to top of RAM
    li   sp, 0x10010000

    # Base address for RAM storage and simulation exit register
    li   s0, 0x10000000       # RAM base
    li   s1, 0x200000FC       # SIM_EXIT_ADDR

    # ------------------------------------------------------------------------
    # Test 1: ADDI and ADD
    # ------------------------------------------------------------------------
    addi t0, zero, 42         # t0 = 42
    addi t1, zero, 58         # t1 = 58
    add  t2, t0, t1           # t2 = 42 + 58 = 100
    sw   t2, 0(s0)            # RAM[0] = 100

    addi t3, zero, 100
    bne  t2, t3, fail_test1

    # ------------------------------------------------------------------------
    # Test 2: SUB
    # ------------------------------------------------------------------------
    sub  t4, t2, t0           # t4 = 100 - 42 = 58
    sw   t4, 4(s0)            # RAM[1] = 58
    bne  t4, t1, fail_test2

    # ------------------------------------------------------------------------
    # Test 3: AND / ANDI
    # ------------------------------------------------------------------------
    # 42 = 0x2A = 0b00101010
    # 15 = 0x0F = 0b00001111
    # 42 & 15 = 10 (0x0A)
    andi t5, t0, 15
    sw   t5, 8(s0)            # RAM[2] = 10
    addi t3, zero, 10
    bne  t5, t3, fail_test3

    and  t6, t0, t4           # 42 (0x2A) & 58 (0x3A) = 0x2A (42)
    bne  t6, t0, fail_test3_b

    # ------------------------------------------------------------------------
    # Test 4: OR / ORI
    # ------------------------------------------------------------------------
    # 0x55 | 0xAA = 0xFF (255)
    ori  a0, zero, 0x55
    ori  a1, zero, 0xAA
    or   a2, a0, a1
    sw   a2, 12(s0)           # RAM[3] = 0xFF
    addi t3, zero, 0xFF
    bne  a2, t3, fail_test4

    # ------------------------------------------------------------------------
    # Test 5: XOR / XORI
    # ------------------------------------------------------------------------
    xori a3, a0, 0xFF         # 0x55 ^ 0xFF = 0xAA
    sw   a3, 16(s0)           # RAM[4] = 0xAA
    bne  a3, a1, fail_test5

    xor  a4, a3, a1           # 0xAA ^ 0xAA = 0
    bne  a4, zero, fail_test5_b

    # ------------------------------------------------------------------------
    # Test 6: Shifts (SLL, SLLI, SRL, SRLI, SRA, SRAI)
    # ------------------------------------------------------------------------
    addi a5, zero, 1
    slli a6, a5, 10           # 1 << 10 = 1024
    sw   a6, 20(s0)           # RAM[5] = 1024
    addi t3, zero, 1024
    bne  a6, t3, fail_test6

    addi t0, zero, 10
    sll  a7, a5, t0           # 1 << 10 = 1024
    bne  a7, a6, fail_test6_b

    srli t1, a6, 5            # 1024 >> 5 = 32
    sw   t1, 24(s0)           # RAM[6] = 32
    addi t3, zero, 32
    bne  t1, t3, fail_test6_c

    # SRA: arithmetic shift with sign preservation
    addi t2, zero, -16        # 0xFFFFFFF0
    srai t3, t2, 2            # -16 >> 2 = -4 (0xFFFFFFFC)
    sw   t3, 28(s0)           # RAM[7] = -4
    addi t4, zero, -4
    bne  t3, t4, fail_test6_d

    # ------------------------------------------------------------------------
    # Test 7: Comparisons (SLT, SLTI, SLTU, SLTIU)
    # ------------------------------------------------------------------------
    addi t0, zero, -5
    addi t1, zero, 5
    slt  t2, t0, t1           # -5 < 5 (signed) => 1
    sw   t2, 32(s0)           # RAM[8] = 1
    addi t3, zero, 1
    bne  t2, t3, fail_test7

    sltu t4, t0, t1           # 0xFFFFFFFB < 5 (unsigned) => 0
    sw   t4, 36(s0)           # RAM[9] = 0
    bne  t4, zero, fail_test7_b

    # ------------------------------------------------------------------------
    # Test 8: RAM Load-back verification
    # ------------------------------------------------------------------------
    lw   t0, 0(s0)            # 100
    addi t1, zero, 100
    bne  t0, t1, fail_test8

    lw   t2, 12(s0)           # 255
    addi t3, zero, 255
    bne  t2, t3, fail_test8_b

    lw   t4, 28(s0)           # -4
    addi t5, zero, -4
    bne  t4, t5, fail_test8_c

    # ------------------------------------------------------------------------
    # All tests passed! Write 0x00000001 to SIM_EXIT_ADDR
    # ------------------------------------------------------------------------
pass:
    addi t0, zero, 1
    sw   t0, 0(s1)
spin_pass:
    j    spin_pass

# ----------------------------------------------------------------------------
# Failure handlers: write test code to SIM_EXIT_ADDR
# ----------------------------------------------------------------------------
fail_test1:
    li   t0, 0x00000101
    sw   t0, 0(s1)
1:  j    1b

fail_test2:
    li   t0, 0x00000102
    sw   t0, 0(s1)
1:  j    1b

fail_test3:
fail_test3_b:
    li   t0, 0x00000103
    sw   t0, 0(s1)
1:  j    1b

fail_test4:
    li   t0, 0x00000104
    sw   t0, 0(s1)
1:  j    1b

fail_test5:
fail_test5_b:
    li   t0, 0x00000105
    sw   t0, 0(s1)
1:  j    1b

fail_test6:
fail_test6_b:
fail_test6_c:
fail_test6_d:
    li   t0, 0x00000106
    sw   t0, 0(s1)
1:  j    1b

fail_test7:
fail_test7_b:
    li   t0, 0x00000107
    sw   t0, 0(s1)
1:  j    1b

fail_test8:
fail_test8_b:
fail_test8_c:
    li   t0, 0x00000108
    sw   t0, 0(s1)
1:  j    1b
