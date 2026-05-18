# =========================================================
# PIPELINE FIRST-TIME SETUP
# =========================================================

Clear-Host

Write-Host "=== PIPELINE SETUP ===" -ForegroundColor Cyan
Write-Host ""

# =========================================================
# INSTALL LOCATION
# =========================================================

$Base = Read-Host "Enter pipeline install path NO TRAILING BACKSLASH OR QUOTES"

if([string]::IsNullOrWhiteSpace($Base)){
    throw "Install path cannot be empty"
}

# =========================================================
# ENSURE BASE DIRECTORY
# =========================================================

if(!(Test-Path $Base)){

    New-Item -ItemType Directory -Path $Base -Force | Out-Null

    Write-Host "[CREATED] $Base" -ForegroundColor Green
}
else {

    Write-Host "[EXISTS] $Base" -ForegroundColor DarkGray
}

# =========================================================
# TOOL INSTALLATION
# =========================================================

Write-Host ""
Write-Host "=== TOOL INSTALLATION ===" -ForegroundColor Cyan

# =========================================================
# CHOCOLATEY
# =========================================================

$ChocoInstalled = Get-Command choco -ErrorAction SilentlyContinue

if(!$ChocoInstalled){

    Write-Host "Chocolatey not detected." -ForegroundColor Yellow
    Write-Host "Installing Chocolatey..." -ForegroundColor Cyan

    Set-ExecutionPolicy Bypass -Scope Process -Force

    [System.Net.ServicePointManager]::SecurityProtocol = \
        [System.Net.ServicePointManager]::SecurityProtocol -bor 3072

    Invoke-Expression ((New-Object System.Net.WebClient).DownloadString(
        'https://community.chocolatey.org/install.ps1'
    ))

    refreshenv
}

# =========================================================
# FFMPEG
# =========================================================

$FFmpegInstalled = Get-Command ffmpeg -ErrorAction SilentlyContinue

if(!$FFmpegInstalled){

    Write-Host "Installing ffmpeg-full..." -ForegroundColor Cyan

    choco install ffmpeg-full -y
}
else {

    Write-Host "FFmpeg already installed." -ForegroundColor Green
}

# =========================================================
# RCLONE
# =========================================================

$RcloneInstalled = Get-Command rclone -ErrorAction SilentlyContinue

if(!$RcloneInstalled){

    Write-Host "Installing rclone..." -ForegroundColor Cyan

    choco install rclone -y
}
else {

    Write-Host "Rclone already installed." -ForegroundColor Green
}

# =========================================================
# REFRESH ENVIRONMENT
# =========================================================

$env:Path = [System.Environment]::GetEnvironmentVariable(
    "Path",
    "Machine"
) + ";" + [System.Environment]::GetEnvironmentVariable(
    "Path",
    "User"
)

# =========================================================
# TOOL PATHS
# =========================================================

Write-Host ""
Write-Host "=== TOOL SETUP ===" -ForegroundColor Cyan

$FFmpegPath = "ffmpeg"
$FFprobePath = "ffprobe"
$RclonePath = "rclone"

# =========================================================
# SCANNER SETTINGS
# =========================================================

Write-Host ""
Write-Host "=== SCANNER SETTINGS ===" -ForegroundColor Cyan

$ScanIntervalMinutes =
    Read-Host "Scanner interval in minutes (default: 10080)"

if([string]::IsNullOrWhiteSpace($ScanIntervalMinutes)){

    $ScanIntervalMinutes = 10080
}

# =========================================================
# IDLE SETTINGS
# =========================================================

Write-Host ""
Write-Host "=== IDLE SETTINGS ===" -ForegroundColor Cyan

$IdleMinutes =
    Read-Host "Idle minutes before shutdown (default: 45)"

if([string]::IsNullOrWhiteSpace($IdleMinutes)){

    $IdleMinutes = 45
}

$CpuThreshold =
    Read-Host "CPU threshold percentage do not add the percent sign(default: 8%)"

if([string]::IsNullOrWhiteSpace($CpuThreshold)){

    $CpuThreshold = 8
}

$GraceSeconds =
    Read-Host "Shutdown grace seconds (default: 60)"

if([string]::IsNullOrWhiteSpace($GraceSeconds)){

    $GraceSeconds = 60
}

# =========================================================
# CONFIG OBJECT
# =========================================================

$Config = @{

    Version = "1.0.0"

    Base = $Base

    Paths = @{

        PowerShell    = "POWERSHELL FILES"
        Batch         = "BATCH FILES"
        Temp          = "TEMP AND TEXT FILES"
        Logs          = "logs"

        RepairQueue   = "Repair_Queue"
        RepairArchive = "Repair_Archive"

        TempOriginal  = "TempOriginal"
        TempProxy     = "TempProxy"

        Processed     = "Processed"

        Originals     = "Originals"
        Proxy         = "Proxy"

        UploadRoot    = "Top Upload Folder"
    }

    Files = @{

        PipelineLog   = "pipeline.log"
        DebugLog      = "debug.log"
        FFmpegLog     = "ffmpeg.log"

        CacheFile     = "scan_cache.txt"
        ScanState     = "last_scan.txt"
        RepairMap     = "repair_map.json"
        MuxQueue      = "mux_queue.txt"

        PauseFlag     = "pause.flag"
        IdleFlag      = "idle.flag"
        ForceScanFlag = "force_scan.flag"
    }

    Tools = @{

        FFmpeg  = $FFmpegPath
        FFprobe = $FFprobePath
        Rclone  = $RclonePath
    }

    Scanner = @{

        ScanIntervalMinutes = 10080
    }

    Idle = @{

        IdleMinutes = 45
        CpuThreshold = 8
        GraceSeconds = 60
    }
}

