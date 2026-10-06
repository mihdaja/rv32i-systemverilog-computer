# ============================================================================
# File: hello_uart.s
# Description: RV32I UART transmission test in pure assembly.
# Transmits "Hello, RV32I SystemVerilog Computer!\n" over memory-mapped UART.
# On completion writes 0x00000001 to SIM_EXIT_ADDR (0x200000FC).
# ============================================================================

    .section .text.init, "ax", @progbits
    .globl _start

_start:
    li   sp, 0x10010000
    la   a0, msg
    jal  ra, uart_puts

    # Exit with code 1
    li   t0, 0x200000FC
    li   t1, 1
    sw   t1, 0(t0)

trap:
    j    trap

# ----------------------------------------------------------------------------
# Subroutine: uart_puts
# Input: a0 = pointer to null-terminated ASCII string
# Clobbers: t0, t1, t2, t3, a0
# ----------------------------------------------------------------------------
uart_puts:
    li   t0, 0x20000000       # UART_REG_TXDATA
    li   t1, 0x20000004       # UART_REG_STATUS
puts_loop:
    lbu  t2, 0(a0)
    beqz t2, puts_done
wait_tx_ready:
    lw   t3, 0(t1)
    andi t3, t3, 1            # Bit 0 = TX ready flag
    beqz t3, wait_tx_ready
    sw   t2, 0(t0)            # Transmit character
    addi a0, a0, 1
    j    puts_loop
puts_done:
    jalr zero, 0(ra)

    .section .rodata
msg:
    .string "Hello, RV32I SystemVerilog Computer!\n"
