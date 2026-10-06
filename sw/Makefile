# ============================================================================
# Makefile for RV32I Bare-Metal Software and Test Suite
#
# Automatically detects if a RISC-V cross-compiler is available:
#   - If available: compiles with GCC, links with link.ld, outputs ELF, BIN, HEX.
#   - If absent: falls back to the pure-Python RV32I assembler & hex generator.
# ============================================================================

PYTHON ?= python3
HEXGEN  = $(PYTHON) generate_hex.py

# Check for available RISC-V GCC toolchains
TOOLCHAIN_BIN := $(shell which riscv32-unknown-elf-gcc 2>/dev/null || \
                         which riscv64-unknown-elf-gcc 2>/dev/null || \
                         which riscv-none-elf-gcc 2>/dev/null)

ifneq ($(TOOLCHAIN_BIN),)
    # Toolchain found - derive prefix
    CROSS_COMPILE ?= $(subst gcc,,$(TOOLCHAIN_BIN))
    CC      = $(CROSS_COMPILE)gcc
    AS      = $(CROSS_COMPILE)as
    LD      = $(CROSS_COMPILE)ld
    OBJCOPY = $(CROSS_COMPILE)objcopy
    OBJDUMP = $(CROSS_COMPILE)objdump
    TOOLCHAIN_AVAILABLE = 1
else
    TOOLCHAIN_AVAILABLE = 0
endif

CFLAGS  = -march=rv32i -mabi=ilp32 -static -mcmodel=medany -nostdlib -fno-builtin -Wall -Wextra -O2
LDFLAGS = -T link.ld -nostdlib

TARGETS = basic_math.hex branch_test.hex hello_uart.hex flappy_bird.hex snake.hex terminal_echo.hex

.PHONY: all clean info

all: info $(TARGETS) rom.hex ram.hex

info:
ifeq ($(TOOLCHAIN_AVAILABLE),1)
	@echo "==> Using RISC-V toolchain: $(CC)"
else
	@echo "==> RISC-V GCC toolchain not found in PATH."
	@echo "==> Using pure-Python RV32I assembler fallback (generate_hex.py)."
endif

# Default ROM/RAM memory image for top-level simulation
rom.hex: basic_math.hex
	cp $< $@

ram.hex: basic_math_ram.hex
	cp $< $@

# ----------------------------------------------------------------------------
# Build rules with GCC toolchain
# ----------------------------------------------------------------------------
ifeq ($(TOOLCHAIN_AVAILABLE),1)

basic_math.elf: basic_math.s link.ld
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ basic_math.s

branch_test.elf: branch_test.s link.ld
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ branch_test.s

hello_uart.elf: crt0.s hello_uart.c uart.c timer.c link.ld
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ crt0.s hello_uart.c uart.c timer.c

flappy_bird.elf: flappy_bird.s link.ld
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ flappy_bird.s

snake.elf: snake.s link.ld
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ snake.s

terminal_echo.elf: terminal_echo.s link.ld
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ terminal_echo.s

%.bin: %.elf
	$(OBJCOPY) -O binary $< $@

%.dump: %.elf
	$(OBJDUMP) -D -S $< > $@

%.hex: %.elf
	$(HEXGEN) $< --rom-out $@ --ram-out $(basename $@)_ram.hex

else

# ----------------------------------------------------------------------------
# Fallback build rules using pure-Python assembler
# ----------------------------------------------------------------------------

basic_math.hex: basic_math.s generate_hex.py
	$(HEXGEN) $< --rom-out $@ --ram-out basic_math_ram.hex

branch_test.hex: branch_test.s generate_hex.py
	$(HEXGEN) $< --rom-out $@ --ram-out branch_test_ram.hex

hello_uart.hex: hello_uart.s generate_hex.py
	$(HEXGEN) $< --rom-out $@ --ram-out hello_uart_ram.hex

flappy_bird.hex: flappy_bird.s generate_hex.py
	$(HEXGEN) $< --rom-out $@ --ram-out flappy_bird_ram.hex

snake.hex: snake.s generate_hex.py
	$(HEXGEN) $< --rom-out $@ --ram-out snake_ram.hex

terminal_echo.hex: terminal_echo.s generate_hex.py
	$(HEXGEN) $< --rom-out $@ --ram-out terminal_echo_ram.hex

endif

clean:
	rm -f *.elf *.bin *.hex *.dump *.o
