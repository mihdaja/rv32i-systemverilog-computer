# ============================================================================
# File: branch_test.s
# Description: RV32I branch condition evaluation and loop test.
# Tests:
#   - BEQ, BNE, BLT, BGE, BLTU, BGEU (both taken and not-taken branches)
#   - JAL and JALR subroutine linkage
#   - Loop counting from 1 to 10 (sum = 55)
#   - Nested loops calculating factorial(5) = 120 without hardware multiplier
# Stores results to RAM (0x10000000).
# On completion:
#   Success: writes 0x00000001 to SIM_EXIT_ADDR (0x200000FC).
#   Failure: writes test failure code (0x000002xx) to SIM_EXIT_ADDR.
# ============================================================================

    .section .text.init, "ax", @progbits
    .globl _start

_start:
    li   sp, 0x10010000
    li   s0, 0x10000000       # RAM base
    li   s1, 0x200000FC       # SIM_EXIT_ADDR

    # ------------------------------------------------------------------------
    # Test 1: BEQ (Taken and Not Taken)
    # ------------------------------------------------------------------------
    addi t0, zero, 17
    addi t1, zero, 17
    beq  t0, t1, beq_taken_ok
    j    fail_beq_taken
beq_taken_ok:

    addi t2, zero, 18
    beq  t0, t2, fail_beq_not_taken

    # ------------------------------------------------------------------------
    # Test 2: BNE (Taken and Not Taken)
    # ------------------------------------------------------------------------
    bne  t0, t2, bne_taken_ok
    j    fail_bne_taken
bne_taken_ok:

    bne  t0, t1, fail_bne_not_taken

    # ------------------------------------------------------------------------
    # Test 3: BLT and BGE (Signed Comparisons)
    # ------------------------------------------------------------------------
    addi t0, zero, -10        # Signed negative
    addi t1, zero, 10         # Signed positive

    # -10 < 10 (BLT taken)
    blt  t0, t1, blt_taken_ok
    j    fail_blt_taken
blt_taken_ok:

    # 10 < -10 (BLT not taken)
    blt  t1, t0, fail_blt_not_taken

    # 10 >= -10 (BGE taken)
    bge  t1, t0, bge_taken_ok
    j    fail_bge_taken
bge_taken_ok:

    # -10 >= 10 (BGE not taken)
    bge  t0, t1, fail_bge_not_taken

    # 10 >= 10 (BGE equal taken)
    bge  t1, t1, bge_equal_ok
    j    fail_bge_equal
bge_equal_ok:

    # ------------------------------------------------------------------------
    # Test 4: BLTU and BGEU (Unsigned Comparisons)
    # ------------------------------------------------------------------------
    # t0 = -10 (0xFFFFFFF6), t1 = 10 (0x0000000A)
    # Unsigned: 10 < 0xFFFFFFF6
    bltu t1, t0, bltu_taken_ok
    j    fail_bltu_taken
bltu_taken_ok:

    bltu t0, t1, fail_bltu_not_taken

    bgeu t0, t1, bgeu_taken_ok
    j    fail_bgeu_taken
bgeu_taken_ok:

    bgeu t1, t0, fail_bgeu_not_taken

    # ------------------------------------------------------------------------
    # Test 5: JAL and JALR subroutine calling
    # ------------------------------------------------------------------------
    addi a0, zero, 25
    jal  ra, square_subroutine
    # Expected result: a0 = 25 + 25 = 50
    addi t0, zero, 50
    bne  a0, t0, fail_jal_jalr

    # ------------------------------------------------------------------------
    # Test 6: Counting loop (Sum of 1 to 10 = 55)
    # ------------------------------------------------------------------------
    addi t0, zero, 1          # i = 1
    addi t1, zero, 10         # limit = 10
    addi t2, zero, 0          # sum = 0

loop_sum:
    add  t2, t2, t0           # sum += i
    addi t0, t0, 1           # i++
    ble  t0, t1, loop_sum     # if i <= limit continue

    sw   t2, 0(s0)            # Store sum to RAM[0]
    addi t3, zero, 55
    bne  t2, t3, fail_loop_sum

    # ------------------------------------------------------------------------
    # Test 7: Nested loops computing Factorial(5) = 120
    # ------------------------------------------------------------------------
    # Uses repeated addition to multiply on bare RV32I core
    addi a1, zero, 5          # N = 5
    addi a2, zero, 1          # result = 1
    addi t0, zero, 2          # i = 2 (multiplier)

fact_outer_loop:
    bgt  t0, a1, fact_done    # if i > N, done
    addi t1, zero, 0          # prod = 0
    addi t2, zero, 0          # counter = 0

fact_inner_loop:
    bge  t2, t0, fact_inner_done # if counter >= i, done inner
    add  t1, t1, a2           # prod += result
    addi t2, t2, 1           # counter++
    j    fact_inner_loop

fact_inner_done:
    add  a2, zero, t1         # result = prod
    addi t0, t0, 1           # i++
    j    fact_outer_loop

fact_done:
    sw   a2, 4(s0)            # Store factorial(5) to RAM[1]
    addi t4, zero, 120
    bne  a2, t4, fail_factorial

    # ------------------------------------------------------------------------
    # All branch and loop tests passed!
    # ------------------------------------------------------------------------
pass:
    addi t0, zero, 1
    sw   t0, 0(s1)
spin_pass:
    j    spin_pass

# ----------------------------------------------------------------------------
# Subroutine: adds a0 to itself
# ----------------------------------------------------------------------------
square_subroutine:
    add  a0, a0, a0
    jalr zero, 0(ra)

# ----------------------------------------------------------------------------
# Failure handlers
# ----------------------------------------------------------------------------
fail_beq_taken:
    li   t0, 0x00000201
    sw   t0, 0(s1)
1:  j    1b

fail_beq_not_taken:
    li   t0, 0x00000202
    sw   t0, 0(s1)
1:  j    1b

fail_bne_taken:
    li   t0, 0x00000203
    sw   t0, 0(s1)
1:  j    1b

fail_bne_not_taken:
    li   t0, 0x00000204
    sw   t0, 0(s1)
1:  j    1b

fail_blt_taken:
fail_blt_not_taken:
    li   t0, 0x00000205
    sw   t0, 0(s1)
1:  j    1b

fail_bge_taken:
fail_bge_not_taken:
fail_bge_equal:
    li   t0, 0x00000206
    sw   t0, 0(s1)
1:  j    1b

fail_bltu_taken:
fail_bltu_not_taken:
    li   t0, 0x00000207
    sw   t0, 0(s1)
1:  j    1b

fail_bgeu_taken:
fail_bgeu_not_taken:
    li   t0, 0x00000208
    sw   t0, 0(s1)
1:  j    1b

fail_jal_jalr:
    li   t0, 0x00000209
    sw   t0, 0(s1)
1:  j    1b

fail_loop_sum:
    li   t0, 0x0000020A
    sw   t0, 0(s1)
1:  j    1b

fail_factorial:
    li   t0, 0x0000020B
    sw   t0, 0(s1)
1:  j    1b
