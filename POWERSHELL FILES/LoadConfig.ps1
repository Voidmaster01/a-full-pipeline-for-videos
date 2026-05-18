# Logger.psm1 location:
# Base\POWERSHELL FILES\Logger.psm1

$script:ModuleRoot = Split-Path -Parent $PSScriptRoot

# Base\config.json
$script:ConfigPath = Join-Path $script:ModuleRoot "config.json"

if(!(Test-Path $ConfigPath)){
    throw "Config file missing: $ConfigPath"
}

$Config = Get-Content $ConfigPath -Raw | ConvertFrom-Json

# Base
$Base = $Config.Base

# Main folders
$PS   = Join-Path $Base $Config.Paths.PowerShell
$BAT  = Join-Path $Base $Config.Paths.Batch
$TXT  = Join-Path $Base $Config.Paths.Temp
$LOGS = Join-Path $Base $Config.Paths.Logs

# Common files
$CacheFile     = Join-Path $TXT $Config.Files.CacheFile
$ScanStateFile = Join-Path $TXT $Config.Files.ScanState
$ForceScanFlag = Join-Path $TXT $Config.Files.ForceScanFlag
$PauseFlag     = Join-Path $TXT $Config.Files.PauseFlag
$IdleFlag      = Join-Path $TXT $Config.Files.IdleFlag
$RepairMapFile = Join-Path $TXT $Config.Files.RepairMap
$UploadState   = Join-Path $TXT $Config.Files.UploadState
$MuxQueue      = Join-Path $TXT $Config.Files.MuxQueue

# Logs
$PipelineLog = Join-Path $LOGS $Config.Files.PipelineLog
$DebugLog    = Join-Path $LOGS $Config.Files.DebugLog
$FFmpegLog   = Join-Path $LOGS $Config.Files.FFmpegLog

# Tool executables
$FFMPEG  = $Config.Tools.FFmpeg
$FFPROBE = $Config.Tools.FFprobe
$RCLONE  = $Config.Tools.Rclone