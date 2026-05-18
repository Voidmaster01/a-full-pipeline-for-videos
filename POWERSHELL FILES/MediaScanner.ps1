# MediaScanner.ps1
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

Log "SCAN" "Media scanner started" "INFO"

# Weekly scan
$scanIntervalMinutes = 10080

# -------------------------
# ENSURE PATHS
# -------------------------
foreach($path in @(
    $RepairFolder
)){
    Log "SCAN" "PATH = [$path]" "DEBUG"
    if([string]::IsNullOrWhiteSpace($path)){
    Log "SCAN" "Skipping null path entry" "WARNING"
    continue
}

if(!(Test-Path $path)){
        New-Item -ItemType Directory -Path $path | Out-Null
        Log "INIT" "Created directory: $path" "INFO"
    }
}

foreach($file in @(
    $CacheFile,
    $ScanStateFile,
    $RepairMapFile
)){
    if(!(Test-Path $file)){
        New-Item -ItemType File -Path $file | Out-Null
        Log "INIT" "Created file: $file" "INFO"
    }
}


# -------------------------
# LAST SCAN INIT
# -------------------------
Log "SCAN" "BEGIN ScanState initialization" "TRACE"

try {

    $raw = Get-Content $ScanStateFile -ErrorAction SilentlyContinue | Select-Object -First 1

    if([string]::IsNullOrWhiteSpace($raw)){
        throw "Empty scan state"
    }

    $lastScan = Get-Date $raw

    Log "SCAN" ("Parsed last scan time: {0}" -f $lastScan) "DEBUG"
}
catch {

    Log "SCAN" "No valid scan state found - forcing initial scan" "WARNING"

    $lastScan = (Get-Date).AddMinutes(-$scanIntervalMinutes)
}

$nextScan = $lastScan.AddMinutes($scanIntervalMinutes)

Log "SCAN" ("Next scan scheduled: {0}" -f $nextScan) "INFO"
Log "SCAN" "END ScanState initialization" "TRACE"

# -------------------------
# CACHE
# -------------------------
function Get-Cache {

    Log "CACHE" "BEGIN Get-Cache" "TRACE"

    $cache = @{}

    if(!(Test-Path $CacheFile)){
        New-Item -ItemType File -Path $CacheFile | Out-Null
        return $cache
    }

    try {

        foreach($line in Get-Content $CacheFile){

            if([string]::IsNullOrWhiteSpace($line)){
                continue
            }

            if($line -notmatch "\|"){
                continue
            }

            $parts = $line -split "\|"

            if($parts.Count -lt 3){
                continue
            }

            $path   = $parts[0]
            $time   = $parts[1]
            $status = $parts[2]

            $cache[$path] = @{
                Time = $time
                Status = $status
            }
        }
    }
    catch {
        Log "CACHE" ("Cache load FAILED: {0}" -f $_) "ERROR"
    }

    Log "CACHE" ("Loaded cache entries: {0}" -f $cache.Count) "DEBUG"
    Log "CACHE" "END Get-Cache" "TRACE"

    return $cache
}

# -------------------------
# CACHE WRITE
# -------------------------
function Save-Cache($cache){

    Log "CACHE" "BEGIN Save-Cache" "TRACE"

    try {

        $lines = foreach($entry in $cache.GetEnumerator()){

                if(!(Test-Path $entry.Key)){
                    continue
                }

                "{0}|{1}|{2}" -f $entry.Key,$entry.Value.Time,$entry.Value.Status
            }

        [System.IO.File]::WriteAllLines($CacheFile, $lines)

        Log "CACHE" ("Cache saved: {0} entries" -f $cache.Count) "INFO"
    }
    catch {
        Log "CACHE" ("Save FAILED: {0}" -f $_) "ERROR"
    }

    Log "CACHE" "END Save-Cache" "TRACE"
}

