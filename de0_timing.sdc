# ============================================================================
# Synopsys Design Constraints (SDC) File for Altera DE0
# 50 MHz Master Clock Constraint
# ============================================================================

# Define 50 MHz Clock (20.000 ns period, 50% duty cycle)
create_clock -name CLOCK_50 -period 20.000 [get_ports CLOCK_50]

# Automatically calculate clock uncertainties
derive_clock_uncertainty

# Input delay constraints for buttons and switches (asynchronous user inputs)
set_false_path -from [get_ports {BUTTON[*]}]
set_false_path -from [get_ports {SW[*]}]
set_false_path -from [get_ports {UART_RXD}]
set_false_path -from [get_ports {GPIO0_D[1]}]

# Output delay constraints for LEDs and 7-segment displays
set_false_path -to [get_ports {LEDG[*]}]
set_false_path -to [get_ports {HEX*_D[*]}]
set_false_path -to [get_ports {HEX*_DP}]
set_false_path -to [get_ports {UART_TXD}]
set_false_path -to [get_ports {GPIO0_D[0]}]
