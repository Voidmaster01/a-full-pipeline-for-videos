# =========================================================

# PIPELINE MANAGER

# =========================================================

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# =========================================================

# STARTUP

# =========================================================

$Script:ManagerRoot = $PSScriptRoot
$Script:ConfigPath = Join-Path $Script:ManagerRoot "config.json"

$Script:Processes = @{}

if(!(Test-Path $Script:ConfigPath)){


[System.Windows.Forms.MessageBox]::Show(
    "config.json missing.",
    "Startup Error"
)

exit


}

try {


$Script:Config = Get-Content $Script:ConfigPath -Raw |
ConvertFrom-Json

$Script:Root = $Script:Config.Base


}
catch {


[System.Windows.Forms.MessageBox]::Show(
    "Failed loading config.json",
    "Startup Error"
)

exit


}

# =========================================================

# HELPERS

# =========================================================

function Get-PipelinePath {


param(
    [string]$FolderKey
)

return Join-Path `
    $Script:Root `
    $Script:Config.Paths.$FolderKey


}

function Add-ColoredLine {


param(
    [System.Windows.Forms.RichTextBox]$Box,
    [string]$Line
)

$Color = [System.Drawing.Color]::White

if($Line -match "ERROR|FAILED|EXCEPTION"){

    $Color = [System.Drawing.Color]::Red
}
elseif($Line -match "WARNING"){

    $Color = [System.Drawing.Color]::Orange
}
elseif($Line -match "UPLOAD"){

    $Color = [System.Drawing.Color]::DeepSkyBlue
}
elseif($Line -match "SCAN"){

    $Color = [System.Drawing.Color]::LimeGreen
}
elseif($Line -match "FFMPEG"){

    $Color = [System.Drawing.Color]::MediumPurple
}
elseif($Line -match "SUCCESS|COMPLETE"){

    $Color = [System.Drawing.Color]::SpringGreen
}

$Box.SelectionStart = $Box.TextLength
$Box.SelectionLength = 0
$Box.SelectionColor = $Color

$Box.AppendText($Line + "`r`n")

$Box.SelectionColor = $Box.ForeColor


}

function Write-ManagerLog {


param(
    [string]$Message
)

$Time = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

Add-ColoredLine `
    $PipelineLogBox `
    "[$Time] $Message"


}

function Start-PipelineScript {


param(
    [string]$Name,
    [string]$Path
)

if(!(Test-Path $Path)){

    Write-ManagerLog "ERROR Missing script: $Path"
    return
}

if($Script:Processes.ContainsKey($Name)){

    $Existing = $Script:Processes[$Name]

    if(!$Existing.HasExited){

        Write-ManagerLog "WARNING $Name already running."
        return
    }
}

try {

    $StartInfo = New-Object System.Diagnostics.ProcessStartInfo

    $StartInfo.FileName = "powershell.exe"

    $StartInfo.Arguments = @(
        "-ExecutionPolicy Bypass",
        "-WindowStyle Hidden",
        "-File `"$Path`""
    ) -join " "

    $StartInfo.CreateNoWindow = $true
    $StartInfo.UseShellExecute = $false

    $Process = [System.Diagnostics.Process]::Start($StartInfo)

    $Script:Processes[$Name] = $Process

    Write-ManagerLog "SUCCESS Started $Name"
}
catch {

    Write-ManagerLog "ERROR Failed starting $Name"
}


}

function Stop-PipelineProcess {


param(
    [string]$Name
)

if($Script:Processes.ContainsKey($Name)){

    try {

        $Process = $Script:Processes[$Name]

        if(!$Process.HasExited){

            taskkill `
                /PID $Process.Id `
                /T `
                /F | Out-Null

            Write-ManagerLog "Stopped $Name"
        }
    }
    catch {

        Write-ManagerLog "ERROR Failed stopping $Name"
    }
}


}


function Test-Tool {


param(
    [string]$Tool
)

return [bool](Get-Command $Tool -ErrorAction SilentlyContinue)


}

