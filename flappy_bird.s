# ==============================================================================
# Flappy Bird for RV32I Bare-Metal System (Dirty-Rect High FPS Version)
# ==============================================================================
# Hardware mapped registers:
#   0x20000000 : UART TX/RX Data (8-bit)
#   0x20000004 : UART Status (bit 0 = TX ready, bit 1 = RX char ready)
#   0x20000010 : System Timer (32-bit cycle count low)
#
# Terminal:
#   ANSI terminal with targeted partial redraws (no full-screen clears).
#   Grid size: 32 columns wide x 16 rows high.
#   Controls: SPACE key flaps upward. Q quits.
# ==============================================================================

.section .text
.globl _start

# Memory map definitions
.equ UART_BASE,    0x20000000
.equ UART_DATA,    0x00
.equ UART_STATUS,  0x04
.equ TIMER_BASE,   0x20000010

# Board and game constants
.equ SCREEN_W,     32
.equ SCREEN_H,     16
.equ BIRD_COL,     6

# Register roles across main game loop:
#   s0: UART base pointer (0x20000000)
#   s1: Bird Y coordinate (row 0 to 14)
#   s2: Pipe X coordinate (column 0 to 30)
#   s3: Pipe Gap Y top (row where gap starts)
#   s4: Pipe Gap Height (constant = 4)
#   s5: Player score
#   s6: Pseudo-random LFSR state
#   s7: Old Bird Y coordinate (for targeted erase)
#   s8: Old Pipe X coordinate
#   s9: Pipe wrap flag (1 = erase left edge columns 1-4)
#   s10: Old score (for targeted score redraw)

_start:
    # Initialize stack pointer to top of RAM
    li sp, 0x10010000

    # Initialize peripheral base pointer
    li s0, 0x20000000

    # Hide cursor and clear terminal screen
    la a0, str_init_term
    jal ra, print_string

restart_game:
    # Set starting game state
    addi s1, zero, 7         # Bird Y starts in middle
    addi s2, zero, 28        # Pipe starts on right side
    addi s3, zero, 5         # Initial gap starts at row 5
    addi s4, zero, 4         # Gap height is 4 rows
    addi s5, zero, 0         # Score = 0
    addi s6, zero, 0xACE     # Seed LFSR
    addi s7, zero, 7         # Old bird Y = 7
    addi s8, zero, 28        # Old pipe X = 28
    addi s9, zero, 0         # Wrap flag = 0
    addi s10, zero, 0        # Old score = 0

    # Clear entire screen & scrollback
    la a0, str_clear
    jal ra, print_string

    # Draw static ground border at row 16
    addi a0, zero, 16
    addi a1, zero, 1
    jal ra, set_cursor
    la a0, str_ground
    jal ra, print_string

    # Draw static scoreboard label at row 17
    addi a0, zero, 17
    addi a1, zero, 1
    jal ra, set_cursor
    la a0, str_score
    jal ra, print_string
    addi a0, zero, 0
    jal ra, print_dec_number

    # Draw initial bird and initial pipe
    jal ra, render_frame_dirty

    # Draw initial welcome and instructions below board (row 19)
    addi a0, zero, 19
    addi a1, zero, 1
    jal ra, set_cursor
    la a0, str_prompt
    jal ra, print_string

wait_for_start:
    jal ra, uart_read_nonblock
    addi t0, zero, 32        # SPACE
    beq a0, t0, start_playing
    addi t0, zero, 113       # 'q'
    beq a0, t0, exit_game
    j wait_for_start

start_playing:
    # Clear prompt lines at rows 19..23
    addi a0, zero, 19
    addi a1, zero, 1
    jal ra, set_cursor
    la a0, str_blank_line
    jal ra, print_string
    addi a0, zero, 20
    addi a1, zero, 1
    jal ra, set_cursor
    la a0, str_blank_line
    jal ra, print_string
    addi a0, zero, 21
    addi a1, zero, 1
    jal ra, set_cursor
    la a0, str_blank_line
    jal ra, print_string
    addi a0, zero, 22
    addi a1, zero, 1
    jal ra, set_cursor
    la a0, str_blank_line
    jal ra, print_string
    addi a0, zero, 23
    addi a1, zero, 1
    jal ra, set_cursor
    la a0, str_blank_line
    jal ra, print_string

game_loop:
    # 1. Process player input
    jal ra, uart_read_nonblock
    addi t0, zero, 32        # SPACE pressed?
    bne a0, t0, check_quit
    addi s1, s1, -2          # Flap: move bird up 2 rows
    blt s1, zero, hit_ceiling
    j finish_input
hit_ceiling:
    addi s1, zero, 0
    j game_over

check_quit:
    addi t0, zero, 113       # Q pressed?
    beq a0, t0, exit_game

    # Gravity: bird falls 1 row every frame if no flap
    addi s1, s1, 1

