@echo off

REM Current config loader location
set "SCRIPT_DIR=%~dp0"
set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"

REM Parent folder = pipeline root
for %%I in ("%SCRIPT_DIR%\..") do set "BASE=%%~fI"

REM Shared folders
set "PS=%BASE%\POWERSHELL FILES"
set "BAT=%BASE%\BATCH FILES"
set "TXT=%BASE%\TEMP AND TEXT FILES"
set "LOGS=%BASE%\logs"

REM Logs
set "PIPELINE_LOG=%LOGS%\pipeline.log"
set "DEBUG_LOG=%LOGS%\debug.log"
set "FFMPEG_LOG=%LOGS%\ffmpeg.log"