# =========================================================
# SAVE CONFIG
# =========================================================

$ConfigPath = Join-Path $Base "config.json"

$Config |
ConvertTo-Json -Depth 20 |
Set-Content $ConfigPath

Write-Host ""
Write-Host "Config created:" -ForegroundColor Green
Write-Host $ConfigPath -ForegroundColor White

# =========================================================
# RCLONE SETUP
# =========================================================

Write-Host ""
Write-Host "=== RCLONE SETUP ===" -ForegroundColor Cyan

$rcloneCheck = Get-Command $RclonePath -ErrorAction SilentlyContinue

if(!$rcloneCheck){

    Write-Host "Rclone not found." -ForegroundColor Red
    Write-Host "Install rclone first, then rerun setup." -ForegroundColor Yellow
}
else {

    Write-Host "Launching rclone config..." -ForegroundColor Green

    Start-Process powershell -ArgumentList @(
        "-NoExit",
        "-Command",
        "& '$RclonePath' config"
    )

    Write-Host ""
    Write-Host "After completing rclone setup:" -ForegroundColor Cyan
    Write-Host "1. Close the rclone config window" -ForegroundColor White
    Write-Host "2. Return here and press ENTER" -ForegroundColor White

    Read-Host

    Write-Host ""
    Write-Host "Available remotes:" -ForegroundColor Cyan

    & $RclonePath listremotes

    Write-Host ""

    $OriginalRemote = Read-Host "Enter ORIGINAL upload remote"
    $ProxyRemote = Read-Host "Enter PROXY upload remote"

    $Config.Upload = @{

        OriginalRemote = $OriginalRemote
        ProxyRemote = $ProxyRemote
    }

    $Config |
    ConvertTo-Json -Depth 20 |
    Set-Content $ConfigPath

    Write-Host ""
    Write-Host "Rclone configuration saved to config.json" -ForegroundColor Green
}

# =========================================================
# VERIFY TOOLS
# =========================================================

Write-Host ""
Write-Host "=== VERIFYING TOOLS ===" -ForegroundColor Cyan

foreach($tool in @(
    $FFmpegPath,
    $FFprobePath,
    $RclonePath
)){

    $found = Get-Command $tool -ErrorAction SilentlyContinue

    if($found){

        Write-Host "[OK] $tool" -ForegroundColor Green
    }
    else {

        Write-Host "[MISSING] $tool" -ForegroundColor Red
    }
}


# =========================================================
    $found = Get-Command $tool -ErrorAction SilentlyContinue

    if($found){

        Write-Host "[OK] $tool" -ForegroundColor Green
    }
    else {

        Write-Host "[MISSING] $tool" -ForegroundColor Red
    }

# =========================================================
# LAUNCH PIPELINE MANAGER
# =========================================================

Write-Host ""
Write-Host "Launching PipelineManager.ps1..." -ForegroundColor Green

copy-Item $ConfigPath (Join-Path $Base "POWERSHELL FILES\config.json") -Force

$PipelineManager = Join-Path $Base "POWERSHELL FILES\PipelineManager.ps1"

if(Test-Path $PipelineManager){

    Start-Process powershell.exe -ArgumentList @(
        "-ExecutionPolicy",
        "Bypass",
        "-File",
        ('"{0}"' -f $PipelineManager)
    )
}
else {

    Write-Host "PipelineManager.ps1 not found." -ForegroundColor Yellow
}

Start-Sleep 5
# =========================================================
# HIDE SETUP FILES
# =========================================================

Write-Host ""
Write-Host "=== FINALIZING SETUP ===" -ForegroundColor Cyan

$SetupFolder = Join-Path $Base ".pipeline_setup"

if(!(Test-Path $SetupFolder)){

    New-Item -ItemType Directory -Path $SetupFolder -Force | Out-Null
}

# Hide setup folder
attrib +h $SetupFolder

# Current setup script
$CurrentSetup = $MyInvocation.MyCommand.Path

# Move setup script
if(Test-Path $CurrentSetup){

    Move-Item $CurrentSetup (Join-Path $SetupFolder "Setup-Pipeline.ps1") -Force
}

# Move launcher BAT if present
$LauncherBat = Join-Path (Split-Path $CurrentSetup) "SetupLauncher.bat"

if(Test-Path $LauncherBat){

    Move-Item $LauncherBat (Join-Path $SetupFolder "SetupLauncher.bat") -Force
}


# =========================================================
# COMPLETE
# =========================================================

Write-Host ""
Write-Host "Pipeline setup complete." -ForegroundColor Green
Write-Host ""
Write-Host "Next step:" -ForegroundColor Cyan
Write-Host "Copy your PS1/BAT files into the generated folders." -ForegroundColor White