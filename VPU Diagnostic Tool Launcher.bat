@echo off
setlocal EnableDelayedExpansion

:: Disable QuickEdit so accidental console clicks don't freeze the window
PowerShell -NoProfile -Command "$k=Add-Type -Name 'CMode' -Namespace 'Win32' -PassThru -MemberDefinition '[DllImport(\"kernel32.dll\")] public static extern IntPtr GetStdHandle(int h); [DllImport(\"kernel32.dll\")] public static extern bool GetConsoleMode(IntPtr h, out uint m); [DllImport(\"kernel32.dll\")] public static extern bool SetConsoleMode(IntPtr h, uint m);'; $h=$k::GetStdHandle(-10); [uint32]$m=0; $k::GetConsoleMode($h,[ref]$m)|Out-Null; $k::SetConsoleMode($h,($m -band (-bnot 0x40)))|Out-Null"

:: Request elevation - Program Files requires admin write access
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo Requesting administrator privileges...
    PowerShell -NoProfile -Command "Start-Process '%~f0' -Verb RunAs"
    exit /b
)

set "InstallDir=%ProgramFiles%\VPU-DiagTool"
set "NeedDownload=1"

:: Check for an existing installation and compare with the latest GitHub commit
if exist "%InstallDir%\.commit" (
    echo Checking for updates...
    PowerShell -NoProfile -Command "try { $s = (Invoke-WebRequest 'https://api.github.com/repos/ianmoore-playon/vpu-diagnostic-tools/commits/main' -UseBasicParsing -TimeoutSec 10 | ConvertFrom-Json).sha; $s | Set-Content '%TEMP%\vpu-sha.txt' -NoNewline } catch { Set-Content '%TEMP%\vpu-sha.txt' 'OFFLINE' -NoNewline }"
    set /p RemoteSHA=<"%TEMP%\vpu-sha.txt"
    set /p LocalSHA=<"%InstallDir%\.commit"
    del "%TEMP%\vpu-sha.txt" >nul 2>&1
    if "!RemoteSHA!"=="OFFLINE" (
        echo Update check failed - running installed version.
        set "NeedDownload=0"
    ) else if "!RemoteSHA!"=="!LocalSHA!" (
        echo VPU Diagnostic Tool is up to date.
        set "NeedDownload=0"
    ) else (
        echo Update available. Downloading latest version...
    )
)

:: Force a fresh download if Run.ps1 is missing regardless of version check
if not exist "%InstallDir%\Run.ps1" set "NeedDownload=1"

if "!NeedDownload!"=="1" (
    echo Downloading VPU Diagnostic Tool Suite...
    PowerShell -NoProfile -ExecutionPolicy Bypass -Command "$zip = '%TEMP%\vpu-diag.zip'; $stage = '%TEMP%\vpu-diag-stage'; if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }; Invoke-WebRequest 'https://github.com/ianmoore-playon/vpu-diagnostic-tools/archive/refs/heads/main.zip' -OutFile $zip; Expand-Archive $zip $stage -Force; $src = Join-Path $stage 'vpu-diagnostic-tools-main'; if (Test-Path '%InstallDir%') { Remove-Item '%InstallDir%' -Recurse -Force }; Move-Item $src '%InstallDir%'; Remove-Item $stage -Recurse -Force -ErrorAction SilentlyContinue; Remove-Item $zip -ErrorAction SilentlyContinue; Get-ChildItem '%InstallDir%' -Recurse | Unblock-File"
    if !ERRORLEVEL! neq 0 (
        echo Download failed. Check your internet connection and try again.
        pause
        exit /b 1
    )
    echo Building launcher...
    PowerShell -NoProfile -ExecutionPolicy Bypass -File "%InstallDir%\Build.ps1"
    if !ERRORLEVEL! neq 0 (
        echo Build step failed. See errors above.
        pause
        exit /b 1
    )
    :: Record the installed commit SHA for future update checks
    PowerShell -NoProfile -Command "try { $s = (Invoke-WebRequest 'https://api.github.com/repos/ianmoore-playon/vpu-diagnostic-tools/commits/main' -UseBasicParsing -TimeoutSec 10 | ConvertFrom-Json).sha; [System.IO.File]::WriteAllText('%InstallDir%\.commit', $s) } catch { }"
)

echo Launching...
PowerShell -NoProfile -ExecutionPolicy Bypass -File "%InstallDir%\Run.ps1"
