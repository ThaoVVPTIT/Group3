@echo off
setlocal
set MODELSIM=E:\Quartus\Data_setup\modelsim_ase\win32aloem

if exist work_axi rmdir /s /q work_axi
"%MODELSIM%\vlib.exe" work_axi || exit /b 1
"%MODELSIM%\vlog.exe" -work work_axi sim\axi4lite_cnn_tb.v rtl\axi4lite_soc_slave.v rtl\cnn_accel_core.v rtl\cnn_input_ram.v rtl\axis_cnn_mnist.v rtl\conv1_layer.v rtl\conv1_buf.v rtl\conv1_calc.v rtl\maxpool_relu.v rtl\conv2_layer.v rtl\conv2_buf.v rtl\conv2_calc.v rtl\fully_connected.v rtl\comparator.v rtl\simpleuart.v || exit /b 1
"%MODELSIM%\vsim.exe" -c -lib work_axi axi4lite_cnn_tb -do "run -all; quit -f"
endlocal
