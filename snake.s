# ==============================================================================
# RISC-V Bare-Metal Snake for SystemVerilog RV32I SoC
# ==============================================================================
# Grid: 32 columns x 16 rows
# Border: Rows 1 and 16 are horizontal walls ("+------------------------------+")
#         Cols 1 and 32 are vertical walls ("|")
# Playable area: Col 2..31 (X: 2..31), Row 2..15 (Y: 2..15)
# Controls:
#   W / w: Up
#   S / s: Down
#   A / a: Left
#   D / d: Right
#   Q / q: Quit
# High FPS: Dirty-rect rendering (only moves cursor to erase tail and draw head)
# ==============================================================================

.equ UART_BASE,       0x20000000
.equ UART_DATA,       0
.equ UART_STATUS,     4
.equ SIM_EXIT,        0xFC

# RAM Storage Offsets (Base: 0x10000000)
.equ RAM_BASE,        0x10000000
.equ SNAKE_X_BUF,     0x10000000    # 512 bytes for X coords
.equ SNAKE_Y_BUF,     0x10000200    # 512 bytes for Y coords

# Direction constants: 0=UP, 1=RIGHT, 2=DOWN, 3=LEFT
.equ DIR_UP,          0
.equ DIR_RIGHT,       1
.equ DIR_DOWN,        2
.equ DIR_LEFT,        3

# Register allocations:
#   s0:  UART Base (0x20000000)
#   s1:  Current Direction (0=UP, 1=RIGHT, 2=DOWN, 3=LEFT)
#   s2:  Next Direction (queued from input)
#   s3:  Head index in circular buffer (0..511)
#   s4:  Tail index in circular buffer (0..511)
#   s5:  Score (number of apples eaten)
#   s6:  LFSR random state
#   s7:  Food X (2..31)
#   s8:  Food Y (2..15)
#   s9:  Snake length (starts at 4)
#   s10: RAM Base (0x10000000)

.section .text
.globl _start

_start:
    # Initialize Stack Pointer to top of SRAM
    li sp, 0x10010000

    # Base pointers
    li s0, UART_BASE
    li s10, RAM_BASE

    # Initialize LFSR seed
    li s6, 0x9A5C

restart_game:
    # Reset game state
    li s1, DIR_RIGHT         # Current direction: RIGHT
    li s2, DIR_RIGHT         # Queued direction: RIGHT
    li s5, 0                 # Score: 0
    li s9, 4                 # Initial length: 4 segments

    # Clear screen and reset cursor
    la a0, str_clear
    jal ra, print_string

    # Draw border and title
    jal ra, draw_arena

    # Initialize snake buffer at RAM_BASE
    # Head at (8, 8), body trailing left: (7, 8), (6, 8), (5, 8)
    li s4, 0                 # tail_idx = 0
    li s3, 3                 # head_idx = 3

    # Segment 0 (tail): (5, 8)
    li t0, 5
    li t1, 8
    sb t0, 0(s10)            # X[0]
    addi t2, s10, 0x200
    sb t1, 0(t2)             # Y[0]

    # Segment 1: (6, 8)
    li t0, 6
    sb t0, 1(s10)            # X[1]
    sb t1, 1(t2)             # Y[1]

    # Segment 2: (7, 8)
    li t0, 7
    sb t0, 2(s10)            # X[2]
    sb t1, 2(t2)             # Y[2]

    # Segment 3 (head): (8, 8)
    li t0, 8
    sb t0, 3(s10)            # X[3]
    sb t1, 3(t2)             # Y[3]

    # Draw initial snake segments
    li a0, 8
    li a1, 5
    jal ra, set_cursor
    li a0, 111               # \x27o\x27
    jal ra, uart_write_char

    li a0, 8
    li a1, 6
    jal ra, set_cursor
    li a0, 111               # \x27o\x27
    jal ra, uart_write_char

    li a0, 8
    li a1, 7
    jal ra, set_cursor
    li a0, 111               # \x27o\x27
    jal ra, uart_write_char

    li a0, 8
    li a1, 8
    jal ra, set_cursor
    li a0, 64                # \x27@\x27 (head)
    jal ra, uart_write_char

    # Spawn first food
    jal ra, spawn_food

    # Show instructions below arena
    li a0, 19
    li a1, 1
    jal ra, set_cursor
    la a0, str_prompt
    jal ra, print_string