function Start-BatchProcess {


param(
    [string]$Name,
    [string]$BatchPath
)

if(!(Test-Path $BatchPath)){

    Write-ManagerLog "ERROR Missing batch file: $BatchPath"
    return
}

try {

    $WorkingDir = Split-Path $BatchPath

    $StartInfo = New-Object System.Diagnostics.ProcessStartInfo

    $StartInfo.FileName = "cmd.exe"

    $StartInfo.Arguments = "/k cd /d `"$WorkingDir`" && `"$BatchPath`""

    $StartInfo.WorkingDirectory = $WorkingDir

    $StartInfo.UseShellExecute = $false
    $StartInfo.CreateNoWindow = $false
    $StartInfo.WindowStyle = "Hidden"

    $Process = [System.Diagnostics.Process]::Start($StartInfo)

    $Script:Processes[$Name] = $Process

    Write-ManagerLog "SUCCESS Started $Name"
}
catch {

    Write-ManagerLog "ERROR Failed starting $Name : $_"
}


}





# =========================================================

# MAIN WINDOW

# =========================================================

$Form = New-Object System.Windows.Forms.Form
$Form.Text = "PIPELINE MANAGER"
$Form.Size = New-Object System.Drawing.Size(1600,950)
$Form.StartPosition = "CenterScreen"
$Form.BackColor = "#1E1E1E"
$Form.ForeColor = "White"

# =========================================================

# MAIN TABS

# =========================================================

$Tabs = New-Object System.Windows.Forms.TabControl
$Tabs.Dock = "Fill"

$DashboardTab = New-Object System.Windows.Forms.TabPage
$DashboardTab.Text = "Dashboard"
$DashboardTab.BackColor = "#1E1E1E"

$LogsTab = New-Object System.Windows.Forms.TabPage
$LogsTab.Text = "Logs"
$LogsTab.BackColor = "#1E1E1E"

$ProcessesTab = New-Object System.Windows.Forms.TabPage
$ProcessesTab.Text = "Processes"
$ProcessesTab.BackColor = "#1E1E1E"

$ToolsTab = New-Object System.Windows.Forms.TabPage
$ToolsTab.Text = "Tools"
$ToolsTab.BackColor = "#1E1E1E"


$Tabs.TabPages.Add($DashboardTab)
$Tabs.TabPages.Add($LogsTab)
$Tabs.TabPages.Add($ProcessesTab)
$Tabs.TabPages.Add($ToolsTab)


$Form.Controls.Add($Tabs)

# =========================================================

# DASHBOARD BUTTONS

# =========================================================

$StartButton = New-Object System.Windows.Forms.Button
$StartButton.Text = "START PIPELINE"
$StartButton.Size = New-Object System.Drawing.Size(250,60)
$StartButton.Location = New-Object System.Drawing.Point(20,20)

$StartButton.Add_Click({


$BatchFolder = Get-PipelinePath "Batch"

Start-BatchProcess `
    "Pipeline" `
    (Join-Path $BatchFolder "Video_Pipeline.bat")


})


$DashboardTab.Controls.Add($StartButton)

# =========================================================

# START UPLOADER

# =========================================================

$UploaderButton = New-Object System.Windows.Forms.Button
$UploaderButton.Text = "START UPLOADER"
$UploaderButton.Size = New-Object System.Drawing.Size(250,60)
$UploaderButton.Location = New-Object System.Drawing.Point(20,100)

$UploaderButton.Add_Click({


$BatchFolder = Get-PipelinePath "Batch"

Start-BatchProcess `
    "Uploader" `
    (Join-Path `
        $BatchFolder `
        "Uploader Starter.bat"
    )


})

$DashboardTab.Controls.Add($UploaderButton)


# =========================================================

# STOP BUTTON

# =========================================================

$StopButton = New-Object System.Windows.Forms.Button
$StopButton.Text = "STOP PIPELINE"
$StopButton.Size = New-Object System.Drawing.Size(250,60)
$StopButton.Location = New-Object System.Drawing.Point(290,20)

