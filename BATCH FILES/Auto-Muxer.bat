@echo off
title OBS Auto Muxer
color 0A
setlocal EnableDelayedExpansion

set "SCRIPT_DIR=%~dp0"
set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"

call "%SCRIPT_DIR%\LoadConfig.bat"
set "FFMPEGLOG=%BASE%\logs\ffmpeg.log"
set "MUXER_LOG=%BASE%\logs\muxer.log"
set "DEBUGLOG=%BASE%\logs\debug.log"
set "VERBOSE_FLAG=%TXT%\verbose.flag"
set "VERBOSE=0"
set "FFPROBE=ffprobe"
set "SUCCESS=0"

REM for /f %%A in ('tasklist ^| find /i "cmd.exe" ^| find /c "%~nx0"') do set COUNT=%%A
REM if !COUNT! GTR 1 exit

goto main

REM -------------------------
REM LOG FUNCTION
REM -------------------------

:log
set "TAG=%~1"
set "MSG=%~2"
set "LEVEL=%~3"

if "%TAG%"=="" set "TAG=SYSTEM"
if "%MSG%"=="" set "MSG=(no message)"
if "%LEVEL%"=="" set "LEVEL=INFO"

if exist "%VERBOSE_FLAG%" set VERBOSE=1
if /I "%LEVEL%"=="ERROR" set VERBOSE=1
if /I "%LEVEL%"=="VERBOSE" if "%VERBOSE%"=="0" exit /b

for /f "tokens=1-2 delims= " %%a in ("%time%") do set "T=%%a"
set "LINE=[!T!][!TAG!][!LEVEL!] !MSG!"

