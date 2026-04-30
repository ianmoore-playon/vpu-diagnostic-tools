@echo off
echo Downloading VPU Diagnostic Tool Suite...
PowerShell -NoProfile -ExecutionPolicy Bypass -Command "if(Test-Path '%TEMP%\VPU-DiagTool'){Remove-Item '%TEMP%\VPU-DiagTool' -Recurse -Force}; Invoke-WebRequest 'https://github.com/ianmoore-playon/vpu-diagnostic-tools/archive/refs/heads/main.zip' -OutFile '%TEMP%\vpu-diag.zip'; Expand-Archive '%TEMP%\vpu-diag.zip' '%TEMP%' -Force; Move-Item '%TEMP%\vpu-diagnostic-tools-main' '%TEMP%\VPU-DiagTool' -Force; Remove-Item '%TEMP%\vpu-diag.zip'; Get-ChildItem '%TEMP%\VPU-DiagTool' -Recurse | Unblock-File"
if %ERRORLEVEL% neq 0 (
    echo Download failed. Check your internet connection and try again.
    pause
    exit /b 1
)
echo Building launcher...
PowerShell -NoProfile -ExecutionPolicy Bypass -File "%TEMP%\VPU-DiagTool\Build.ps1"
if %ERRORLEVEL% neq 0 (
    echo Build step failed. See errors above.
    pause
    exit /b 1
)
echo Launching...
PowerShell -NoProfile -ExecutionPolicy Bypass -File "%TEMP%\VPU-DiagTool\Run.ps1"
