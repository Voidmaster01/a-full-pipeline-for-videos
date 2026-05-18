@echo off
setlocal EnableDelayedExpansion

REM =========================================================
REM VIDEO PIPELINE LAUNCHER
REM Fixed version for GUI supervision compatibility.
REM
REM CHANGES:
REM - Removes wt new-tab detachment
REM - Keeps process tree attached
REM - Allows GUI stop button to work
REM - Launches background workers cleanly
REM =========================================================

cd /d "%~dp0"

REM =========================================================
REM PATHS
REM =========================================================

set "ROOT=%~dp0.."
for %%I in ("%ROOT%") do set "ROOT=%%~fI"

set "PS_FOLDER=%ROOT%\POWERSHELL FILES"
set "BATCH_FOLDER=%ROOT%\BATCH FILES"
set "LOG_FOLDER=%ROOT%\logs"


REM =========================================================
REM CREATE LOGS FOLDER
REM =========================================================

if not exist "%LOG_FOLDER%" (
mkdir "%LOG_FOLDER%"
)

REM =========================================================
REM START MAIN SERVICES
REM
REM IMPORTANT:
REM Use START /B instead of:
REM - wt new-tab
REM - start powershell
REM
REM This preserves the process tree so the GUI
REM can terminate everything correctly.
REM =========================================================

start /B powershell.exe -ExecutionPolicy Bypass -WindowStyle Hidden -File "%PS_FOLDER%\MediaScanner.ps1"

start /B powershell.exe -ExecutionPolicy Bypass -WindowStyle Hidden -File "%PS_FOLDER%\RepairRestore.ps1"

start /B powershell.exe -ExecutionPolicy Bypass -WindowStyle Hidden -File "%PS_FOLDER%\IdleShutdown.ps1"

start /B powershell.exe -ExecutionPolicy Bypass -WindowStyle Hidden -File "%PS_FOLDER%\FileCleaner.ps1"

REM =========================================================
REM START MUXER
REM =========================================================

if exist "%~dp0BATCH FILES\Auto-Muxer.bat" (
start /B cmd.exe /c ""%~dp0BATCH FILES\Auto-Muxer.bat""
)

REM =========================================================
REM START LOG VIEWERS IF NEEDED
REM =========================================================

REM These are optional now because the GUI
REM already embeds logs internally.

REM start /B powershell.exe -ExecutionPolicy Bypass -WindowStyle Hidden -File "%PS_FOLDER%\View-Log.ps1"
REM start /B powershell.exe -ExecutionPolicy Bypass -WindowStyle Hidden -File "%PS_FOLDER%\View-ffLog.ps1"

REM =========================================================
REM OPTIONAL:
REM Start uploader separately from GUI.
REM Do NOT auto-start here if uploader is meant
REM to remain independent.
REM =========================================================

REM start /B powershell.exe -ExecutionPolicy Bypass -WindowStyle Hidden -File "%PS_FOLDER%\Uploader.ps1"

REM =========================================================
REM SUPPORTING BATCH SYSTEMS
REM =========================================================

if exist "%~dp0BATCH FILES\LoadConfig.bat" (
start /B cmd.exe /c ""%~dp0BATCH FILES\LoadConfig.bat""
)

REM =========================================================
REM KEEP BATCH PROCESS ALIVE
REM
REM This is critical.
REM Without this loop the BAT exits immediately
REM and the GUI loses ownership.
REM =========================================================

:KEEPALIVE

timeout /t 5 /nobreak >nul

goto KEEPALIVE