wait_for_start:
    jal ra, uart_read_nonblock
    li t0, 32                # SPACE
    beq a0, t0, start_playing
    li t0, 113               # \x27q\x27
    beq a0, t0, exit_game
    j wait_for_start

start_playing:
    # Clear instructions lines (rows 19..21)
    li a0, 19
    li a1, 1
    jal ra, set_cursor
    la a0, str_blank_line
    jal ra, print_string

    li a0, 20
    li a1, 1
    jal ra, set_cursor
    la a0, str_blank_line
    jal ra, print_string

    li a0, 21
    li a1, 1
    jal ra, set_cursor
    la a0, str_blank_line
    jal ra, print_string

# ------------------------------------------------------------------------------
# Main Game Loop
# ------------------------------------------------------------------------------
game_loop:
    # 1. Read keyboard inputs (drain buffer to get newest key)
input_poll_loop:
    jal ra, uart_read_nonblock
    beq a0, zero, input_done

    # Check \x27q\x27 / \x27Q\x27
    li t0, 113
    beq a0, t0, exit_game
    li t0, 81
    beq a0, t0, exit_game

    # \x27w\x27 / \x27W\x27 -> UP (if not moving DOWN)
    li t0, 119
    beq a0, t0, try_up
    li t0, 87
    beq a0, t0, try_up

    # \x27s\x27 / \x27S\x27 -> DOWN (if not moving UP)
    li t0, 115
    beq a0, t0, try_down
    li t0, 83
    beq a0, t0, try_down

    # \x27a\x27 / \x27A\x27 -> LEFT (if not moving RIGHT)
    li t0, 97
    beq a0, t0, try_left
    li t0, 65
    beq a0, t0, try_left

    # \x27d\x27 / \x27D\x27 -> RIGHT (if not moving LEFT)
    li t0, 100
    beq a0, t0, try_right
    li t0, 68
    beq a0, t0, try_right

    j input_poll_loop

try_up:
    li t0, DIR_DOWN
    beq s1, t0, input_poll_loop
    li s2, DIR_UP
    j input_poll_loop

try_down:
    li t0, DIR_UP
    beq s1, t0, input_poll_loop
    li s2, DIR_DOWN
    j input_poll_loop

try_left:
    li t0, DIR_RIGHT
    beq s1, t0, input_poll_loop
    li s2, DIR_LEFT
    j input_poll_loop

try_right:
    li t0, DIR_LEFT
    beq s1, t0, input_poll_loop
    li s2, DIR_RIGHT
    j input_poll_loop

input_done:
    # Commit queued direction
    mv s1, s2

    # 2. Compute new head coordinate
    # Load current head (X, Y)
    add t0, s10, s3
    lbu t1, 0(t0)            # head_x
    addi t0, t0, 0x200
    lbu t2, 0(t0)            # head_y

    li t3, DIR_UP
    beq s1, t3, move_up
    li t3, DIR_DOWN
    beq s1, t3, move_down
    li t3, DIR_LEFT
    beq s1, t3, move_left
    # Move RIGHT
    addi t1, t1, 1
    j check_wall_collision

move_up:
    addi t2, t2, -1
    j check_wall_collision
move_down:
    addi t2, t2, 1
    j check_wall_collision
move_left:
    addi t1, t1, -1

