@echo off
setlocal EnableDelayedExpansion

:: Console appearance
title Pulse - Pixellot Unified Live System Evaluator
mode con cols=72 lines=32

:: Disable QuickEdit so accidental clicks don't freeze the window
PowerShell -NoProfile -Command "$k=Add-Type -Name 'CMode' -Namespace 'Win32' -PassThru -MemberDefinition '[DllImport(\"kernel32.dll\")] public static extern IntPtr GetStdHandle(int h); [DllImport(\"kernel32.dll\")] public static extern bool GetConsoleMode(IntPtr h, out uint m); [DllImport(\"kernel32.dll\")] public static extern bool SetConsoleMode(IntPtr h, uint m);'; $h=$k::GetStdHandle(-10); [uint32]$m=0; $k::GetConsoleMode($h,[ref]$m)|Out-Null; $k::SetConsoleMode($h,($m -band (-bnot 0x40)))|Out-Null"

:: Request elevation - Program Files requires admin write access
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo    Requesting administrator access...
    PowerShell -NoProfile -Command "Start-Process '%~f0' -Verb RunAs"
    if !ERRORLEVEL! neq 0 (
        echo.
        echo  ==============================================================
        echo    ERROR: Could not launch as administrator.
        echo.
        echo    Right-click Pulse.bat and choose 'Run as administrator'.
        echo    If a UAC prompt appears, click Yes.
        echo  ==============================================================
        echo.
        pause
    )
    exit /b
)

:: ---- Header ----------------------------------------------------------------
cls
echo.
echo  +==============================================================+
echo  ^|                                                              ^|
echo  ^|         PULSE - PIXELLOT UNIFIED LIVE SYSTEM EVALUATOR       ^|
echo  ^|         Pixellot Unified Live System Evaluator              ^|
echo  ^|                                                              ^|
echo  +==============================================================+
echo.
echo    WARNING: Do NOT close this window while the tool is running.
echo    Closing this window will also close the application.
echo    You may minimise it, but do not close it.
echo  --------------------------------------------------------------
echo.

:: ---- Deploy token (contents:read PAT — allows download from private repo) --
set "VPU_DEPLOY_TOKEN=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"

:: ---- Version and install state --------------------------------------------
set "InstallDir=%ProgramFiles%\Pulse"
set "NeedDownload=1"
set "LocalVersion=not installed"
set "RemoteVersion="

if exist "%InstallDir%\version.txt" (
    set /p LocalVersion=<"%InstallDir%\version.txt"
)

:: Check for an existing installation and compare SHA against GitHub.
:: Note: no | pipe in the PS command - use variable assignment instead to
:: avoid CMD misinterpreting | inside a parenthesised block.
if exist "%InstallDir%\.commit" (
    echo    Checking for updates...
    PowerShell -NoProfile -Command "try { $w = Invoke-WebRequest 'https://api.github.com/repos/ianmoore-playon/vpu-diagnostic-tools/commits/main' -UseBasicParsing -TimeoutSec 10 -Headers @{Authorization='Bearer %VPU_DEPLOY_TOKEN%'}; $s = (ConvertFrom-Json $w.Content).sha; Set-Content '%TEMP%\vpu-sha.txt' $s -NoNewline } catch { Set-Content '%TEMP%\vpu-sha.txt' 'OFFLINE' -NoNewline }"
    set /p RemoteSHA=<"%TEMP%\vpu-sha.txt"
    set /p LocalSHA=<"%InstallDir%\.commit"
    del "%TEMP%\vpu-sha.txt" >nul 2>&1

    if "!RemoteSHA!"=="OFFLINE" (
        echo    Could not reach update server.
        echo    Running installed version  v!LocalVersion!  ^(offline mode^).
        set "NeedDownload=0"
    ) else if "!RemoteSHA!"=="!LocalSHA!" (
        echo    Version  v!LocalVersion!  is up to date.
        set "NeedDownload=0"
    ) else (
        echo    Installed  :  v!LocalVersion!
        echo    Update found. Downloading latest version...
    )
)

:: Force re-download if Run.ps1 is missing regardless of version check
if not exist "%InstallDir%\Run.ps1" set "NeedDownload=1"

