# ============================================================================
# File: terminal_echo.s
# Description: Interactive terminal echo test for RV32I Computer.
# Reads keystrokes from UART RX, echoes them with ASCII hex code,
# and exits on 'q' or ESC.
# ============================================================================

    .section .text.init, "ax", @progbits
    .globl _start

_start:
    li   sp, 0x10010000
    li   s0, 0x20000000       # UART_REG_TXDATA / RXDATA
    li   s1, 0x20000004       # UART_REG_STATUS

    # Print welcome banner
    la   a0, msg_banner
    jal  ra, uart_puts

main_loop:
    # Check if RX character is available (bit 1 of STATUS)
    lw   t0, 0(s1)
    andi t0, t0, 2
    beqz t0, main_loop

    # Read the received byte
    lw   s2, 0(s0)
    andi s2, s2, 0xFF

    # Check for 'q' (0x71)
    li   t1, 0x71
    beq  s2, t1, exit_clean

    # Check for ESC (0x1B)
    li   t1, 0x1B
    beq  s2, t1, exit_clean

    # Check for Enter '\r' (0x0D) or '\n' (0x0A)
    li   t1, 0x0D
    beq  s2, t1, handle_enter
    li   t1, 0x0A
    beq  s2, t1, handle_enter

    # Echo character details: " -> Key: '<char>' [ASCII 0x<HEX>]\r\nType something: "
    la   a0, msg_echo_start
    jal  ra, uart_puts

    mv   a0, s2
    jal  ra, uart_putc

    la   a0, msg_echo_mid
    jal  ra, uart_puts

    mv   a0, s2
    jal  ra, uart_puthex8

    la   a0, msg_echo_end
    jal  ra, uart_puts

    j    main_loop

handle_enter:
    la   a0, msg_newline_prompt
    jal  ra, uart_puts
    j    main_loop

exit_clean:
    la   a0, msg_exit
    jal  ra, uart_puts

    # Simulation exit with code 1
    li   t0, 0x200000FC
    li   t1, 1
    sw   t1, 0(t0)

trap:
    j    trap

# ----------------------------------------------------------------------------
# Subroutines
# ----------------------------------------------------------------------------
uart_putc:
    li   t1, 0x20000004
putc_wait:
    lw   t2, 0(t1)
    andi t2, t2, 1
    beqz t2, putc_wait
    li   t0, 0x20000000
    sw   a0, 0(t0)
    jalr zero, 0(ra)

uart_puts:
    addi sp, sp, -8
    sw   ra, 4(sp)
    sw   s3, 0(sp)
    mv   s3, a0
puts_loop:
    lbu  a0, 0(s3)
    beqz a0, puts_done
    jal  ra, uart_putc
    addi s3, s3, 1
    j    puts_loop
puts_done:
    lw   s3, 0(sp)
    lw   ra, 4(sp)
    addi sp, sp, 8
    jalr zero, 0(ra)

uart_puthex8:
    addi sp, sp, -8
    sw   ra, 4(sp)
    sw   s4, 0(sp)
    mv   s4, a0

    # High nibble
    srli a0, s4, 4
    andi a0, a0, 0xF
    jal  ra, nibble_to_ascii
    jal  ra, uart_putc

    # Low nibble
    andi a0, s4, 0xF
    jal  ra, nibble_to_ascii
    jal  ra, uart_putc

    lw   s4, 0(sp)
    lw   ra, 4(sp)
    addi sp, sp, 8
    jalr zero, 0(ra)

nibble_to_ascii:
    li   t3, 10
    blt  a0, t3, hex_digit
    addi a0, a0, 55           # 'A' - 10
    jalr zero, 0(ra)
hex_digit:
    addi a0, a0, 48           # '0'
    jalr zero, 0(ra)

# ----------------------------------------------------------------------------
# String Constants
# ----------------------------------------------------------------------------
    .section .rodata
msg_banner:
    .string "\r\n============================================================\r\n       RV32I SystemVerilog Computer: Live Terminal\r\n============================================================\r\n Connection verified!\r\n Type characters on your Mac terminal to test the link.\r\n The RISC-V CPU will echo your keys back with hex codes.\r\n Press 'q' or ESC to exit cleanly.\r\n============================================================\r\n\r\nType something: "

msg_echo_start:
    .string " -> Key: '"

msg_echo_mid:
    .string "' [ASCII 0x"

msg_echo_end:
    .string "]\r\nType something: "

msg_newline_prompt:
    .string "\r\n[ENTER pressed]\r\nType something: "

msg_exit:
    .string "\r\n\r\nExiting test. Goodbye!\r\n"
