# =========================================================
# Load Central Config
# =========================================================

$script:ModuleRoot = Split-Path -Parent $PSScriptRoot
$script:ConfigPath = Join-Path $script:ModuleRoot "config.json"

if (!(Test-Path $script:ConfigPath)) {
    throw "Missing config file: $script:ConfigPath"
}

$script:Config = Get-Content $script:ConfigPath -Raw | ConvertFrom-Json

# =========================================================
# Shared Base Paths
# =========================================================

$script:Initialized = $false
$script:LastLogLine = $null
$script:RepeatCount = 0

$Global:Base = $script:Config.Base

$Global:PS   = Join-Path $Global:Base $script:Config.Paths.PowerShell
$Global:BAT  = Join-Path $Global:Base $script:Config.Paths.Batch
$Global:TXT  = Join-Path $Global:Base $script:Config.Paths.Temp
$Global:LOGS = Join-Path $Global:Base $script:Config.Paths.Logs

# =========================================================
# Shared Files
# =========================================================

$Global:CacheFile     = Join-Path $Global:TXT $script:Config.Files.CacheFile
$Global:ScanStateFile = Join-Path $Global:TXT $script:Config.Files.ScanState
$Global:RepairMapFile = Join-Path $Global:TXT $script:Config.Files.RepairMap
$Global:MuxQueue      = Join-Path $Global:TXT $script:Config.Files.MuxQueue
$Global:TempOriginal  = Join-Path $Global:Base $script:Config.Paths.TempOriginal
$Global:TempProxy     = Join-Path $Global:Base $script:Config.Paths.TempProxy
$Global:Processed     = Join-Path $Global:Base $script:Config.Paths.Processed
$Global:RepairQueue   = Join-Path $Global:Base $script:Config.Paths.RepairQueue

# =========================================================
# Logs
# =========================================================

$Global:LogPath      = Join-Path $Global:LOGS $script:Config.Files.PipelineLog
$Global:DebugLogPath = Join-Path $Global:LOGS $script:Config.Files.DebugLog

$script:ServiceLogs = @{

    "SCAN"    = Join-Path $Global:LOGS "scanner.log"
    "REPAIR"  = Join-Path $Global:LOGS "repair.log"
    "RESTORE" = Join-Path $Global:LOGS "restore.log"
    "CLEANER" = Join-Path $Global:LOGS "cleaner.log"
    "IDLE"    = Join-Path $Global:LOGS "idle.log"
    "UPLOAD"  = Join-Path $Global:LOGS "uploader.log"
    "MUX"     = Join-Path $Global:LOGS "muxer.log"
}

$Global:FFmpegLog    = Join-Path $Global:LOGS $script:Config.Files.FFmpegLog

# =========================================================
# Flags
# =========================================================

$Global:VerboseFlag = Join-Path $Global:TXT "verbose.flag"
$Global:IdleFlag    = Join-Path $Global:TXT $script:Config.Files.IdleFlag
$Global:PauseFlag   = Join-Path $Global:TXT $script:Config.Files.PauseFlag
$Global:ForceScanFlag = Join-Path $Global:TXT $script:Config.Files.ForceScanFlag

# =========================================================
# Tools
# =========================================================

$Global:FFMPEG  = $script:Config.Tools.ffmpeg
$Global:FFPROBE = $script:Config.Tools.ffprobe
$Global:RCLONE  = $script:Config.Tools.rclone

# =========================================================
# Path Functions
# =========================================================

$Global:RepairQueue =
    Join-Path $Global:Base $script:Config.Paths.RepairQueue

$Global:RepairArchive =
    Join-Path $Global:Base $script:Config.Paths.RepairArchive
function Get-PipelineLogPath {
    return $Global:LogPath
}

function Get-DebugLogPath {
    return $Global:DebugLogPath
}

function Get-FFmpegLogPath {
    return $Global:FFmpegLog
}

# -------------------------
# INIT
# -------------------------
function Initialize-Logger {

        foreach($dir in @(
            $Global:LOGS,
            $Global:TXT
        )){
            if(!(Test-Path $dir)){

                New-Item -ItemType Directory -Path $dir -Force | Out-Null
            }
        }

    if($script:Initialized){
        return
    }

    $script:Initialized = $true

    try {

        $logDir = $Global:LOGS

        if(!(Test-Path $logDir)){
            New-Item -ItemType Directory -Path $logDir -Force | Out-Null
        }

# -------------------------
# CREATE LOG FILES
# -------------------------

$allLogs = @()

$allLogs += $Global:LogPath
$allLogs += $Global:DebugLogPath

foreach($key in $script:ServiceLogs.Keys){

    $allLogs += $script:ServiceLogs[$key]
}

foreach($file in $allLogs){

    try {

        $parent = Split-Path $file -Parent

        if(!(Test-Path $parent)){

            New-Item `
                -ItemType Directory `
                -Path $parent `
                -Force | Out-Null
        }

        if(!(Test-Path $file)){

            New-Item `
                -ItemType File `
                -Path $file `
                -Force | Out-Null
        }
    }
    catch {

        Write-Host "Failed creating log file: $file | $_" -ForegroundColor Red
    }
}
    }
    catch {

        Write-Host "Logger initialization FAILED: $_" -ForegroundColor Red
    }
}