$StopButton.Add_Click({


foreach($Name in $Script:Processes.Keys){

    Stop-PipelineProcess $Name
}


})

$DashboardTab.Controls.Add($StopButton)

# =========================================================

# START MUXER

# =========================================================

$MuxerButton = New-Object System.Windows.Forms.Button
$MuxerButton.Text = "START MUXER"
$MuxerButton.Size = New-Object System.Drawing.Size(250,60)
$MuxerButton.Location = New-Object System.Drawing.Point(290,100)

$MuxerButton.Add_Click({


$BatchFolder = Get-PipelinePath "Batch"

$MuxerPath = Join-Path `
    $BatchFolder `
    "Auto-Muxer.bat"

if(!(Test-Path $MuxerPath)){

    Write-ManagerLog "ERROR Missing Auto-Muxer.bat"
    return
}

try {

    $StartInfo = New-Object System.Diagnostics.ProcessStartInfo

    $StartInfo.FileName = "cmd.exe"

    $StartInfo.Arguments = '/c start "MUXER" /min "' + $MuxerPath + '"'

    $StartInfo.WorkingDirectory = $BatchFolder

    $StartInfo.UseShellExecute = $true

    $Process = [System.Diagnostics.Process]::Start($StartInfo)

    Write-ManagerLog "SUCCESS Started muxer minimized."
}
catch {

    Write-ManagerLog "ERROR Failed starting muxer: $_"
}


})


$DashboardTab.Controls.Add($MuxerButton)



# =========================================================

# FORCE SCAN

# =========================================================

$ForceButton = New-Object System.Windows.Forms.Button
$ForceButton.Text = "FORCE SCAN"
$ForceButton.Size = New-Object System.Drawing.Size(250,60)
$ForceButton.Location = New-Object System.Drawing.Point(560,20)

$ForceButton.Add_Click({


$Batch = Join-Path `
    (Get-PipelinePath "Batch") `
    "Force Scan.bat"

if(Test-Path $Batch){

    Start-Process $Batch -WindowStyle Hidden

    Write-ManagerLog "SCAN Force scan triggered."
}


})

$DashboardTab.Controls.Add($ForceButton)

# =========================================================
# PAUSE/RESUME
# =========================================================

$PauseButton = New-Object System.Windows.Forms.Button
$PauseButton.Text = "PAUSE PIPELINE"
$PauseButton.Size = New-Object System.Drawing.Size(250,60)
$PauseButton.Location = New-Object System.Drawing.Point(830,20)

$PauseButton.Add_Click({

$PauseBatch = Join-Path `
    (Get-PipelinePath "Batch") `
    "Pause.bat"

if(Test-Path $PauseBatch){

    Start-Process `
        $PauseBatch `
        -WindowStyle Hidden

    Write-ManagerLog "WARNING Pause toggled."
}
else {

    Write-ManagerLog "ERROR Pause.bat missing."
}


})

$DashboardTab.Controls.Add($PauseButton)

$PauseStatus = New-Object System.Windows.Forms.Label
$PauseStatus.Text = "Pipeline Active"
$PauseStatus.ForeColor = "Lime"
$PauseStatus.Font = New-Object System.Drawing.Font(
"Segoe UI",
14,
[System.Drawing.FontStyle]::Bold
)
$PauseStatus.Location = New-Object System.Drawing.Point(1100,30)
$PauseStatus.AutoSize = $true

$DashboardTab.Controls.Add($PauseStatus)



# =========================================================

# LOG TABS

# =========================================================

$LogTabs = New-Object System.Windows.Forms.TabControl
$LogTabs.Dock = "Fill"

$PipelineTab = New-Object System.Windows.Forms.TabPage
$PipelineTab.Text = "Pipeline"

$DebugTab = New-Object System.Windows.Forms.TabPage
$DebugTab.Text = "Debug"

$FFmpegTab = New-Object System.Windows.Forms.TabPage
$FFmpegTab.Text = "FFmpeg"

