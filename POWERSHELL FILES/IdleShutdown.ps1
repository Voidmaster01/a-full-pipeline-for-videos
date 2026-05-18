# Prevent duplicate execution
$scriptName = [System.IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)

$existing = Get-Process powershell -ErrorAction SilentlyContinue | Where-Object {
    $_.CommandLine -like "*$scriptName*"
}

if ($existing.Count -gt 1) {
    exit
}

# -------------------------
# LOGGER
# -------------------------
$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

Import-Module "$ScriptRoot\Logger.psm1" -Force

Log "IDLE" "Idle shutdown watcher started" "INFO"


# -------------------------
# SHUTDOWN STATE
# -------------------------
$shutdownPending = $false
$shutdownStart   = $null
$graceSeconds    = 60

# -------------------------
# MUX STATE
# -------------------------
$lastMuxCount = -1
$muxStableCycles = 0

# -------------------------
# REAL IDLE TIMER
# -------------------------
Add-Type @"
using System;
using System.Runtime.InteropServices;

public static class IdleTime {

    [StructLayout(LayoutKind.Sequential)]
    struct LASTINPUTINFO {
        public uint cbSize;
        public uint dwTime;
    }

    [DllImport("user32.dll")]
    static extern bool GetLastInputInfo(ref LASTINPUTINFO plii);

    public static uint GetIdleTime() {

        LASTINPUTINFO lii = new LASTINPUTINFO();

        lii.cbSize = (uint)System.Runtime.InteropServices.Marshal.SizeOf(lii);

        GetLastInputInfo(ref lii);

        return ((uint)Environment.TickCount - lii.dwTime);
    }
}
"@

Log "IDLE" "Smart watcher started" "INFO"

# -------------------------
# MAIN LOOP
# -------------------------
while($true){

    try {

        Log "IDLE" "----- LOOP TICK -----" "TRACE"

        $active = $false

        # -------------------------
        # PAUSE FLAG
        # -------------------------
        if(Test-Path $IdleFlag){

            Log "IDLE" "Pause flag active" "INFO"

            $active = $true
        }

        # -------------------------
        # USER IDLE
        # -------------------------
        $idleMs = [IdleTime]::GetIdleTime()

        $idleMinutes = $idleMs / 1000 / 60

        Log "IDLE" ("User idle: {0:N2} min" -f $idleMinutes) "TRACE"

        if($idleMinutes -lt 45){

            Log "IDLE" "User ACTIVE" "DEBUG"

            $active = $true
        }

        # -------------------------
        # CPU CHECK
        # -------------------------
        try {

            $cpu = (
                Get-Counter '\Processor(_Total)\% Processor Time'
            ).CounterSamples.CookedValue

            Log "IDLE" ("CPU: {0:N2}%" -f $cpu) "TRACE"

            if($cpu -gt 8){
                
                Log "IDLE" "CPU activity detected" "DEBUG"

                $active = $true
            }
        }
        catch {

            Log "IDLE" ("CPU check failed: {0}" -f $_) "ERROR"
        }

        # -------------------------
        # FFMPEG PROCESS CHECK
        # -------------------------
        try {

            $ffmpeg = Get-Process ffmpeg -ErrorAction SilentlyContinue

            if($ffmpeg){

                Log "IDLE" "ffmpeg process active" "DEBUG"

                $active = $true
            }
        }
        catch {

            Log "IDLE" ("ffmpeg process check failed: {0}" -f $_) "ERROR"
        }


# -------------------------
# MUX QUEUE
# -------------------------
if(Test-Path $MuxQueue){

    try {

        $items = Get-Content $MuxQueue -ErrorAction Stop |
                 Where-Object { $_.Trim() -ne "" }

        $count = @($items).Count

        Log "IDLE" ("Mux queue count: {0}" -f $count) "TRACE"

        # -------------------------
        # STABILITY TRACKING
        # -------------------------
        if($count -eq $lastMuxCount){

            $muxStableCycles++
        }
        else {

            $muxStableCycles = 0
        }

        $lastMuxCount = $count

        Log "IDLE" ("Mux stable cycles: {0}" -f $muxStableCycles) "DEBUG"

        # -------------------------
        # ACTIVE ONLY IF CHANGING
        # -------------------------
        if($count -gt 0 -and $muxStableCycles -lt 3){

            Log "IDLE" "Mux queue active" "DEBUG"

            $active = $true
        }
    }
    catch {

        Log "IDLE" ("Mux queue read FAILED: {0}" -f $_) "ERROR"
    }
}

        # -------------------------
        # FINAL DECISION
        # -------------------------
        if(-not $active){

            Log "IDLE" "System IDLE" "INFO"

            if($idleMinutes -gt 45){

                if(-not $shutdownPending){

                    Log "IDLE" ("Idle threshold met → shutdown in {0}s" -f $graceSeconds) "WARNING"

                    shutdown /a 2>$null
                    shutdown /s /t $graceSeconds

                    $shutdownPending = $true
                    $shutdownStart = Get-Date
                }
                else {

                    $elapsed = (Get-Date) - $shutdownStart

                    $remaining = [math]::Max(
                        0,
                        $graceSeconds - [int]$elapsed.TotalSeconds
                    )

                    Log "IDLE" ("Shutdown pending: {0}s remaining" -f $remaining) "TRACE"
                }
            }
        }
        else {

            Log "IDLE" "System ACTIVE" "INFO"

            if($shutdownPending){

                Log "IDLE" "Activity detected → cancelling shutdown" "WARNING"

                shutdown /a

                $shutdownPending = $false
                $shutdownStart = $null
            }
        }
    }
    catch {

        Log "IDLE" ("UNHANDLED LOOP ERROR: {0}" -f $_) "ERROR"
    }

    Start-Sleep 30
}