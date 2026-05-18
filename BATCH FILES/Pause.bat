@echo off

set "SCRIPT_DIR=%~dp0"
set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"

call "%SCRIPT_DIR%\LoadConfig.bat"

set "FLAG=%TXT%\pause.flag"

if exist "%FLAG%" (
    del "%FLAG%" >nul 2>&1
    echo =========================
    echo   PIPELINE RESUMED
    echo =========================
) else (
    type nul > "%FLAG%"
    echo =========================
    echo   PIPELINE PAUSED
    echo =========================
)

timeout /t 2 >nul