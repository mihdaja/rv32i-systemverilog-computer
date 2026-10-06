# Altera DE0 FPGA Port (TU Delft CSE 2420 Digital Systems)

This directory contains the physical FPGA implementation of the RV32I Computer and SoC tailored specifically for the **Altera / Terasic DE0 Education Board** (featuring the **Intel/Altera Cyclone III EP3C16F484C6** FPGA), as used in the TU Delft CSE 2420 Digital Systems lab course.

---

## Board Specifications & Resource Budget

The Cyclone III EP3C16F484 on the DE0 board provides:
- **Logic Elements**: 15,408 LEs (RV32I Core + SoC uses ~2,400 LEs, ~15% utilization)
- **Embedded Memory**: 56 M9K BRAM blocks (504 Kbits = 63 KB maximum total RAM)
- **On-board Oscillator**: 50 MHz clock on `PIN_G21` (matches our core clock directly, no PLL needed)

### Memory Allocation on EP3C16
- **Boot ROM**: 16 KB (16 M9K blocks preloaded with `$readmemh` during bitstream compilation)
- **Main SRAM**: 32 KB (32 M9K blocks for stack, heap, `.data`, `.bss`)
- **Total BRAM used**: 48 M9K blocks out of 56 (85% utilization, leaving 8 blocks free)

---

## Physical I/O and Pin Mapping

| Peripheral | Board Component | Cyclone III Pin | Description |
|---|---|---|---|
| **Clock** | `CLOCK_50` | `PIN_G21` | 50 MHz on-board oscillator |
| **Reset** | `BUTTON[0]` | `PIN_H2` | Active-low push button (debounced & synchronized) |
| **Soft Reset** | `SW[0]` | `PIN_J6` | Slide switch (UP = Reset active) |
| **UART RX Sel** | `SW[1]` | `PIN_H5` | `0`: RS-232 DB9 port (`PIN_A8`), `1`: GPIO0 header (`PIN_C3`) |
| **Display Mode** | `SW[3:2]` | `PIN_G4`, `PIN_H6` | `00`: PC, `01`: Inst [15:0], `10`: Inst [31:16], `11`: Exit Code |
| **Status LEDs** | `LEDG[0]` | `PIN_J1` | Game Over / Simulation Exit Trap valid |
| | `LEDG[1]` | `PIN_J2` | UART Transmitter active |
| | `LEDG[2]` | `PIN_J3` | UART Receiver active |
| | `LEDG[3]` | `PIN_H1` | 64-bit Hardware Timer Interrupt (`timer_irq`) |
| | `LEDG[9:4]` | `PIN_B1..PIN_E1` | Status / Result Code bits [5:0] |
| **7-Segments** | `HEX0_D[6:0]` | `PIN_F13..PIN_E11` | Digit 0 (lowest nibble) |
| | `HEX1_D[6:0]` | `PIN_A15..PIN_A13` | Digit 1 |
| | `HEX2_D[6:0]` | `PIN_F14..PIN_D15` | Digit 2 |
| | `HEX3_D[6:0]` | `PIN_G15..PIN_B18` | Digit 3 (highest nibble) |
| **RS-232** | `UART_TXD` | `PIN_B8` | DB9 serial port transmit (via MAX3232) |
| | `UART_RXD` | `PIN_A8` | DB9 serial port receive |
| **GPIO Header** | `GPIO0_D[0]` | `PIN_D3` | 3.3V LVTTL UART TX (for FTDI / CP2102 USB dongles) |
| | `GPIO0_D[1]` | `PIN_C3` | 3.3V LVTTL UART RX |

---

## Directory Contents