finish_input:
    # 2. Advance pipe position (2x speed)
    addi s2, s2, -2
    bge s2, zero, skip_pipe_reset

    # Pipe reached left edge: reset to right side and score + 1
    addi s2, zero, 28
    addi s5, s5, 1
    addi s9, zero, 1         # Set wrap flag to erase left edge

    # Pseudo-randomize gap position using 16-bit Galois LFSR
    andi t0, s6, 1
    srli s6, s6, 1
    beq t0, zero, lfsr_skip_tap
    li t1, 0xb400
    xor s6, s6, t1
lfsr_skip_tap:
    # New gap top = 2 + (s6 % 8)
    andi t2, s6, 7
    addi s3, t2, 2

skip_pipe_reset:
    # 3. Collision detection
    # Did bird hit ground? (row >= 15)
    addi t0, zero, 15
    bge  s1, t0, game_over

    # Did bird hit ceiling? (row < 0)
    blt  s1, zero, game_over

    # Is bird in the pipe column? (col == s2 or col == s2 + 1)
    addi t0, zero, BIRD_COL
    beq  s2, t0, in_pipe_col
    addi t1, s2, 1
    beq  t1, t0, in_pipe_col
    j    skip_collision

in_pipe_col:
    # In pipe column: check if inside gap
    # Collision if s1 < s3 (above gap)
    blt  s1, s3, game_over
    # Collision if s1 >= s3 + s4 (below gap)
    add  t1, s3, s4
    bge  s1, t1, game_over

skip_collision:
    # 4. Render ONLY changed elements (pipes and bird)
    jal ra, render_frame_dirty

    # 5. Delay until next frame
    jal ra, frame_delay

    j game_loop

# ------------------------------------------------------------------------------
# Targeted Frame Renderer (Dirty-rect redraw without rendering empty spaces)
# ------------------------------------------------------------------------------
render_frame_dirty:
    addi sp, sp, -16
    sw ra, 12(sp)
    sw s11, 8(sp)

    # --------------------------------------------------------------------------
    # 1. Pipe rendering and erase
    # --------------------------------------------------------------------------
    # If pipe wrapped, erase columns 1-4 on rows 1..15
    beq s9, zero, render_pipe_body
    addi s11, zero, 1
clear_left_loop:
    mv a0, s11
    addi a1, zero, 1
    jal ra, set_cursor
    la a0, str_four_spaces
    jal ra, print_string
    addi s11, s11, 1
    addi t1, zero, 16
    blt s11, t1, clear_left_loop
    addi s9, zero, 0

render_pipe_body:
    # For rows r = 0..14 (ANSI row = r + 1)
    addi s11, zero, 0
pipe_row_loop:
    # Position cursor at (s11 + 1, s2 + 1)
    addi a0, s11, 1
    addi a1, s2, 1
    jal ra, set_cursor

    # Is row s11 inside the gap? (s11 >= s3 and s11 < s3 + s4)
    blt s11, s3, draw_wall
    add t1, s3, s4
    bge s11, t1, draw_wall

draw_gap:
    addi a0, zero, 32        # ' '
    jal ra, uart_write_char
    addi a0, zero, 32
    jal ra, uart_write_char
    j check_trail

draw_wall:
    addi a0, zero, 124       # '|'
    jal ra, uart_write_char
    addi a0, zero, 124
    jal ra, uart_write_char

check_trail:
    # Erase old pipe trailing at (s2 + 2, s2 + 3) if within screen width (32)
    addi t0, s2, 2
    addi t1, zero, 32
    bge t0, t1, pipe_row_next
    addi a0, zero, 32
    jal ra, uart_write_char
    addi t0, s2, 3
    bge t0, t1, pipe_row_next
    addi a0, zero, 32
    jal ra, uart_write_char

pipe_row_next:
    addi s11, s11, 1
    addi t0, zero, 15
    blt s11, t0, pipe_row_loop

    # --------------------------------------------------------------------------
    # 2. Bird rendering and erase
    # --------------------------------------------------------------------------
    # Erase old bird position if bird moved
    beq s7, s1, draw_new_bird
    addi a0, s7, 1
    addi a1, zero, BIRD_COL + 1
    jal ra, set_cursor
    addi a0, zero, 32        # ' '
    jal ra, uart_write_char

draw_new_bird:
    addi a0, s1, 1
    addi a1, zero, BIRD_COL + 1
    jal ra, set_cursor
    addi a0, zero, 79        # 'O'
    jal ra, uart_write_char
    mv s7, s1                # old_bird_y = bird_y

    # --------------------------------------------------------------------------
    # 3. Scoreboard update (only when score changed)
    # --------------------------------------------------------------------------
    beq s5, s10, rfd_done
    addi a0, zero, 17
    addi a1, zero, 8
    jal ra, set_cursor
    mv a0, s5
    jal ra, print_dec_number
    mv s10, s5

