@echo off
setlocal EnableDelayedExpansion

:: Console appearance
title VPU Diagnostic Tool Suite
mode con cols=72 lines=32

:: Disable QuickEdit so accidental clicks don't freeze the window
PowerShell -NoProfile -Command "$k=Add-Type -Name 'CMode' -Namespace 'Win32' -PassThru -MemberDefinition '[DllImport(\"kernel32.dll\")] public static extern IntPtr GetStdHandle(int h); [DllImport(\"kernel32.dll\")] public static extern bool GetConsoleMode(IntPtr h, out uint m); [DllImport(\"kernel32.dll\")] public static extern bool SetConsoleMode(IntPtr h, uint m);'; $h=$k::GetStdHandle(-10); [uint32]$m=0; $k::GetConsoleMode($h,[ref]$m)|Out-Null; $k::SetConsoleMode($h,($m -band (-bnot 0x40)))|Out-Null"

:: Request elevation - Program Files requires admin write access
net session >nul 2>&1
if %errorLevel% neq 0 (
    PowerShell -NoProfile -Command "Start-Process '%~f0' -Verb RunAs"
    exit /b
)

:: ---- Header ----------------------------------------------------------------
cls
echo.
echo  +==============================================================+
echo  ^|                                                              ^|
echo  ^|         VPU DIAGNOSTIC TOOL SUITE                           ^|
echo  ^|         Pixellot VPU Field Diagnostic Utility               ^|
echo  ^|                                                              ^|
echo  +==============================================================+
echo.
echo    WARNING: Do NOT close this window while the tool is running.
echo    Closing this window will also close the application.
echo    You may minimise it, but do not close it.
echo  --------------------------------------------------------------
echo.

:: ---- Version and install state --------------------------------------------
set "InstallDir=%ProgramFiles%\VPU-DiagTool"
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
    PowerShell -NoProfile -Command "try { $w = Invoke-WebRequest 'https://api.github.com/repos/ianmoore-playon/vpu-diagnostic-tools/commits/main' -UseBasicParsing -TimeoutSec 10; $s = (ConvertFrom-Json $w.Content).sha; Set-Content '%TEMP%\vpu-sha.txt' $s -NoNewline } catch { Set-Content '%TEMP%\vpu-sha.txt' 'OFFLINE' -NoNewline }"
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
        echo    Installing VPU Diagnostic Tool Suite for the first time...
    )
    echo.
    echo    Downloading...
    PowerShell -NoProfile -ExecutionPolicy Bypass -Command "$zip = '%TEMP%\vpu-diag.zip'; $stage = '%TEMP%\vpu-diag-stage'; if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }; Invoke-WebRequest 'https://github.com/ianmoore-playon/vpu-diagnostic-tools/archive/refs/heads/main.zip' -OutFile $zip; Expand-Archive $zip $stage -Force; $src = Join-Path $stage 'vpu-diagnostic-tools-main'; if (Test-Path '%InstallDir%') { Remove-Item '%InstallDir%' -Recurse -Force }; Move-Item $src '%InstallDir%'; Remove-Item $stage -Recurse -Force -ErrorAction SilentlyContinue; Remove-Item $zip -ErrorAction SilentlyContinue"
    if !ERRORLEVEL! neq 0 (
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

    :: Record installed commit SHA for future update checks (no | pipe used)
    PowerShell -NoProfile -Command "try { $w = Invoke-WebRequest 'https://api.github.com/repos/ianmoore-playon/vpu-diagnostic-tools/commits/main' -UseBasicParsing -TimeoutSec 10; $s = (ConvertFrom-Json $w.Content).sha; [System.IO.File]::WriteAllText('%InstallDir%\.commit', $s) } catch { }"
)

:: ---- Launch ----------------------------------------------------------------
echo.
echo  ==============================================================
if "!RemoteVersion!"=="" (
    echo    Launching  VPU Diagnostic Tool Suite  v!LocalVersion!
) else (
    echo    Launching  VPU Diagnostic Tool Suite  v!RemoteVersion!
)
echo.
echo    This window will remain open while the application runs.
echo    Do NOT close it  --  minimise it instead.
echo  ==============================================================
echo.
PowerShell -NoProfile -ExecutionPolicy Bypass -File "%InstallDir%\Run.ps1"
