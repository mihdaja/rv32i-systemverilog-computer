#!/usr/bin/env bash
# ============================================================================
# Script: connect_terminal.sh
# Description: Launch RV32I Computer simulation and connect interactive terminal.
# Usage:
#   ./connect_terminal.sh                     # Runs interactive keystroke echo test
#   ./connect_terminal.sh sw/flappy_bird.hex  # Runs Flappy Bird game in terminal
# ============================================================================

set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DIR"

PROGRAM_ROM="${1:-sw/terminal_echo.hex}"
PROGRAM_RAM="${PROGRAM_ROM%.hex}_ram.hex"

if [ ! -f "$PROGRAM_ROM" ]; then
  echo "Error: ROM file '$PROGRAM_ROM' not found!"
  exit 1
fi

if [ ! -f "$PROGRAM_RAM" ]; then
  PROGRAM_RAM="sw/ram.hex"
fi

# 1. Compile VPI module if missing
if [ ! -f "pty_bridge.vpi" ]; then
  echo "[1/3] Building terminal VPI bridge (pty_bridge.c)..."
  iverilog-vpi pty_bridge.c
fi

# 2. Compile simulation model if missing or outdated
if [ ! -f "terminal_sim.vvp" ] || [ "terminal_tb.sv" -nt "terminal_sim.vvp" ] || [ "top_soc.sv" -nt "terminal_sim.vvp" ] || [ "uart_tx.sv" -nt "terminal_sim.vvp" ]; then
  echo "[2/3] Compiling SystemVerilog computer simulation model..."
  iverilog -g2012 -Wall -s terminal_tb -o terminal_sim.vvp \
    rv32i_pkg.sv alu.sv reg_file.sv imm_gen.sv pc_reg.sv next_pc_gen.sv decoder.sv lsu.sv \
    bus_interconnect.sv rom_sync.sv ram_sync.sv uart_tx.sv system_timer.sv rv32i_core.sv \
    top_soc.sv terminal_tb.sv
fi

echo "[3/3] Starting RV32I simulation with ROM: $(basename "$PROGRAM_ROM")..."

# Kill any previous dangling simulator instance
pkill -f "terminal_sim.vvp" 2>/dev/null || true

# Start simulator in background
vvp -M. -mpty_bridge terminal_sim.vvp "+ROM_HEX=$PROGRAM_ROM" "+RAM_HEX=$PROGRAM_RAM" > rv32_sim.log 2>&1 &
SIM_PID=$!

cleanup() {
  if kill -0 "$SIM_PID" 2>/dev/null; then
    kill "$SIM_PID" 2>/dev/null || true
  fi
}
trap cleanup EXIT INT TERM

# Wait for TCP server on localhost:9000 to be ready
READY=0
for i in {1..40}; do
  if nc -z 127.0.0.1 9000 2>/dev/null; then
    READY=1
    break
  fi
  sleep 0.05
done

if [ $READY -eq 0 ]; then
  echo "Failed to connect to simulator. Check rv32_sim.log:"
  cat rv32_sim.log
  exit 1
fi

# Connect raw terminal client
clear 2>/dev/null || printf '\033[2J\033[3J\033[H'
python3 term.py