check_wall_collision:
    # Playable X: 2..31. Collision if X < 2 or X > 31
    li t4, 2
    blt t1, t4, snake_game_over
    li t4, 31
    bgt t1, t4, snake_game_over

    # Playable Y: 2..15. Collision if Y < 2 or Y > 15
    li t4, 2
    blt t2, t4, snake_game_over
    li t4, 15
    bgt t2, t4, snake_game_over

    # 3. Check self-collision
    # Iterate through all existing segments from tail_idx to head_idx
    mv t5, s4                # cur = tail_idx
check_self_loop:
    # Read segment (X, Y)
    add t6, s10, t5
    lbu a0, 0(t6)            # seg_x
    addi t6, t6, 0x200
    lbu a1, 0(t6)            # seg_y

    # If seg_x == new_head_x and seg_y == new_head_y -> crash!
    bne a0, t1, next_seg
    beq a1, t2, snake_game_over

next_seg:
    beq t5, s3, self_check_done
    addi t5, t5, 1
    andi t5, t5, 511         # Ring buffer wrap 512
    j check_self_loop

self_check_done:
    # Save computed (new_head_x, new_head_y) to stack across subroutine calls
    addi sp, sp, -8
    sw t1, 0(sp)             # new_head_x
    sw t2, 4(sp)             # new_head_y

    # 4. Check if Food is eaten (new_head == food)
    bne t1, s7, no_food_eaten
    bne t2, s8, no_food_eaten

    # --- FOOD EATEN ---
    # Score + 1, Snake grows (do NOT erase tail)
    addi s5, s5, 1
    addi s9, s9, 1

    # Update scoreboard
    li a0, 17
    li a1, 8
    jal ra, set_cursor
    mv a0, s5
    jal ra, print_dec_number

    # Spawn next food
    jal ra, spawn_food
    j update_head_rendering

no_food_eaten:
    # --- NO FOOD EATEN ---
    # Erase old tail segment from screen
    add t6, s10, s4
    lbu a1, 0(t6)            # tail_x
    addi t6, t6, 0x200
    lbu a0, 0(t6)            # tail_y
    jal ra, set_cursor
    li a0, 32                # \x27 \x27
    jal ra, uart_write_char

    # Advance tail index in circular buffer
    addi s4, s4, 1
    andi s4, s4, 511

update_head_rendering:
    # 5. Turn old head into body segment \x27o\x27
    add t6, s10, s3
    lbu a1, 0(t6)            # old_head_x
    addi t6, t6, 0x200
    lbu a0, 0(t6)            # old_head_y
    jal ra, set_cursor
    li a0, 111               # \x27o\x27
    jal ra, uart_write_char

    # 6. Retrieve new_head (t1, t2) from stack
    lw t1, 0(sp)             # new_head_x
    lw t2, 4(sp)             # new_head_y
    addi sp, sp, 8

    # Save new head to circular buffer
    addi s3, s3, 1
    andi s3, s3, 511
    add t6, s10, s3
    sb t1, 0(t6)             # new_head_x
    addi t6, t6, 0x200
    sb t2, 0(t6)             # new_head_y

    # Draw new head \x27@\x27
    mv a0, t2                # row
    mv a1, t1                # col
    jal ra, set_cursor
    li a0, 64                # \x27@\x27
    jal ra, uart_write_char

    # 7. Frame rate delay
    jal ra, snake_frame_delay

    j game_loop

# ------------------------------------------------------------------------------
# Arena Drawing: Top border, Side walls, Bottom border, Score
# ------------------------------------------------------------------------------
draw_arena:
    addi sp, sp, -8
    sw ra, 4(sp)
    sw s11, 0(sp)

    # Top border at row 1
    li a0, 1
    li a1, 1
    jal ra, set_cursor
    la a0, str_horiz_wall
    jal ra, print_string

    # Side walls for rows 2..15
    li s11, 2
