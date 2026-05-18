# a-full-pipeline-for-videos

A fully automated video processing pipeline for converting, compressing, repairing, archiving, and optionally uploading video files to cloud storage.

Supports `.mkv` and `.mp4` inputs and outputs optimized `.mp4` archive-ready files.

---

# Features

* Automated video muxing and compression
* Corruption detection and repair handling
* Optional semi-automatic cloud uploads using Rclone
* Idle-based automatic shutdown system
* Automatic cleanup of old processed files
* Integrated logging and process management
* Configurable scanning and maintenance tools

---

# Setup

Run `SetupLauncher.bat` and follow the prompts to configure the pipeline.

During setup you may optionally configure `Rclone` for semi-automatic cloud uploads. If you do not plan to upload files, this step can be skipped.

You will also be prompted to configure the idle shutdown system. This feature can be disabled at any time by running:

```text
<Root Folder>\BATCH FILES\IdleFlag.bat
```

Additional configuration options are available through the terminal interface and the `config.json` file.

---

# Usage

Launch the pipeline using:

```text
Main Launcher.bat
```

To start the pipeline automatically when Windows starts:

1. Open the Startup folder:

```text
%AppData%\Roaming\Microsoft\Windows\Start Menu\Programs\Startup
```

2. Create a shortcut to:

```text
Main Launcher.bat
```

---

# Interface Overview

The manager contains several tabs for controlling and monitoring the pipeline.

---

# Dashboard

The Dashboard contains the primary pipeline controls.

## Start Pipeline

Starts all core services, including:

* `MediaScanner.ps1`
* `RepairRestore.ps1`
* `IdleShutdown.ps1`
* `FileCleaner.ps1`

---

## MediaScanner.ps1

Scans archived video files for corrupted or missing `moov` atoms, which can make video files unplayable.

If corruption is detected, affected files are moved to the repair folder for processing.

Features include:

* Compatibility with previously archived files
* Cached verification of known-good files
* Configurable scan intervals

---

## RepairRestore.ps1

Tracks files moved into the repair directory and stores their original archive locations.

Once repairs are completed, files are automatically restored to their original locations.

---

## IdleShutdown.ps1

Monitors overall system and user activity to determine when the computer can safely shut down after pipeline tasks are complete.

Monitored conditions include:

* CPU usage
* Keyboard and mouse activity
* Pipeline activity state
* Runtime cycle count

This is useful for unattended overnight processing or large export jobs.

---

## FileCleaner.ps1

Monitors the `Processed` and `Backup` directories for old video files and removes them after a configurable retention period (default: approximately 30–60 days).

This helps prevent processed source files, especially large `.mkv` files, from consuming excessive storage space.

Retention settings can be adjusted by modifying the `AddDays` value in the script configuration.

---

## Stop Pipeline

Stops all active pipeline-related processes and services.

---

## Force Scan

Immediately starts a media integrity scan, bypassing the normal scheduled interval.

By default, scans occur once per week, though this can be modified during setup or through `config.json`.

---

## Pause Pipeline

Temporarily pauses the following services:

* Muxer
* Uploader
* Media Scanner

---

## Start Uploader

Launches the Rclone-based uploader service for semi-automatic cloud uploads.

Files placed in the configured upload directory can be transferred automatically to supported cloud providers.

---

## Start Muxer

Launches the primary video muxing and processing service.

Due to current implementation limitations, the muxer is started independently from the main pipeline process.

To process a file:

1. Rename or prepare the video file as desired
2. Place the file into the monitored input location
3. Wait for processing to complete
4. Processed files will appear in:

```text
<Root Folder>\Archive
```

---

# Logs

The Logs tab provides access to all pipeline logs, including both active and archived sessions.

Available logs include:

* Pipeline
* Debug
* FFmpeg
* Muxer
* Scanner
* Uploader
* Repair
* Idle
* Cleaner

---

# Processes

Displays currently running pipeline processes.

This section is still under development and may not always accurately reflect process states.

---

# Tools

Provides utility tools for validating or checking installations of:

* FFmpeg
* FFprobe
* Rclone

Diagnostic output is written to:

```text
Pipeline.log
```

or can be viewed directly in the `Pipeline` log tab.

---

# License

## MIT License

Copyright © 2026 Voidmaster01

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the “Software”), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED “AS IS”, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

---

# Support

If you encounter issues, please open a bug report with relevant logs and details about the problem. Assistance will be provided when possible.