# -------------------------
# VERBOSE STATE
# -------------------------
function Get-VerboseEnabled {

    return (Test-Path $Global:VerboseFlag)
}

# -------------------------
# LOG ROTATION
# -------------------------
function Invoke-LogRotation {

    try {

        if(!(Test-Path $Global:LogPath)){
            return
        }

        $sizeMB = (Get-Item $Global:LogPath).Length / 1MB

        if($sizeMB -lt 5){
            return
        }

        $archive = "$Global:Base\logs\pipeline_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"

        Move-Item $Global:LogPath $archive -Force

        New-Item -ItemType File -Path $Global:LogPath | Out-Null

        # keep newest 5 archives
        Get-ChildItem "$Global:Base\logs\pipeline_*.log" |
        Sort-Object LastWriteTime -Descending |
        Select-Object -Skip 5 |
        Remove-Item -Force
    }
    catch {}
}

# -------------------------
# COLOR RESOLUTION
# -------------------------
function Get-LogColor($tag,$level,$msg){

    if($level -eq "ERROR"){
        return "Red"
    }

    if($level -eq "WARNING"){
        return "Yellow"
    }

    if($level -eq "DEBUG"){
        return "Gray"
    }

    if($level -eq "TRACE"){
        return "DarkGray"
    }

    switch($tag){

        "MUX"      { return "Cyan" }
        "SCAN"     { return "Green" }
        "CACHE"    { return "DarkGreen" }
        "VERIFY"   { return "Magenta" }
        "CLEANER"  { return "Yellow" }
        "IDLE"     { return "DarkMagenta" }
        "MAIN"     { return "White" }
        "QUEUE"    { return "Blue" }
        "REPAIR"   { return "DarkYellow" }
        "RESTORE"  { return "DarkCyan" }

        default {

            if($msg -match "(?i)fail|error|missing|corrupt"){
                return "Red"
            }

            return "White"
        }
    }
}

# -------------------------
# MAIN LOGGER
# -------------------------
function Log {

    param(
        [string]$tag,
        [string]$msg,
        [string]$level = "INFO"
    )

    Initialize-Logger

    if([string]::IsNullOrWhiteSpace($msg)){
        return
    }

    $msg = $msg.Trim()

    # -------------------------
    # VERBOSE FILTER
    # -------------------------
    if($level -eq "TRACE" -or $level -eq "VERBOSE"){

        if(-not (Get-VerboseEnabled)){
            return
        }
    }

    Invoke-LogRotation

    $time = Get-Date -Format "HH:mm:ss"

    $line = "[$time][$tag][$level] $msg"

    # -------------------------
    # DEDUP
    # -------------------------
    $compare = "[$tag][$level] $msg"

    if($compare -eq $script:LastLogLine){

        $script:RepeatCount++

        return
    }

    if($script:RepeatCount -gt 0){

        $repeat = "[$time][LOGGER][INFO] Previous message repeated $script:RepeatCount times"

        try {
            [System.IO.File]::AppendAllText(
                $Global:LogPath,
                $repeat + [Environment]::NewLine
            )
        }
        catch {}

        Write-Host $repeat -ForegroundColor DarkGray

        $script:RepeatCount = 0
    }

    $script:LastLogLine = $compare

    # -------------------------
    # COLOR
    # -------------------------
    $color = Get-LogColor $tag $level $msg

    Write-Host $line -ForegroundColor $color

    # -------------------------
    # WRITE PIPELINE
    # -------------------------
    try {

        [System.IO.File]::AppendAllText(
            $Global:LogPath,
            $line + [Environment]::NewLine
        )
    }
    catch {}

        # -------------------------
        # SERVICE LOG
        # -------------------------
        if($script:ServiceLogs[$tag]){

            try {

                [System.IO.File]::AppendAllText(
                    $script:ServiceLogs[$tag],
                    $line + [Environment]::NewLine
                )
            }
            catch {}
        }

    # -------------------------
    # DEBUG LOG
    # -------------------------
    if($level -eq "DEBUG"){

        try {

            [System.IO.File]::AppendAllText(
                $Global:DebugLogPath,
                $line + [Environment]::NewLine
            )
        }
        catch {}
    }
}

# -------------------------
# GLOBAL ERROR HANDLER
# -------------------------
$ErrorActionPreference = "Stop"

trap {

    Write-Host "[LOGGER][FATAL] $_" -ForegroundColor Red

    continue
}

Export-ModuleMember -Function @(
    "Log",
    "Get-VerboseEnabled",
    "Get-PipelineLogPath",
    "Get-DebugLogPath",
    "Get-FFmpegLogPath"
)
