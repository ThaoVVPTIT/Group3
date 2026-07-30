# DE10-Lite MAX10_CLK1_50 oscillator: 50 MHz (20 ns period).
create_clock -name MAX10_CLK1_50 -period 20.000 [get_ports {MAX10_CLK1_50}]

# Add the device-recommended setup/hold clock uncertainty.
derive_clock_uncertainty

# UART RX, push-buttons and switches are asynchronous to MAX10_CLK1_50.
set_false_path -from [get_ports {UART_RX KEY[0] SW[*]}]

# UART TX and LEDs have no external clock relationship or output-delay
# requirement in this GPIO/UART functional test.
set_false_path -to [get_ports {UART_TX LEDR[*]}]