rfd_done:
    lw s11, 8(sp)
    lw ra, 12(sp)
    addi sp, sp, 16
    jalr zero, 0(ra)

# ------------------------------------------------------------------------------
# Game over & exit routines
# ------------------------------------------------------------------------------
game_over:
    addi a0, zero, 19
    addi a1, zero, 1
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
    addi t0, zero, 32
    beq a0, t0, restart_game
    addi t0, zero, 113
    beq a0, t0, exit_game
    j wait_for_retry

exit_game:
    addi a0, zero, 24
    addi a1, zero, 1
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

# Write character in a0 to UART
uart_write_char:
    lw t0, UART_STATUS(s0)
    andi t0, t0, 1           # Check TX ready bit
    beq t0, zero, uart_write_char
    sw a0, UART_DATA(s0)
    jalr zero, 0(ra)

# Non-blocking UART read: returns character in a0, or 0 if nothing waiting
uart_read_nonblock:
    lw t0, UART_STATUS(s0)
    andi t0, t0, 2           # Check RX valid bit
    beq t0, zero, rx_none
    lw a0, UART_DATA(s0)
    andi a0, a0, 0xFF
    jalr zero, 0(ra)
rx_none:
    addi a0, zero, 0
    jalr zero, 0(ra)

# Print null-terminated string at address a0
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

# Position cursor at row a0 (1..32), column a1 (1..32) using ANSI sequence: "\033[<row>;<col>H"
set_cursor:
    addi sp, sp, -16
    sw ra, 12(sp)
    sw s7, 8(sp)
    sw s8, 4(sp)
    mv s7, a0                # target row
    mv s8, a1                # target col

    addi a0, zero, 27        # ESC
    jal ra, uart_write_char
    addi a0, zero, 91        # '['
    jal ra, uart_write_char

    mv a0, s7
    jal ra, print_dec_number

    addi a0, zero, 59        # ';'
    jal ra, uart_write_char

    mv a0, s8
    jal ra, print_dec_number

    addi a0, zero, 72        # 'H'
    jal ra, uart_write_char

    lw s8, 4(sp)
    lw s7, 8(sp)
    lw ra, 12(sp)
    addi sp, sp, 16
    jalr zero, 0(ra)

# Print positive integer in a0 as decimal
print_dec_number:
    addi sp, sp, -16
    sw ra, 12(sp)
    sw s11, 8(sp)

    # If number is zero, print single zero
    bne a0, zero, pdn_nonzero
    addi a0, zero, 48
    jal ra, uart_write_char
    j pdn_done

pdn_nonzero:
    # Buffer up to 5 decimal digits on stack (offset 0..4)
    addi t0, sp, 5           # Buffer pointer
    sb zero, 0(t0)           # Null terminator

pdn_div_loop:
    # Divide by 10 via repeated subtraction
    addi t1, zero, 0         # Quotient
pdn_sub_loop:
    addi t2, a0, -10
    blt t2, zero, pdn_sub_done
    mv a0, t2
    addi t1, t1, 1
    j pdn_sub_loop
pdn_sub_done:
    # a0 is remainder, t1 is quotient
    addi a0, a0, 48
    addi t0, t0, -1
    sb a0, 0(t0)
    mv a0, t1
    bne a0, zero, pdn_div_loop

    # Print formatted string from buffer
    mv a0, t0
    jal ra, print_string

pdn_done:
    lw s11, 8(sp)
    lw ra, 12(sp)
    addi sp, sp, 16
    jalr zero, 0(ra)

# Short delay between frames
frame_delay:
    addi t0, zero, 0
    li t1, 1500              # tuned for responsive simulation frame rate
fd_loop:
    addi t0, t0, 1
    blt t0, t1, fd_loop
    jalr zero, 0(ra)

# ------------------------------------------------------------------------------
# String tables and ANSI escape sequences
# ------------------------------------------------------------------------------
.section .rodata

str_init_term:
    .string "\033[?25l\033[2J\033[3J\033[H"

str_clear:
    .string "\033[2J\033[3J\033[H"

str_ground:
    .string "================================"

str_score:
    .string "SCORE: "

str_prompt:
    .string "=== RISC-V FLAPPY BIRD ===\r\nPress [SPACE] to Flap\r\nPress [Q] to Quit\r\n\r\nReady? Press SPACE to start!"

str_blank_line:
    .string "                                                  "

str_four_spaces:
    .string "    "

str_gameover:
    .string "*** CRASH! GAME OVER ***\r\n"

str_final_score:
    .string "Final Score: "

str_retry:
    .string "\r\nPress [SPACE] to play again, [Q] to exit.\r\n"

str_goodbye:
    .string "\033[?25h\r\nGame halted. Cursor restored.\r\n"