REM --- SAFE ECHO (handles special chars) ---
echo(!LINE!

REM --- ROUTE LOGS ---

if /I "!TAG!"=="MUX" (


>>"%MUXER_LOG%" echo(!LINE!


) else (


>>"%FFMPEGLOG%" echo(!LINE!


)

REM --- DEBUG LOG ---

if /I "!LEVEL!"=="DEBUG" (
>>"%DEBUGLOG%" echo(!LINE!
)


exit /b

REM -------------------------
REM SAFE VERIFY (MOOV ONLY)
REM -------------------------

:verify_moov
set "VERIFY_FILE=%~1"
call :log MUX "Loose verify (moov): %VERIFY_FILE%" INFO

%FFPROBE% -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "%VERIFY_FILE%" >nul 2>&1

if errorlevel 1 (
    call :log MUX "MOOV missing: %VERIFY_FILE%" ERROR
    set "SUCCESS=0"
    exit /b 1
)

call :log MUX "MOOV OK: %VERIFY_FILE%" DEBUG
set "SUCCESS=1"
exit /b 0

:main

set "WATCH=%BASE%\Watch"
set "RQUEUE=%BASE%\Repair_Queue"
set "tempOriginal=%BASE%\Temp\Original"
set "PROCESSED=%BASE%\Processed"
set "ARCHIVE=%BASE%\Archive"
set "REPAIR=%BASE%\Repair"
set "MQUEUE=%TXT%\mux_queue.txt"
set "PAUSE_FLAG=%TXT%\pause.flag"


if not exist "%BASE%\logs" mkdir "%BASE%\logs"
if not exist "%FFMPEGLOG%" type nul > "%FFMPEGLOG%"
if not exist "%DEBUGLOG%" type nul > "%DEBUGLOG%"
if not exist "%RQUEUE%" mkdir "%RQUEUE%"
if exist "%MQUEUE%\" ( rmdir /s /q "%MQUEUE%" )
if not exist "%MQUEUE%" ( type nul > "%MQUEUE%" )
if not exist "%tempOriginal%" mkdir "%tempOriginal%"
if not exist "%ARCHIVE%" mkdir "%ARCHIVE%"
if not exist "%PROCESSED%" mkdir "%PROCESSED%"
if not exist "%REPAIR%" mkdir "%REPAIR%"

call :log MUX "Muxer started" INFO

:loop

call :log MUX "Muxer loop check" DEBUG
REM -------------------------
REM PAUSE CHECK
REM -------------------------
if exist "%PAUSE_FLAG%" (
    call :log MUX "PAUSE FLAG DETECTED - pausing muxer..." WARNING

    :pause_wait
    timeout /t 5 >nul

    if exist "%PAUSE_FLAG%" (
        goto pause_wait
    )

    call :log MUX "PAUSE FLAG CLEARED - resuming muxer" INFO
)

set "NEXTFILE="

REM --- Mark as active (mux queue) ---
call :log MUX "Syncing WATCH files into mux queue" TRACE

for %%F in ("%WATCH%\*.mkv") do (
    if exist "%%~F" (
        findstr /x /c:"%%~fF" "%MQUEUE%" >nul 2>&1 || (
            echo %%~fF>> "%MQUEUE%"
        )
    )
)

for %%F in ("%WATCH%\*.mp4") do (
    if exist "%%~fF" (
        findstr /x /c:"%%~fF" "%MQUEUE%" >nul 2>&1 || (
            echo %%~fF>> "%MQUEUE%"
            call :log MUX "WATCH MP4 added to mux queue: %%~fF" DEBUG
        )
    )
)

for %%F in ("%RQUEUE%\*.mkv") do (
    if exist "%%~fF" (
        findstr /x /c:"%%~fF" "%MQUEUE%" >nul 2>&1 || (
            echo %%~fF>> "%MQUEUE%"
            call :log MUX "REPAIR MKV added to mux queue: %%~fF" DEBUG
        )
    )
)

for %%F in ("%RQUEUE%\*.mp4") do (
    if exist "%%~fF" (
        findstr /x /c:"%%~fF" "%MQUEUE%" >nul 2>&1 || (
            echo %%~fF>> "%MQUEUE%"
            call :log MUX "REPAIR MP4 added to mux queue: %%~fF" DEBUG
        )
    )
)

sort "%MQUEUE%" /unique > "%MQUEUE%.tmp"
move /y "%MQUEUE%.tmp" "%MQUEUE%" >nul

for /f "usebackq delims=" %%F in ("%MQUEUE%") do (
    set "NEXTFILE=%%F"
    goto process_next
)

goto after_repair

:process_next

if defined NEXTFILE (
    call :log MUX "Processing queued file: !NEXTFILE!" INFO
    call :process "!NEXTFILE!"
)


:after_repair

timeout /t 5 >nul
goto loop

REM -------------------------
REM PROCESS FILE
REM -------------------------

:process
call :log MUX "Processing Start" DEBUG
set "SUCCESS=0"

if "%~1"=="" (
    call :log MUX "Blank process call detected" ERROR
    exit /b
)

set "FILE=%~1"
call :log MUX "Incoming FILE arg: %~1" TRACE

if not exist "%FILE%" (
    call :log MUX "Input file missing: %FILE%" ERROR
    goto cleanup
)

call :log MUX "Input file exists: %FILE%" DEBUG

set "INPUT=%FILE%"
set "INFILE=%FILE%"

call :log MUX "INPUT set to: !INPUT!" TRACE
call :log MUX "INFILE set to: !INFILE!" TRACE

REM -------------------------
REM REPAIR CACHE
REM -------------------------

call :log MUX "Checking repair cache for: %~nx1" TRACE

REM --- Validate existing repair ---
if exist "%REPAIR%\%~nx1" (

    for %%A in ("%REPAIR%\%~nx1") do (

        call :log MUX "Existing repair size: %%~zA bytes" TRACE

        if %%~zA LSS 1048576 (

            call :log MUX "Repair file too small, rebuilding" WARNING

            del /f /q "%REPAIR%\%~nx1" >nul 2>&1
        )
    )
)

REM --- Rebuild repair if missing ---
if not exist "%REPAIR%\%~nx1" (

    call :log MUX "Repair file missing, rebuilding repair cache" WARNING

    call :log MUX "Running repair ffmpeg pass" INFO

    ffmpeg -y ^
        -fflags +discardcorrupt ^
        -err_detect ignore_err ^
        -i "%FILE%" ^
        -c copy ^
        "%REPAIR%\%~nx1" >> "%FFMPEGLOG%" 2>&1


    call :log MUX "Repair ffmpeg completed" TRACE
)

REM --- Final repair validation ---
if exist "%REPAIR%\%~nx1" (

    call :log MUX "Repair output created successfully" DEBUG

    for %%A in ("%REPAIR%\%~nx1") do (

        call :log MUX "Repair output size: %%~zA bytes" TRACE

        if %%~zA GTR 0 (

            set "INPUT=%REPAIR%\%~nx1"

            call :log MUX "Repair input activated: !INPUT!" INFO
        )
    )

) else (

    call :log MUX "Repair generation FAILED" ERROR
)

REM encode original
call :log MUX "Starting ORIGINAL encode" INFO
call :log MUX "Original encode input: !INPUT!" TRACE
call :log MUX "Original encode output: %tempOriginal%\%~n1.mp4" TRACE

call :log MUX "Testing and Removing Existing Outputs" INFO
if exist "%tempOriginal%\%~n1.mp4" del /f /q "%tempOriginal%\%~n1.mp4"

ffmpeg -y -err_detect ignore_err -fflags +discardcorrupt -i "%INPUT%" -map 0:v -map 0:a? -c:v h264_nvenc -preset p5 -cq 19 -bf 0 -pix_fmt yuv420p -c:a copy -movflags +faststart "%tempOriginal%\%~n1.mp4" >> "%FFMPEGLOG%" 2>&1


call :log MUX "Original encode finished" TRACE

timeout /t 5 >nul

call :log MUX "Checking original output existence" TRACE

if not exist "%tempOriginal%\%~n1.mp4" (
    call :log MUX "Original output missing" ERROR
    goto cleanup
)

call :log MUX "Original output exists" DEBUG

call :verify_moov "%tempOriginal%\%~n1.mp4" || (
    call :log MUX "Original moov verification FAILED" ERROR
    goto cleanup
)

call :log MUX "Original moov verification PASSED" INFO

set "SUCCESS=1"
call :log MUX "Mux verification chain complete" DEBUG

REM move outputs
call :log MUX "Moving completed outputs" INFO

move /y "%tempOriginal%\%~n1.mp4" "%ARCHIVE%" >nul

if errorlevel 1 (
    call :log MUX "FAILED moving original output" ERROR
    set "SUCCESS=0"
)

move /y "%FILE%" "%PROCESSED%" >nul

if errorlevel 1 (
    call :log MUX "FAILED moving source to processed" ERROR
    set "SUCCESS=0"
)

call :log MUX "All file moves completed" DEBUG

REM -------------------------
REM FINAL OUTPUT VALIDATION
REM -------------------------

set "FINAL_ORIGINAL=%ARCHIVE%\%~n1.mp4"

call :log MUX "Validating final delivery output" TRACE

if exist "%FINAL_ORIGINAL%" (

    call :log MUX "Original delivery confirmed: %FINAL_ORIGINAL%" INFO

) else (

    call :log MUX "Original delivery missing: %FINAL_ORIGINAL%" ERROR

    set "SUCCESS=0"
)

:cleanup

call :log MUX "Beginning cleanup phase" TRACE

set "TMP=%MQUEUE%.tmp"

call :log MUX "Cleanup temp queue file: !TMP!" TRACE

type nul > "%TMP%"

call :log MUX "Rebuilding mux queue without current file" TRACE

for /f "usebackq delims=" %%L in ("%MQUEUE%") do (

    set "LINE=%%L"

    if not "!LINE!"=="" (

        if /I not "!LINE!"=="!INFILE!" (

            echo !LINE!>> "%TMP%"
        )
    )
)


REM --- Ensure target is not a folder ---
if exist "%MQUEUE%\" (
    call :log MUX "MQUEUE incorrectly exists as directory, removing" ERROR
    rmdir /s /q "%MQUEUE%"
)

call :log MUX "Replacing mux queue with cleaned queue" TRACE

move /y "%TMP%" "%MQUEUE%" >nul

if errorlevel 1 (
    call :log MUX "FAILED replacing mux queue" ERROR
) else (
    call :log MUX "Mux CLEANUP removed: !INFILE!" DEBUG
)

if "!SUCCESS!"=="1" (
    call :log MUX "Completed: %~n1" INFO
) else (
    call :log MUX "FAILED: %~n1" ERROR
)

exit /b

call :log MUX "Basic" INFO