arena_row_loop:
    # Left wall at col 1
    mv a0, s11
    li a1, 1
    jal ra, set_cursor
    li a0, 124               # \x27|\x27
    jal ra, uart_write_char

    # Right wall at col 32
    mv a0, s11
    li a1, 32
    jal ra, set_cursor
    li a0, 124               # \x27|\x27
    jal ra, uart_write_char

    addi s11, s11, 1
    li t0, 16
    blt s11, t0, arena_row_loop

    # Bottom border at row 16
    li a0, 16
    li a1, 1
    jal ra, set_cursor
    la a0, str_horiz_wall
    jal ra, print_string

    # Scoreboard at row 17
    li a0, 17
    li a1, 1
    jal ra, set_cursor
    la a0, str_score
    jal ra, print_string
    li a0, 0
    jal ra, print_dec_number

    lw s11, 0(sp)
    lw ra, 4(sp)
    addi sp, sp, 8
    jalr zero, 0(ra)

# ------------------------------------------------------------------------------
# Spawn Food using Galois LFSR
# ------------------------------------------------------------------------------
spawn_food:
    addi sp, sp, -8
    sw ra, 4(sp)

roll_food:
    # Step LFSR
    andi t0, s6, 1
    srli s6, s6, 1
    beq t0, zero, lfsr_step_done
    li t1, 0xB400
    xor s6, s6, t1
lfsr_step_done:
    # Food X: 2 + (s6 % 30) -> range [2..31]
    # Modulo 30 via repeated subtraction
    andi t2, s6, 0x7F        # 0..127
mod30_loop:
    addi t3, t2, -30
    blt t3, zero, mod30_done
    mv t2, t3
    j mod30_loop
mod30_done:
    addi s7, t2, 2           # food_x = 2..31

    # Step LFSR again for Y
    andi t0, s6, 1
    srli s6, s6, 1
    beq t0, zero, lfsr_y_done
    li t1, 0xB400
    xor s6, s6, t1
lfsr_y_done:
    # Food Y: 2 + (s6 % 14) -> range [2..15]
    andi t2, s6, 0x3F        # 0..63
mod14_loop:
    addi t3, t2, -14
    blt t3, zero, mod14_done
    mv t2, t3
    j mod14_loop
mod14_done:
    addi s8, t2, 2           # food_y = 2..15

    # Check if food landed on snake body
    mv t5, s4
check_food_overlap:
    add t6, s10, t5
    lbu a0, 0(t6)
    addi t6, t6, 0x200
    lbu a1, 0(t6)
    bne a0, s7, food_seg_ok
    beq a1, s8, roll_food    # Overlap! Re-roll
food_seg_ok:
    beq t5, s3, draw_food
    addi t5, t5, 1
    andi t5, t5, 511
    j check_food_overlap

draw_food:
    # Draw food symbol \x27*\x27 at (food_y, food_x)
    mv a0, s8
    mv a1, s7
    jal ra, set_cursor
    li a0, 42                # \x27*\x27
    jal ra, uart_write_char

    lw ra, 4(sp)
    addi sp, sp, 8
    jalr zero, 0(ra)

# ------------------------------------------------------------------------------
# Game Over Routine
# ------------------------------------------------------------------------------
snake_game_over:
    li a0, 19
    li a1, 1
    jal ra, set_cursor
    la a0, str_gameover
    jal ra, print_string
    la a0, str_final_score
    jal ra, print_string
    mv a0, s5
    jal ra, print_dec_number
    la a0, str_retry
    jal ra, print_string

wait_for_retry:
    jal ra, uart_read_nonblock
    li t0, 32                # SPACE -> Restart
    beq a0, t0, restart_game
    li t0, 113               # \x27q\x27 -> Exit
    beq a0, t0, exit_game
    j wait_for_retry

exit_game:
    li a0, 24
    li a1, 1
    jal ra, set_cursor
    la a0, str_goodbye
    jal ra, print_string
    li t0, 0x200000FC
    li t1, 1
    sw t1, 0(t0)
halt_loop:
    j halt_loop