- **[`de0_top.sv`](file:///Users/mihai/Documents/TU%20Delft%20CSE%20(2025)/Year%202/Quarter%201/CSE%202420%20Digital%20Systems%20(DS)/SystemVerilog%20PC%20Design/de0_fpga_port/de0_top.sv)**: Top-level board wrapper with clock synchronization, push-button debouncing, and 7-segment multiplexing.
- **[`de0_soc.sv`](file:///Users/mihai/Documents/TU%20Delft%20CSE%20(2025)/Year%202/Quarter%201/CSE%202420%20Digital%20Systems%20(DS)/SystemVerilog%20PC%20Design/de0_fpga_port/de0_soc.sv)**: SoC configured with 16 KB ROM and 32 KB SRAM fitting the Cyclone III M9K memory budget.
- **[`uart_rx.sv`](file:///Users/mihai/Documents/TU%20Delft%20CSE%20(2025)/Year%202/Quarter%201/CSE%202420%20Digital%20Systems%20(DS)/SystemVerilog%20PC%20Design/de0_fpga_port/uart_rx.sv)**: Hardware 8N1 serial receiver with mid-bit center sampling at 115,200 baud.
- **[`seven_seg_decoder.sv`](file:///Users/mihai/Documents/TU%20Delft%20CSE%20(2025)/Year%202/Quarter%201/CSE%202420%20Digital%20Systems%20(DS)/SystemVerilog%20PC%20Design/de0_fpga_port/seven_seg_decoder.sv)**: Active-low hexadecimal to 7-segment cathode decoder.
- **[`de0_pins.qsf`](file:///Users/mihai/Documents/TU%20Delft%20CSE%20(2025)/Year%202/Quarter%201/CSE%202420%20Digital%20Systems%20(DS)/SystemVerilog%20PC%20Design/de0_fpga_port/de0_pins.qsf)**: Complete Quartus II / Quartus Prime pin assignments and I/O standards.
- **[`de0_timing.sdc`](file:///Users/mihai/Documents/TU%20Delft%20CSE%20(2025)/Year%202/Quarter%201/CSE%202420%20Digital%20Systems%20(DS)/SystemVerilog%20PC%20Design/de0_fpga_port/de0_timing.sdc)**: 50 MHz timing constraints and false-path definitions.
- **[`de0_tb.sv`](file:///Users/mihai/Documents/TU%20Delft%20CSE%20(2025)/Year%202/Quarter%201/CSE%202420%20Digital%20Systems%20(DS)/SystemVerilog%20PC%20Design/de0_fpga_port/de0_tb.sv)**: Verification testbench for the board wrapper.
- **[`hex_to_mif.py`](file:///Users/mihai/Documents/TU%20Delft%20CSE%20(2025)/Year%202/Quarter%201/CSE%202420%20Digital%20Systems%20(DS)/SystemVerilog%20PC%20Design/de0_fpga_port/hex_to_mif.py)**: Utility to convert `.hex` files to Altera Memory Initialization Files (`.mif`).

---

## How to Build in Quartus Prime / Quartus II

1. **Create or Open Project**:
   - Open Quartus (e.g. Quartus II 13.0sp1 or Quartus Prime Lite).
   - Create a project named `de0_rv32i` targeting device **`EP3C16F484C6`**.
   - Import `de0_pins.qsf` (or Project -> Add/Remove Files in Project -> Add all files listed in `de0_pins.qsf`).
2. **Compile Design**:
   - Press **Start Compilation** (`Ctrl+L`).
   - Timing Analyzer will confirm 50 MHz timing closure (`Slack > 0`).
3. **Program FPGA**:
   - Open **Programmer** (`Tools -> Programmer`).
   - Select hardware: **USB-Blaster**.
   - Add file: `output_files/de0_top.sof`.
   - Click **Start**.

---

## Connecting Your Computer to Play Games on the Board

### Option A: Using a 3.3V USB-UART Dongle (CP2102 / FTDI)
1. Connect ground (GND) to `PIN 12` of GPIO0.
2. Connect adapter RX to DE0 `GPIO0_D[0]` (`PIN_D3`).
3. Connect adapter TX to DE0 `GPIO0_D[1]` (`PIN_C3`).
4. Set `SW[1]` to **UP** (selects GPIO header for UART).

### Option B: Using the On-board RS-232 DB9 Connector
1. Plug a standard USB-to-RS232 serial cable into the DE0 DB9 port.
2. Set `SW[1]` to **DOWN** (selects DB9 port).

### Launching the Game
On your host PC (macOS/Linux), open the serial port at 115,200 baud in raw mode:
```bash
# In terminal
python3 ../term.py  # Or screen /dev/cu.usbserial-* 115200
```
Press `BUTTON[0]` on the DE0 board to reset. The 7-segment displays will show the program counter advancing, and the game will render in your terminal!
