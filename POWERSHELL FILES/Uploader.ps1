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

Log "UPLOAD" "Future uploader started" "INFO"

# -------------------------
# REMOTES
# -------------------------
$RemoteOriginal = "gdrive:Uploads/Original"
$RemoteProxy    = "gdrive:Uploads/Proxy"

# -------------------------
# TOOLS
# -------------------------
$Rclone = "rclone"
$FFMPEG = "ffmpeg"
$FFPROBE = "ffprobe"

# -------------------------
# ENSURE PATHS
# -------------------------
foreach($path in @(
    $TopUploadFolder,
    $OriginalsFolder,
    $TempFolder,
    $TempProxyFolder,
    $RepairFolder
)){
    if(!(Test-Path $path)){
        New-Item -ItemType Directory -Path $path | Out-Null

        Log "UPLOAD" ("Created directory: {0}" -f $path) "INFO"
    }
}

# -------------------------
# STATE
# -------------------------
function Get-State {

    if(!(Test-Path $StateFile)){
        return @{}
    }

    try {

        $raw = Get-Content $StateFile -Raw

        if([string]::IsNullOrWhiteSpace($raw)){
            return @{}
        }

        return ConvertFrom-Json $raw -AsHashtable
    }
    catch {

        Log "UPLOAD" ("Failed loading state: {0}" -f $_) "ERROR"

        return @{}
    }
}

function Save-State($state){

    try {

        $temp = "$StateFile.tmp"

        $state |
        ConvertTo-Json -Depth 20 |
        Set-Content $temp

        Move-Item $temp $StateFile -Force

        Log "UPLOAD" "Upload state saved" "DEBUG"
    }
    catch {

        Log "UPLOAD" ("Failed saving state: {0}" -f $_) "ERROR"
    }
}