# ------------------------------------------------------------------------------
# Hardware helpers: UART, cursor positioning, and number formatting
# ------------------------------------------------------------------------------
uart_write_char:
    lw t0, UART_STATUS(s0)
    andi t0, t0, 1
    beq t0, zero, uart_write_char
    sw a0, UART_DATA(s0)
    jalr zero, 0(ra)

uart_read_nonblock:
    lw t0, UART_STATUS(s0)
    andi t0, t0, 2
    beq t0, zero, rx_none
    lw a0, UART_DATA(s0)
    andi a0, a0, 0xFF
    jalr zero, 0(ra)
rx_none:
    li a0, 0
    jalr zero, 0(ra)

print_string:
    addi sp, sp, -8
    sw ra, 4(sp)
    sw s11, 0(sp)
    mv s11, a0
ps_loop:
    lbu a0, 0(s11)
    beq a0, zero, ps_done
    jal ra, uart_write_char
    addi s11, s11, 1
    j ps_loop
ps_done:
    lw s11, 0(sp)
    lw ra, 4(sp)
    addi sp, sp, 8
    jalr zero, 0(ra)

set_cursor:
    addi sp, sp, -16
    sw ra, 12(sp)
    sw s7, 8(sp)
    sw s8, 4(sp)
    mv s7, a0                # target row
    mv s8, a1                # target col

    li a0, 27                # ESC
    jal ra, uart_write_char
    li a0, 91                # \x27[\x27
    jal ra, uart_write_char

    mv a0, s7
    jal ra, print_dec_number

    li a0, 59                # \x27;\x27
    jal ra, uart_write_char

    mv a0, s8
    jal ra, print_dec_number

    li a0, 72                # \x27H\x27
    jal ra, uart_write_char

    lw s8, 4(sp)
    lw s7, 8(sp)
    lw ra, 12(sp)
    addi sp, sp, 16
    jalr zero, 0(ra)

print_dec_number:
    addi sp, sp, -16
    sw ra, 12(sp)
    sw s11, 8(sp)
    sw t1, 4(sp)
    sw t2, 0(sp)

    bne a0, zero, pdn_nonzero
    li a0, 48
    jal ra, uart_write_char
    j pdn_done

pdn_nonzero:
    addi t0, sp, 5
    sb zero, 0(t0)

pdn_div_loop:
    li t1, 0
pdn_sub_loop:
    addi t2, a0, -10
    blt t2, zero, pdn_sub_done
    mv a0, t2
    addi t1, t1, 1
    j pdn_sub_loop
pdn_sub_done:
    addi a0, a0, 48
    addi t0, t0, -1
    sb a0, 0(t0)
    mv a0, t1
    bne a0, zero, pdn_div_loop

    mv a0, t0
    jal ra, print_string

pdn_done:
    lw t2, 0(sp)
    lw t1, 4(sp)
    lw s11, 8(sp)
    lw ra, 12(sp)
    addi sp, sp, 16
    jalr zero, 0(ra)

snake_frame_delay:
    li t0, 0
    li t1, 1200
sfd_loop:
    addi t0, t0, 1
    blt t0, t1, sfd_loop
    jalr zero, 0(ra)

# ------------------------------------------------------------------------------
# String Constants
# ------------------------------------------------------------------------------
.section .rodata
str_clear:
    .string "\033[?25l\033[2J\033[3J\033[H"
str_horiz_wall:
    .string "+------------------------------+"
str_score:
    .string "SCORE: "
str_blank_line:
    .string "                                                  "
str_prompt:
    .string "=== RISC-V SNAKE ===\r\n[W/A/S/D] Move | [Q] Quit\r\nReady? Press SPACE to start!"
str_gameover:
    .string "*** GAME OVER ***\r\n"
str_final_score:
    .string "Final Score: "
str_retry:
    .string "\r\nPress SPACE to play again, or Q to quit."
str_goodbye:
    .string "\r\nThanks for playing! Exiting...\r\n\033[?25h"