$MuxerTab = New-Object System.Windows.Forms.TabPage
$MuxerTab.Text = "Muxer"

$ScannerTab = New-Object System.Windows.Forms.TabPage
$ScannerTab.Text = "Scanner"

$UploaderTab = New-Object System.Windows.Forms.TabPage
$UploaderTab.Text = "Uploader"

$RepairTab = New-Object System.Windows.Forms.TabPage
$RepairTab.Text = "Repair"

$IdleTab = New-Object System.Windows.Forms.TabPage
$IdleTab.Text = "Idle"

$CleanerTab = New-Object System.Windows.Forms.TabPage
$CleanerTab.Text = "Cleaner"




$LogTabs.TabPages.Add($PipelineTab)
$LogTabs.TabPages.Add($DebugTab)
$LogTabs.TabPages.Add($FFmpegTab)
$LogTabs.TabPages.Add($MuxerTab)
$LogTabs.TabPages.Add($ScannerTab)
$LogTabs.TabPages.Add($UploaderTab)
$LogTabs.TabPages.Add($RepairTab)
$LogTabs.TabPages.Add($IdleTab)
$LogTabs.TabPages.Add($CleanerTab)

$LogsTab.Controls.Add($LogTabs)

function New-LogBox {


$Box = New-Object System.Windows.Forms.RichTextBox

$Box.Dock = "Fill"
$Box.BackColor = "#111111"
$Box.ForeColor = "White"
$Box.Font = New-Object System.Drawing.Font(
    "Consolas",
    10
)

$Box.ReadOnly = $true

return $Box


}

$PipelineLogBox = New-LogBox
$DebugLogBox = New-LogBox
$FFmpegLogBox = New-LogBox
$ScannerLogBox = New-LogBox
$UploaderLogBox = New-LogBox
$RepairLogBox = New-LogBox
$IdleLogBox = New-LogBox
$CleanerLogBox = New-LogBox
$MuxerLogBox = New-LogBox


$MuxerTab.Controls.Add($MuxerLogBox)
$PipelineTab.Controls.Add($PipelineLogBox)
$DebugTab.Controls.Add($DebugLogBox)
$FFmpegTab.Controls.Add($FFmpegLogBox)
$ScannerTab.Controls.Add($ScannerLogBox)
$UploaderTab.Controls.Add($UploaderLogBox)
$RepairTab.Controls.Add($RepairLogBox)
$IdleTab.Controls.Add($IdleLogBox)
$CleanerTab.Controls.Add($CleanerLogBox)
# =========================================================

# PROCESS LIST

# =========================================================

$ProcessList = New-Object System.Windows.Forms.ListView

$ProcessList.Dock = "Fill"
$ProcessList.View = "Details"
$ProcessList.BackColor = "#1A1A1A"
$ProcessList.ForeColor = "White"

$ProcessList.Columns.Add("Process",300)
$ProcessList.Columns.Add("PID",120)
$ProcessList.Columns.Add("Status",200)

$ProcessesTab.Controls.Add($ProcessList)

# =========================================================

# TOOLS

# =========================================================

$VerifyButton = New-Object System.Windows.Forms.Button
$VerifyButton.Text = "VERIFY TOOLS"
$VerifyButton.Size = New-Object System.Drawing.Size(300,60)
$VerifyButton.Location = New-Object System.Drawing.Point(20,20)

$VerifyButton.Add_Click({


foreach($Tool in @(
    "ffmpeg",
    "ffprobe",
    "rclone"
)){

    if(Test-Tool $Tool){

        Write-ManagerLog "SUCCESS [OK] $Tool"
    }
    else {

        Write-ManagerLog "ERROR [MISSING] $Tool"
    }
}


})

$ToolsTab.Controls.Add($VerifyButton)

# =========================================================

# PROCESS TIMER

# =========================================================

$ProcessTimer = New-Object System.Windows.Forms.Timer
$ProcessTimer.Interval = 3000

