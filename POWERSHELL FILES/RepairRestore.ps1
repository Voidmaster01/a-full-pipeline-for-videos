# RepairRestore.ps1

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

Log "REPAIR" "Repair restore service started" "INFO"

# -------------------------
# ENSURE PATHS
# -------------------------
foreach($path in @(
    $RepairArchive
)){
    Log "SCAN" "PATH = [$path]" "DEBUG"
    if([string]::IsNullOrWhiteSpace($path)){
    Log "SCAN" "Skipping null path entry" "WARNING"
    continue
}

if(!(Test-Path $path)){

        New-Item -ItemType Directory -Path $path | Out-Null

        Log "INIT" ("Created directory: {0}" -f $path) "INFO"
    }
}

if(!(Test-Path $RepairMapFile)){

    "{}" | Set-Content $RepairMapFile

    Log "INIT" ("Created repair map: {0}" -f $RepairMapFile) "INFO"
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

    try {

        $json = $map | ConvertTo-Json -Depth 5

        [System.IO.File]::WriteAllText($RepairMapFile,$json)

        Log "REPAIR" ("Repair map saved: {0} entries" -f $map.Count) "DEBUG"
    }
    catch {

        Log "REPAIR" ("Repair map save FAILED: {0}" -f $_) "ERROR"
    }
}

# -------------------------
# VIDEO VERIFY
# -------------------------
function Test-Video($file){

    if(!(Test-Path $file)){
        return $false
    }

    try {

        $result = & ffprobe -v error `
            -show_entries format=duration `
            -of default=noprint_wrappers=1:nokey=1 `
            "$file" 2>&1

        if([string]::IsNullOrWhiteSpace($result)){
            return $false
        }

        [double]$duration = 0

        return [double]::TryParse($result,[ref]$duration)
    }
    catch {

        Log "VERIFY" ("Verification FAILED: {0}" -f $_) "ERROR"

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
# MAIN LOOP
# -------------------------
while($true){

    try {

        Log "REPAIR" "===== LOOP START =====" "TRACE"

        # -------------------------
        # LOAD MAP
        # -------------------------
        $map = Get-RepairMap

        # -------------------------
        # SCAN ARCHIVE
        # -------------------------
        $files = Get-ChildItem $RepairArchive -File -ErrorAction SilentlyContinue

        foreach($file in $files){

            $name = $file.Name

            Log "REPAIR" ("Detected repaired file: {0}" -f $name) "INFO"

            if(-not $map.ContainsKey($name)){

                Log "REPAIR" ("No repair entry found: {0}" -f $name) "WARNING"

                continue
            }

            # -------------------------
            # FILE READY
            # -------------------------
            if(!(Wait-FileReady $file.FullName)){

                Log "REPAIR" ("File unstable: {0}" -f $name) "WARNING"

                continue
            }

            # -------------------------
            # VERIFY
            # -------------------------
            if(!(Test-Video $file.FullName)){

                Log "REPAIR" ("Verification failed: {0}" -f $name) "ERROR"

                continue
            }

            $originalPath = $map[$name].OriginalPath

            $parent = Split-Path $originalPath -Parent

            # -------------------------
            # ENSURE PARENT
            # -------------------------
            if(!(Test-Path $parent)){

                New-Item -ItemType Directory -Path $parent -Force | Out-Null

                Log "REPAIR" ("Created directory: {0}" -f $parent) "INFO"
            }

            # -------------------------
            # OVERWRITE SAFETY
            # -------------------------
            if(Test-Path $originalPath){

                $originalPath = Join-Path $parent (
                    [IO.Path]::GetFileNameWithoutExtension($name) +
                    "_REPAIRED" +
                    [IO.Path]::GetExtension($name)
                )

                Log "REPAIR" ("Original exists - using renamed restore: {0}" -f $originalPath) "WARNING"
            }

            # -------------------------
            # RESTORE
            # -------------------------
            try {

                Move-Item $file.FullName $originalPath -Force

                Log "REPAIR" ("Restored repaired media: {0}" -f $originalPath) "INFO"

                $map.Remove($name)

                Save-RepairMap $map
            }
            catch {

                Log "REPAIR" ("Restore FAILED: {0}" -f $_) "ERROR"
            }
        }
    }
    catch {

        Log "REPAIR" ("UNHANDLED ERROR: {0}" -f $_) "ERROR"
    }

    Log "REPAIR" "Loop sleep (10s)" "TRACE"

    Start-Sleep 10
}