# -------------------------
# VERIFY CONTAINER
# -------------------------
function Test-Moov($file){

    if(!(Test-Path $file)){
        return $false
    }

    try {

        & $FFPROBE -v error `
            -show_entries format=duration `
            -of default=noprint_wrappers=1:nokey=1 `
            "$file" > $null 2>&1

        return ($LASTEXITCODE -eq 0)
    }
    catch {

        return $false
    }
}

# -------------------------
# CREATE PROXY
# -------------------------
function New-Proxy($original){

    Log "UPLOAD" ("BEGIN proxy generation: {0}" -f $original) "INFO"

    if(!(Test-Path $original)){

        Log "UPLOAD" ("Original missing: {0}" -f $original) "ERROR"

        return $null
    }

    $name = [IO.Path]::GetFileNameWithoutExtension($original)

    $proxyOut = Join-Path $TempProxyFolder "$name`_Proxy.mp4"

    if(Test-Path $proxyOut){
        Remove-Item $proxyOut -Force
    }

    try {
        & $FFMPEG -y -err_detect ignore_err -fflags +discardcorrupt -i "$original" -vf "scale=-2:720" -c:v h264_nvenc -preset p4 -cq 28 -bf 0 -pix_fmt yuv420p -c:a aac -b:a 128k -movflags +faststart "$proxyOut"

        if(!(Test-Path $proxyOut)){

            Log "UPLOAD" "Proxy generation failed (missing output)" "ERROR"

            return $null
        }

        if(!(Test-Moov $proxyOut)){

            Log "UPLOAD" "Proxy moov verification FAILED" "ERROR"

            Remove-Item $proxyOut -Force -ErrorAction SilentlyContinue

            return $null
        }

        Log "UPLOAD" ("Proxy generated successfully: {0}" -f $proxyOut) "INFO"

        return $proxyOut
    }
    catch {

        Log "UPLOAD" ("Proxy generation FAILED: {0}" -f $_) "ERROR"

        return $null
    }
}

            # -------------------------
            # UPLOAD FILE
            # -------------------------
            function Send-Upload($local,$remote){

                Log "UPLOAD" ("Uploading: {0}" -f $local) "INFO"

                try {

                    & $Rclone copy `
                        "$local" `
                        "$remote" `
                        --progress `
                        --stats=5s

                    if($LASTEXITCODE -ne 0){

                        Log "UPLOAD" ("Upload FAILED: {0}" -f $local) "ERROR"

                        return $false
                    }

                    Log "UPLOAD" ("Upload completed: {0}" -f $local) "INFO"

                    return $true
                }
                catch {

                    Log "UPLOAD" ("Upload exception: {0}" -f $_) "ERROR"

                    return $false
                }
            }

            # -------------------------
            # MAIN LOOP
            # -------------------------
            while($true){

                try {

                    # -------------------------
                    # PAUSE
                    # -------------------------
                    if(Test-Path $PauseFlag){

                        Log "UPLOAD" "Pause flag active" "WARNING"

                        while(Test-Path $PauseFlag){
                            Start-Sleep 5
                        }

                        Log "UPLOAD" "Pause cleared" "INFO"
                    }

                    $state = Get-State

                    # -------------------------
                    # FIND ORIGINALS
                    # -------------------------
                    $files = Get-ChildItem $OriginalsFolder -Recurse -File |
                            Where-Object {
                                $_.Extension -match "\.(mp4|mkv)$"
                            }

                    foreach($file in $files){

                $path = $file.FullName

                Log "UPLOAD" ("Evaluating file: {0}" -f $path) "TRACE"

                if($state.ContainsKey($path)){

                    Log "UPLOAD" "Already uploaded, skipping" "TRACE"

                    continue
                }

                # -------------------------
                # VERIFY ORIGINAL
                # -------------------------
                if(!(Test-Moov $path)){

                    Log "UPLOAD" ("Original verification FAILED: {0}" -f $path) "ERROR"

                    try {

                        $dest = Join-Path $RepairFolder $file.Name

                        Move-Item $path $dest -Force

                        Log "UPLOAD" ("Moved broken original to repair: {0}" -f $dest) "WARNING"
                    }
                    catch {

                        Log "UPLOAD" ("Repair move FAILED: {0}" -f $_) "ERROR"
                    }

                    continue
                }

                # -------------------------
                # GENERATE PROXY FIRST
                # -------------------------
                $proxy = New-Proxy $path

                if([string]::IsNullOrWhiteSpace($proxy)){

                    Log "UPLOAD" "Proxy generation failed - upload skipped" "ERROR"

                    continue
                }

                # -------------------------
                # UPLOAD ORIGINAL
                # -------------------------
                $okOriginal = Send-Upload $path $RemoteOriginal

                # -------------------------
                # UPLOAD PROXY
                # -------------------------
                $okProxy = $false

                if($okOriginal){

                    $okProxy = Send-Upload $proxy $RemoteProxy
                }

                # -------------------------
                # CLEAN TEMP PROXY
                # -------------------------
                try {

                    if(Test-Path $proxy){

                        Remove-Item $proxy -Force

                        Log "UPLOAD" ("Temporary proxy removed: {0}" -f $proxy) "DEBUG"
                    }
                }
                catch {

                    Log "UPLOAD" ("Temp proxy cleanup FAILED: {0}" -f $_) "ERROR"
                }

                # -------------------------
                # MARK COMPLETE
                # -------------------------
                if($okOriginal -and $okProxy){

                    $state[$path] = @{
                        Uploaded = (Get-Date)
                        Proxy = $true
                    }

                    Save-State $state

                    Log "UPLOAD" ("Upload chain completed: {0}" -f $path) "INFO"
                }
                else {

                    Log "UPLOAD" ("Upload chain incomplete: {0}" -f $path) "WARNING"
                }
            }

            }
            catch {

                Log "UPLOAD" ("UNHANDLED LOOP ERROR: {0}" -f $_) "ERROR"
            }

            Start-Sleep 15
            }