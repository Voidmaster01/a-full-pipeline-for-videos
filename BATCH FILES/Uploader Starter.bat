@echo off
title GDrive Uploader
color 0B

set "SCRIPT_DIR=%~dp0"
set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"

call "%SCRIPT_DIR%\LoadConfig.bat"

echo =========================================
echo        STARTING UPLOADER
echo =========================================
echo.

REM -------------------------
REM VERIFY SCRIPT EXISTS
REM -------------------------
if not exist "%PS%\Uploader.ps1" (
    echo ERROR: Uploader.ps1 not found
    echo.
    pause
    exit /b
)

REM -------------------------
REM START POWERSHELL UPLOADER
REM -------------------------
powershell.exe ^
    -NoProfile ^
    -ExecutionPolicy Bypass ^
    -File "%PS%\Uploader.ps1"

echo.
echo Uploader exited.
pause