$ProcessTimer.Add_Tick({


$ProcessList.Items.Clear()

foreach($Key in $Script:Processes.Keys){

    $Proc = $Script:Processes[$Key]

    $Status = "Exited"

    if(!$Proc.HasExited){

        $Status = "Running"
    }

    $Item = New-Object System.Windows.Forms.ListViewItem($Key)

    $null = $Item.SubItems.Add($Proc.Id)
    $null = $Item.SubItems.Add($Status)

    $ProcessList.Items.Add($Item)
}


})

$ProcessTimer.Start()

# =========================================================

# PAUSE STATUS TIMER

# =========================================================

$PauseTimer = New-Object System.Windows.Forms.Timer
$PauseTimer.Interval = 2000

$PauseTimer.Add_Tick({


try {

    # HARD PATH TO PAUSE FLAG
    $PauseFlag = Join-Path `
        (Join-Path $Script:Root "TEMP AND TEXT FILES") `
        "pause.flag"

    if(Test-Path $PauseFlag){

        $PauseStatus.Text = "Pipeline Paused"
        $PauseStatus.ForeColor = "Red"
    }
    else {

        $PauseStatus.Text = "Pipeline Active"
        $PauseStatus.ForeColor = "Lime"
    }
}
catch {

    $PauseStatus.Text = "Pause Check Failed"
    $PauseStatus.ForeColor = "Orange"
}


})

$PauseTimer.Start()



# =========================================================

# LIVE LOG READER

# =========================================================

function Update-LogBox {


param(
    [string]$Path,
    [System.Windows.Forms.RichTextBox]$Box
)

if(Test-Path $Path){

    $Box.Clear()

    $Lines = Get-Content $Path -Tail 50

    foreach($Line in $Lines){

        Add-ColoredLine $Box $Line
    }
}


}

$LogTimer = New-Object System.Windows.Forms.Timer
$LogTimer.Interval = 4000

$LogTimer.Add_Tick({


Update-LogBox `
    (Join-Path `
        (Get-PipelinePath "Logs") `
        $Script:Config.Files.PipelineLog
    ) `
    $PipelineLogBox

Update-LogBox `
    (Join-Path `
        (Get-PipelinePath "Logs") `
        $Script:Config.Files.DebugLog
    ) `
    $DebugLogBox

Update-LogBox `
    (Join-Path `
        (Get-PipelinePath "Logs") `
        $Script:Config.Files.FFmpegLog
    ) `
    $FFmpegLogBox
    
    Update-LogBox `
    (Join-Path `
    (Get-PipelinePath "Logs")`
     "scanner.log"
     ) `
    $ScannerLogBox

    Update-LogBox `
     (Join-Path `
    (Get-PipelinePath "Logs")`
     "uploader.log" 
     ) `
    $UploaderLogBox

    Update-LogBox `
    (Join-Path `
    (Get-PipelinePath "Logs")`
     "repair.log" 
     ) `
    $RepairLogBox

    Update-LogBox `
    (Join-Path `
    (Get-PipelinePath "Logs") `
     "idle.log" 
     ) `
    $IdleLogBox

    Update-LogBox `
    (Join-Path `
    (Get-PipelinePath "Logs") `
     "cleaner.log"
      ) `
    $CleanerLogBox

    Update-LogBox `
    (Join-Path `
    (Get-PipelinePath "Logs") `
     "muxer.log"
      ) `
    $MuxerLogBox


})

$LogTimer.Start()

# =========================================================

# CLEAN EXIT

# =========================================================

$Form.Add_FormClosing({


foreach($Name in $Script:Processes.Keys){


try {

    $Proc = $Script:Processes[$Name]

    if(!$Proc.HasExited){

        taskkill /PID $Proc.Id /T /F | Out-Null
    }
}
catch {

}


}
}
)


Write-ManagerLog "Pipeline Manager initialized."

# =========================================================

# SHOW WINDOW

# =========================================================

[void]$Form.ShowDialog()
