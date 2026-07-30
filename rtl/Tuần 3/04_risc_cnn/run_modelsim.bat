@echo off
setlocal
set "MODELSIM_BIN=E:\Quartus\Data_setup\modelsim_ase\win32aloem"

if exist Q:\de10_riscv_cnn_sample.qpf goto q_mapped
subst Q: "%~dp0"
if errorlevel 1 (
    echo Cannot create temporary Q: mapping.
    echo Remove an old mapping with: subst Q: /d
    exit /b 1
)
:q_mapped

pushd Q:\
if not exist work "%MODELSIM_BIN%\vlib.exe" work
"%MODELSIM_BIN%\vlog.exe" ^
  rtl/cnn_input_ram.v ^
  rtl/cnn_mmio_controller.v ^
  rtl/axis_cnn_mnist.v ^
  rtl/conv1_layer.v rtl/conv1_buf.v rtl/conv1_calc.v ^
  rtl/maxpool_relu.v ^
  rtl/conv2_layer.v rtl/conv2_buf.v rtl/conv2_calc.v ^
  rtl/fully_connected.v rtl/comparator.v ^
  sim/cnn_mmio_tb.v
if errorlevel 1 exit /b 1

"%MODELSIM_BIN%\vsim.exe" -c -do "run -all; quit -f" work.cnn_mmio_tb
set SIM_RESULT=%ERRORLEVEL%
popd

exit /b %SIM_RESULT%
