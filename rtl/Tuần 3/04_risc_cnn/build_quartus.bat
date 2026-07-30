@echo off
setlocal
set "QUARTUS_BIN=E:\Quartus\Data_setup\quartus\bin64"

if exist Q:\de10_riscv_cnn_sample.qpf goto q_mapped
subst Q: "%~dp0"
if errorlevel 1 (
    echo Cannot create temporary Q: mapping.
    echo Remove an old mapping with: subst Q: /d
    exit /b 1
)
:q_mapped

pushd Q:\
"%QUARTUS_BIN%\quartus_sh.exe" --flow compile de10_riscv_cnn_sample
set BUILD_RESULT=%ERRORLEVEL%
popd

exit /b %BUILD_RESULT%
