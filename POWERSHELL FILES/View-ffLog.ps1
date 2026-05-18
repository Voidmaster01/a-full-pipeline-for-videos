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

$Log = $FFmpegLog

Clear-Host

Write-Host "=== LIVE FFMPEG LOG ===" -ForegroundColor Cyan
Write-Host ""

# -------------------------
# WAIT FOR LOG
# -------------------------
while(-not (Test-Path $Log)){

    Write-Host "Waiting for ffmpeg log..." -ForegroundColor Yellow

    Start-Sleep 2
}

# -------------------------
# LIVE LOG VIEW
# -------------------------
Get-Content $Log -Wait -Tail 50 | ForEach-Object {

    $line = $_
    $color = "DarkGray"

    # -------------------------
    # ERROR DETECTION
    # -------------------------
    if($line -match "(?i)error|failed|invalid|corrupt"){

        $color = "Red"
    }
    elseif($line -match "(?i)warning"){

        $color = "Yellow"
    }

    # -------------------------
    # FFMPEG STATUS
    # -------------------------
    elseif($line -match "frame=\s*\d+"){

        $color = "Green"
    }
    elseif($line -match "Input #|Output #"){

        $color = "Cyan"
    }
    elseif($line -match "Stream #"){

        $color = "DarkCyan"
    }
    elseif($line -match "\.(mkv|mp4|mov|avi)"){

        $color = "Magenta"
    }
    elseif($line -match "Press \[q\] to stop"){

        $color = "Gray"
    }

    Write-Host $line -ForegroundColor $color
}