# -------------------------
# VIDEO VERIFY
# -------------------------
function Test-Video($file){

    Log "VERIFY" ("BEGIN Test-Video: {0}" -f $file) "TRACE"

    if(!(Test-Path $file)){
        Log "VERIFY" ("Missing file: {0}" -f $file) "ERROR"
        return $false
    }

    try {

        $result = & ffprobe -v error `
            -show_entries format=duration `
            -of default=noprint_wrappers=1:nokey=1 `
            "$file" 2>&1

        if([string]::IsNullOrWhiteSpace($result)){
            Log "VERIFY" ("No duration returned: {0}" -f $file) "ERROR"
            return $false
        }

        [double]$duration = 0

        if([double]::TryParse($result,[ref]$duration)){
            Log "VERIFY" ("Container valid ({0}s): {1}" -f $duration,$file) "DEBUG"
        }

        return $true
    }
    catch {

        Log "VERIFY" ("Verification FAILED: {0} | {1}" -f $file,$_ ) "ERROR"

        return $false
    }
}

# -------------------------
# FILE STABILITY
# -------------------------
function Wait-FileReady($file){

    $lastSize = -1

    for($i = 0; $i -lt 5; $i++){

        if(!(Test-Path $file)){
            return $false
        }

        try {
            $size = (Get-Item $file).Length
        }
        catch {
            return $false
        }

        if($size -eq $lastSize){
            return $true
        }

        $lastSize = $size

        Start-Sleep 3
    }

    return $false
}

# -------------------------
# REPAIR MAP LOAD
# -------------------------
function Get-RepairMap {

    Log "REPAIR" "BEGIN Get-RepairMap" "TRACE"

    if(!(Test-Path $RepairMapFile)){
        return @{}
    }

    try {

        $raw = Get-Content $RepairMapFile -Raw -ErrorAction SilentlyContinue

        if([string]::IsNullOrWhiteSpace($raw)){
            return @{}
        }

        $obj = $raw | ConvertFrom-Json

        $map = @{}

        foreach($prop in $obj.PSObject.Properties){

            $map[$prop.Name] = @{
                OriginalPath = $prop.Value.OriginalPath
                RepairPath   = $prop.Value.RepairPath
                Timestamp    = $prop.Value.Timestamp
            }
        }

        Log "REPAIR" ("Loaded repair entries: {0}" -f $map.Count) "DEBUG"

        return $map
    }
    catch {

        Log "REPAIR" ("Repair map load FAILED: {0}" -f $_) "ERROR"

        return @{}
    }
}
# -------------------------
# REPAIR MAP SAVE
# -------------------------
function Save-RepairMap($map){

    Log "REPAIR" "BEGIN Save-RepairMap" "TRACE"

    try {

        $json = $map | ConvertTo-Json -Depth 5

        [System.IO.File]::WriteAllText($RepairMapFile,$json)

        Log "REPAIR" ("Repair map saved: {0} entries" -f $map.Count) "INFO"
    }
    catch {

        Log "REPAIR" ("Repair map save FAILED: {0}" -f $_) "ERROR"
    }
}

# -------------------------
# ADD REPAIR ENTRY
# -------------------------
function Add-RepairEntry($originalPath,$repairPath){

    Log "REPAIR" ("Caching repair entry: {0}" -f $originalPath) "INFO"

    $map = Get-RepairMap

    $name = [IO.Path]::GetFileName($originalPath)

    $map[$name] = @{
        OriginalPath = $originalPath
        RepairPath   = $repairPath
        Timestamp    = (Get-Date).ToString("o")
    }

    Save-RepairMap $map
}

# -------------------------
# MAIN SCAN
# -------------------------
function Invoke-MediaScan {

    $root = $ScanRoot

    Log "SCAN" ("BEGIN Invoke-MediaScan root={0}" -f $root) "TRACE"

    $cache = Get-Cache

    $processed = 0
    $updated = 0
    $bad = 0

    $dirs = Get-ChildItem $root -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -ne "1 FULL PROCESS" }

    foreach($dir in $dirs){

        Log "SCAN" ("Scanning directory: {0}" -f $dir.FullName) "TRACE"

        try {

            $files = Get-ChildItem $dir.FullName -Recurse -File -ErrorAction SilentlyContinue |
                     Where-Object { $_.Extension -match "\.(mp4|mkv)$" }
        }
        catch {

            Log "SCAN" ("Directory scan FAILED: {0}" -f $_) "ERROR"
            continue
        }

        foreach($item in $files){

            $processed++

            $path = $item.FullName
            $time = $item.LastWriteTime.ToString("o")

            # Skip tiny files
            if($item.Length -lt 5MB){

                $cache[$path] = @{
                    Time = $time
                    Status = "SMALL"
                }

                continue
            }

            # Cache hit
            if($cache.ContainsKey($path)){

                if($cache[$path].Time -eq $time){
                    continue
                }
            }

            Log "SCAN" ("Processing: {0}" -f $path) "INFO"

            # Wait for file stabilization
            if(!(Wait-FileReady $path)){

                Log "SCAN" ("File unstable: {0}" -f $path) "WARNING"

                continue
            }

            # Verify video
            $valid = Test-Video $path

            if(-not $valid){

                $bad++

                Log "SCAN" ("Invalid media detected: {0}" -f $path) "ERROR"

                try {

                        $dest = Join-Path $RepairFolder ([IO.Path]::GetFileName($path))

                        Add-RepairEntry $path $dest
                    Log "SCAN" ("Added Repair Entry: {0} -> {1}" -f $path, $dest) "DEBUG"

                        Move-Item $path $dest -Force

                    Log "SCAN" ("Moved to repair: {0}" -f $dest) "WARNING"
                }
                catch {
                    Log "SCAN" ("Repair move FAILED: {0}" -f $_) "ERROR"
                }

                $cache[$path] = @{
                    Time = $time
                    Status = "BAD"
                }

                continue
            }

            $status = "MEDIA_OK"

            $cache[$path] = @{
                Time = $time
                Status = $status
            }

            $updated++

            Log "SCAN" ("Cached [{0}]: {1}" -f $status,$path) "INFO"
        }
    }

    Save-Cache $cache

    Log "SCAN" ("Processed: {0}" -f $processed) "INFO"
    Log "SCAN" ("Updated cache entries: {0}" -f $updated) "INFO"
    Log "SCAN" ("Bad files: {0}" -f $bad) "INFO"

    Log "SCAN" "END Invoke-MediaScan" "TRACE"
}

# -------------------------
# MAIN LOOP
# -------------------------
while($true){

    try {

        Log "MAIN" "===== LOOP START =====" "TRACE"

        # -------------------------
        # PAUSE
        # -------------------------
        if(Test-Path $PauseFlag){

            Log "MAIN" "Pause flag detected" "WARNING"

            while(Test-Path $PauseFlag){
                Start-Sleep 2
            }

            Log "MAIN" "Pause cleared" "INFO"
        }

        # -------------------------
        # SCAN CHECK
        # -------------------------
        if((Get-Date) -gt $nextScan -or (Test-Path $ForceScanFlag)){

            Log "SCAN" "Scan triggered" "INFO"

            try {

                Invoke-MediaScan

                $lastScan = Get-Date

                $lastScan.ToString("o") | Set-Content $ScanStateFile

                $nextScan = $lastScan.AddMinutes($scanIntervalMinutes)

                Log "SCAN" ("Next scan scheduled: {0}" -f $nextScan) "INFO"

                if(Test-Path $ForceScanFlag){
                    Remove-Item $ForceScanFlag -Force
                    Log "SCAN" "Force scan flag removed" "DEBUG"
                }
            }
            catch {
                Log "SCAN" ("Scan FAILED: {0}" -f $_) "ERROR"
            }
        }
        else {
            Log "SCAN" ("Scan not required yet (next: {0})" -f $nextScan) "TRACE"
        }
    }
    catch {

        Log "MAIN" ("UNHANDLED LOOP ERROR: {0}" -f $_) "ERROR"
    }

    Log "MAIN" "Loop sleep (5s)" "TRACE"

    Start-Sleep 5
}
