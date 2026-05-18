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

Log "CLEANER" "Cleanup service started" "INFO"


# -------------------------
# SAFE DELETE
# -------------------------
function Remove-Safely($path){

    if(!(Test-Path $path)){
        return
    }

    try {

        Log "CLEANER" ("Deleting: {0}" -f $path) "INFO"

        Remove-Item $path -Force

        Log "CLEANER" ("Delete successful: {0}" -f $path) "DEBUG"
    }
    catch {

        Log "CLEANER" ("Delete FAILED: {0} | {1}" -f $path,$_ ) "ERROR"
    }
}

# -------------------------
# MAIN LOOP
# -------------------------
while($true){

    try {

        Log "CLEANER" "----- CLEANER LOOP -----" "TRACE"

        # -------------------------
        # TEMP ORIGINAL CLEANUP
        # -------------------------
        if(Test-Path $TempOriginal){

            $files = Get-ChildItem $TempOriginal -File -ErrorAction SilentlyContinue

            foreach($file in $files){

                # older than 12 hours
                if($file.LastWriteTime -lt (Get-Date).AddHours(-12)){

                    Log "CLEANER" ("Stale temp original: {0}" -f $file.FullName) "INFO"

                    Remove-Safely $file.FullName
                }
            }
        }

        # -------------------------
        # TEMP PROXY CLEANUP
        # -------------------------
        if(Test-Path $TempProxy){

            $files = Get-ChildItem $TempProxy -File -ErrorAction SilentlyContinue

            foreach($file in $files){

                # older than 12 hours
                if($file.LastWriteTime -lt (Get-Date).AddHours(-12)){

                    Log "CLEANER" ("Stale temp proxy: {0}" -f $file.FullName) "INFO"

                    Remove-Safely $file.FullName
                }
            }
        }

        # -------------------------
        # PROCESSED CLEANUP
        # -------------------------
        if(Test-Path $Processed){

            $files = Get-ChildItem $Processed -File -ErrorAction SilentlyContinue

            foreach($file in $files){

                # older than 30 days
                if($file.LastWriteTime -lt (Get-Date).AddDays(-30)){

                    Log "CLEANER" ("Old processed file: {0}" -f $file.FullName) "INFO"

                    Remove-Safely $file.FullName
                }
            }
        }

        # -------------------------
        # REPAIR QUEUE CLEANUP
        # -------------------------
        if(Test-Path $RepairQueue){

            $files = Get-ChildItem $RepairQueue -File -ErrorAction SilentlyContinue

            foreach($file in $files){

                # older than 60 days
                if($file.LastWriteTime -lt (Get-Date).AddDays(-60)){

                    Log "CLEANER" ("Old repair file: {0}" -f $file.FullName) "WARNING"

                    Remove-Safely $file.FullName
                }
            }
        }

        Log "CLEANER" "Cleanup cycle complete" "TRACE"
    }
    catch {

        Log "CLEANER" ("UNHANDLED ERROR: {0}" -f $_) "ERROR"
    }

    # 30 minutes
    Start-Sleep 1800
}