:: ---- Download + build (only when needed) -----------------------------------
if "!NeedDownload!"=="1" (
    if "!LocalVersion!"=="not installed" (
        echo    Installing Pulse for the first time...
    )
    echo.
    set "VPU_INST=%InstallDir%"
    PowerShell -NoProfile -Command "$wc=New-Object Net.WebClient; $wc.Headers.Add('Authorization','Bearer %VPU_DEPLOY_TOKEN%'); try { $wc.DownloadFile('https://raw.githubusercontent.com/ianmoore-playon/vpu-diagnostic-tools/main/Download.ps1','%TEMP%\vpu-dl.ps1') } catch { }"
    if exist "%TEMP%\vpu-dl.ps1" (
        PowerShell -NoProfile -ExecutionPolicy Bypass -File "%TEMP%\vpu-dl.ps1"
    ) else (
        echo    Downloading...
        PowerShell -NoProfile -ExecutionPolicy Bypass -Command "$ProgressPreference='SilentlyContinue'; $z='%TEMP%\vpu-diag.zip'; $s='%TEMP%\vpu-diag-stage'; if(Test-Path $s){Remove-Item $s -Recurse -Force}; Invoke-WebRequest 'https://github.com/ianmoore-playon/vpu-diagnostic-tools/archive/refs/heads/main.zip' -OutFile $z; Expand-Archive $z $s -Force; $r=Join-Path $s 'vpu-diagnostic-tools-main'; if(Test-Path '%InstallDir%'){Remove-Item '%InstallDir%' -Recurse -Force}; Move-Item $r '%InstallDir%'; Remove-Item $s -Recurse -Force -EA SilentlyContinue; Remove-Item $z -EA SilentlyContinue"
    )
    set DL_ERR=!ERRORLEVEL!
    del "%TEMP%\vpu-dl.ps1" >nul 2>&1
    if !DL_ERR! neq 0 (
        echo.
        echo  ==============================================================
        echo    ERROR: Download failed. Check your internet connection.
        echo  ==============================================================
        echo.
        pause
        exit /b 1
    )
    PowerShell -NoProfile -Command "foreach ($f in (Get-ChildItem '%InstallDir%' -Recurse)) { try { Unblock-File $f.FullName } catch {} }"

    if exist "%InstallDir%\version.txt" (
        set /p RemoteVersion=<"%InstallDir%\version.txt"
        if "!LocalVersion!"=="not installed" (
            echo    Installed    :  v!RemoteVersion!
        ) else (
            echo    Updated      :  v!LocalVersion!  -^>  v!RemoteVersion!
        )
    )

    echo.
    echo    Building launcher...
    PowerShell -NoProfile -ExecutionPolicy Bypass -File "%InstallDir%\Build.ps1"
    if !ERRORLEVEL! neq 0 (
        echo.
        echo  ==============================================================
        echo    ERROR: Build step failed. See errors above.
        echo  ==============================================================
        echo.
        pause
        exit /b 1
    )
    echo    Done.

    :: ---- Feedback token setup (first install only) -------------------------
    if not exist "C:\ProgramData\Pulse\feedback.key" (
        PowerShell -NoProfile -ExecutionPolicy Bypass -File "%InstallDir%\Set-FeedbackToken.ps1"
    )

    :: Record installed commit SHA for future update checks (no | pipe used)
    PowerShell -NoProfile -Command "try { $w = Invoke-WebRequest 'https://api.github.com/repos/ianmoore-playon/vpu-diagnostic-tools/commits/main' -UseBasicParsing -TimeoutSec 10 -Headers @{Authorization='Bearer %VPU_DEPLOY_TOKEN%'}; $s = (ConvertFrom-Json $w.Content).sha; [System.IO.File]::WriteAllText('%InstallDir%\.commit', $s) } catch { }"
)

:: ---- Launcher log ----------------------------------------------------------
set "LogDir=%InstallDir%\logs"
if not exist "%LogDir%" mkdir "%LogDir%" 2>nul
set "LogFile=%LogDir%\launcher.log"

set "_LaunchVer=!LocalVersion!"
if not "!RemoteVersion!"=="" set "_LaunchVer=!RemoteVersion!"
>> "%LogFile%" echo [%DATE% %TIME%] Pulse v!_LaunchVer! launcher started

:: ---- Launch ----------------------------------------------------------------
echo.
echo  ==============================================================
if "!RemoteVersion!"=="" (
    echo    Launching  Pulse  v!LocalVersion!
) else (
    echo    Launching  Pulse  v!RemoteVersion!
)
echo.
echo    This window will remain open while the application runs.
echo    Do NOT close it  --  minimise it instead.
echo  ==============================================================
echo.
if not exist "%InstallDir%\Run.ps1" (
    >> "%LogFile%" echo [%DATE% %TIME%] ERROR: Run.ps1 not found - installation may be corrupt
    echo.
    echo  ==============================================================
    echo    ERROR: Run.ps1 not found at %InstallDir%
    echo    Delete the folder %InstallDir% and re-run this launcher.
    echo  ==============================================================
    echo.
    pause
    exit /b 1
)
>> "%LogFile%" echo [%DATE% %TIME%] Launching Run.ps1
PowerShell -NoProfile -ExecutionPolicy Bypass -File "%InstallDir%\Run.ps1"
set _ExitCode=!ERRORLEVEL!
if !_ExitCode! neq 0 (
    >> "%LogFile%" echo [%DATE% %TIME%] ERROR: Application exited with code !_ExitCode!
    echo.
    echo  ==============================================================
    echo    The application exited with an error ^(code: !_ExitCode!^).
    echo    If this keeps happening, delete %InstallDir% and re-run.
    echo  ==============================================================
    echo.
    pause
) else (
    >> "%LogFile%" echo [%DATE% %TIME%] Application closed normally
)
