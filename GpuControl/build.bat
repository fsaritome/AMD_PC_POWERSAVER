@echo off
REM Build GpuControl using GCC (MinGW-w64)
REM Requires: WinLibs GCC installed via winget

set ADLX=%TEMP%\ADLX
set SRC=GpuControl.c
set HELPER=%ADLX%\SDK\ADLXHelper\Windows\C\ADLXHelper.c
set PLATFORM=%ADLX%\SDK\Platform\Windows\WinAPIs.c
set INC=-I%ADLX%
set OUT=GpuControl.exe

echo Building GpuControl...
gcc -O2 -o %OUT% %SRC% %HELPER% %PLATFORM% %INC% -lole32
if %ERRORLEVEL% EQU 0 (
    echo Build successful: %OUT%
) else (
    echo Build FAILED
    exit /b 1
)
