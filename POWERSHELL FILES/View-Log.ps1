# Prevent duplicate execution
$scriptName = [System.IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)

$existing = Get-Process powershell -ErrorAction SilentlyContinue | Where-Object {
    $_.CommandLine -like "*$scriptName*"
}

if ($existing.Count -gt 1) {
    exit
}

# -------------------------
# PATHS
# -------------------------
$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

Import-Module "$ScriptRoot\Logger.psm1" -Force

$PipelineLog = $LogPath
$DebugLog    = $DebugLogPath

Clear-Host

Write-Host "=== LIVE PIPELINE + DEBUG LOG ===" -ForegroundColor Cyan
Write-Host ""

# -------------------------
# ENSURE LOG FILES
# -------------------------
foreach($log in @(
    $pipelineLog,
    $debugLog
)){
    if(!(Test-Path $log)){
        New-Item -ItemType File -Path $log | Out-Null
    }
}

# -------------------------
# PIPELINE LOG WATCHER
# -------------------------
Start-Job -ScriptBlock {

    param($log)

    while(!(Test-Path $log)){
        Write-Host "Waiting for pipeline log..." -ForegroundColor Yellow
        Start-Sleep 2
    }

    Get-Content $log -Wait -Tail 50 | ForEach-Object {

        $line = $_
        $color = "White"

        # -------------------------
        # LEVEL COLORS
        # -------------------------
        if($line -match "\[ERROR\]"){
            $color = "Red"
        }
        elseif($line -match "\[WARNING\]"){
            $color = "Yellow"
        }
        elseif($line -match "\[DEBUG\]"){
            $color = "Gray"
        }
        elseif($line -match "\[TRACE\]"){
            $color = "DarkGray"
        }

        # -------------------------
        # TAG COLORS
        # -------------------------
        elseif($line -match "\[MUX\]"){
            $color = "Cyan"
        }
        elseif($line -match "\[SCAN\]"){
            $color = "Green"
        }
        elseif($line -match "\[CACHE\]"){
            $color = "DarkGreen"
        }
        elseif($line -match "\[VERIFY\]"){
            $color = "Magenta"
        }
        elseif($line -match "\[REPAIR\]"){
            $color = "DarkYellow"
        }
        elseif($line -match "\[RESTORE\]"){
            $color = "DarkCyan"
        }
        elseif($line -match "\[QUEUE\]"){
            $color = "Blue"
        }
        elseif($line -match "\[CLEANER\]"){
            $color = "Yellow"
        }
        elseif($line -match "\[IDLE\]"){
            $color = "DarkMagenta"
        }
        elseif($line -match "\[MAIN\]"){
            $color = "White"
        }

        # -------------------------
        # FALLBACK ERROR DETECTION
        # -------------------------
        if($line -match "(?i)fail|error|missing|corrupt"){
            $color = "Red"
        }

        Write-Host "[PIPE] $line" -ForegroundColor $color
    }

} -ArgumentList $pipelineLog | Out-Null

# -------------------------
# DEBUG LOG WATCHER
# -------------------------
Start-Job -ScriptBlock {

    param($log)

    while(!(Test-Path $log)){
        Write-Host "Waiting for debug log..." -ForegroundColor Yellow
        Start-Sleep 2
    }

    Get-Content $log -Wait -Tail 50 | ForEach-Object {

        $line = $_
        $color = "DarkGray"

        if($line -match "\[ERROR\]"){
            $color = "Red"
        }

        Write-Host "[DEBUG] $line" -ForegroundColor $color
    }

} -ArgumentList $debugLog | Out-Null

# -------------------------
# KEEP MAIN THREAD ALIVE
# -------------------------
while($true){

        Get-Job | Where-Object {
        $_.State -in @("Completed","Failed","Stopped")
    } | Remove-Job -Force

    Receive-Job * | Out-Null

    Start-Sleep 1
}