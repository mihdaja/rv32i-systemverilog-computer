#!/usr/bin/env bash
# ============================================================================
# Script: run_tests.sh
# Description: Automated simulation and regression test runner for RV32I SoC.
# ============================================================================

set -e

# Change directory to project root (directory where this script resides)
cd "$(dirname "$0")"

SCRIPT_DIR="$(pwd)"
SIM_BIN="top_soc_sim.vvp"

echo "======================================================================"
echo " RV32I SystemVerilog Computer: Automated SoC Test Suite"
echo "======================================================================"
echo "Starting build and verification process..."
echo

# ----------------------------------------------------------------------------
# 1. Compile System Simulation Model with Icarus Verilog
# ----------------------------------------------------------------------------
echo "[1/4] Compiling SystemVerilog design and testbench with iverilog..."

iverilog -g2012 -Wall -s top_soc_tb -o "$SIM_BIN" \
  rv32i_pkg.sv \
  alu.sv \
  reg_file.sv \
  imm_gen.sv \
  pc_reg.sv \
  next_pc_gen.sv \
  decoder.sv \
  lsu.sv \
  bus_interconnect.sv \
  rom_sync.sv \
  ram_sync.sv \
  uart_tx.sv \
  system_timer.sv \
  rv32i_core.sv \
  top_soc.sv \
  top_soc_tb.sv

echo "      Compilation successful -> $SIM_BIN"
echo

# ----------------------------------------------------------------------------
# 2. Test Execution Function
# ----------------------------------------------------------------------------
PASSED_COUNT=0
FAILED_COUNT=0
TOTAL_COUNT=3

run_test() {
  local test_name="$1"
  local rom_hex="$2"
  local ram_hex="$3"
  local log_file="/tmp/${test_name}.log"

  echo "----------------------------------------------------------------------"
  echo "Running Test: ${test_name}"
  echo "ROM Image:    ${rom_hex}"
  echo "RAM Image:    ${ram_hex}"
  echo "----------------------------------------------------------------------"

  if [ ! -f "$rom_hex" ]; then
    echo "ERROR: ROM hex file not found: $rom_hex"
    FAILED_COUNT=$((FAILED_COUNT + 1))
    return 1
  fi

  set +e
  vvp "$SIM_BIN" "+ROM_HEX=${rom_hex}" "+RAM_HEX=${ram_hex}" > "$log_file" 2>&1
  local exit_code=$?
  set -e

  cat "$log_file"

  if [ $exit_code -eq 0 ] && grep -q ">>> TEST PASSED <<<" "$log_file"; then
    echo "Result: [PASSED] - ${test_name}"
    PASSED_COUNT=$((PASSED_COUNT + 1))
  else
    echo "Result: [FAILED] - ${test_name}"
    FAILED_COUNT=$((FAILED_COUNT + 1))
  fi
  echo
}

# ----------------------------------------------------------------------------
# 3. Execute Automated Tests
# ----------------------------------------------------------------------------
run_test "basic_math" "sw/basic_math.hex" "sw/basic_math_ram.hex"
run_test "branch_test" "sw/branch_test.hex" "sw/branch_test_ram.hex"
run_test "hello_uart" "sw/hello_uart.hex" "sw/hello_uart_ram.hex"

# ----------------------------------------------------------------------------
# 4. Summary Report
# ----------------------------------------------------------------------------
echo "======================================================================"
echo " Test Suite Summary"
echo "======================================================================"
echo "Total Tests Run : $TOTAL_COUNT"
echo "Passed          : $PASSED_COUNT"
echo "Failed          : $FAILED_COUNT"

if [ $FAILED_COUNT -eq 0 ]; then
  echo "Status          : ALL TESTS PASSED SUCCESSFULLY!"
  echo "======================================================================"
  exit 0
else
  echo "Status          : ONE OR MORE TESTS FAILED!"
  echo "======================================================================"
  exit 1
fi
