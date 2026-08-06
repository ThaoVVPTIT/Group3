# DE10-Lite 50 MHz oscillator.
create_clock -name MAX10_CLK1_50 -period 20.000 [get_ports {MAX10_CLK1_50}]
derive_clock_uncertainty

# Board buttons, switches and UART RX are asynchronous to the FPGA clock.
set_false_path -from [get_ports {UART_RX KEY[*] SW[*]}]

# UART TX and LEDs are functional/debug outputs without a receiving clock.
set_false_path -to [get_ports {UART_TX LEDR[*]}]
