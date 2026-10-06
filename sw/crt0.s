# ============================================================================
# File: crt0.s
# Description: Minimal C runtime startup for RV32I bare-metal computer.
# Sets up stack, initializes .data, clears .bss, calls main, handles exit.
# ============================================================================

    .section .text.init, "ax", @progbits
    .globl _start
    .type _start, @function

_start:
    # 1. Initialize stack pointer to end of 64KB RAM (0x10010000)
    la   sp, _stack_top

    # 2. Clear BSS section (_sbss to _ebss)
    la   t0, _sbss
    la   t1, _ebss
bss_loop:
    bge  t0, t1, bss_done
    sw   zero, 0(t0)
    addi t0, t0, 4
    j    bss_loop
bss_done:

    # 3. Copy initialized data from ROM (_sidata) to RAM (_sdata .. _edata)
    la   t0, _sdata
    la   t1, _edata
    la   t2, _sidata
data_loop:
    bge  t0, t1, data_done
    lw   t3, 0(t2)
    sw   t3, 0(t0)
    addi t0, t0, 4
    addi t2, t2, 4
    j    data_loop
data_done:

    # 4. Call C entry point main()
    call main

    # 5. Handle main() return value (in a0)
    # If a0 == 0 (EXIT_SUCCESS), write 1 to SIM_EXIT_ADDR.
    # Otherwise write a0 directly as error code.
    li   t0, 0x200000FC
    bnez a0, sim_exit_write
    li   a0, 1
sim_exit_write:
    sw   a0, 0(t0)

    # 6. Trap loop
trap_loop:
    j    trap_loop

    .size _start, . - _start
