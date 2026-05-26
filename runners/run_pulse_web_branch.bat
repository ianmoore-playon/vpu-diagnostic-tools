@echo off
title Pulse Web BRANCH ^| VPU Diagnostics
color 0E

echo.
echo  =========================================
echo   Pulse Web BRANCH  ^|  VPU Diagnostic Tools
echo  =========================================
echo.

:: -- Config ---------------------------------------------------------------
:: Change BRANCH to test any branch directly on the VPU.
set "BRANCH=web-convert"
if not "%~1"=="" set "BRANCH=%~1"

set "INSTALL_DIR=%LOCALAPPDATA%\PulseWeb-branch"
set "REPO=ianmoore-playon/vpu-diagnostic-tools"
set "ZIPFILE=%TEMP%\pulse-web-branch-dl.zip"
set "EXTRACT=%TEMP%\pulse-web-branch-extract"

echo  [INFO] Branch: %BRANCH%
echo.

:: -- Install Chrome if missing --------------------------------------------
reg query "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\chrome.exe" >nul 2>&1
if %errorlevel% NEQ 0 (
    echo  [INFO] Chrome not found — installing...
    powershell -Command "Invoke-WebRequest -Uri 'https://dl.google.com/chrome/install/latest/chrome_installer.exe' -OutFile '%TEMP%\chrome_installer.exe'"
    echo  [INFO] Running Chrome installer...
    start /wait "" "%TEMP%\chrome_installer.exe" /silent /install
    del "%TEMP%\chrome_installer.exe"
    echo  [INFO] Chrome installed.
) else (
    echo  [INFO] Chrome already installed.
)
echo.

:: -- Download branch zip --------------------------------------------------
set "ASSET_URL=https://github.com/%REPO%/archive/refs/heads/%BRANCH%.zip"
echo  [INFO] URL: %ASSET_URL%
echo  [INFO] Downloading branch '%BRANCH%'...
curl.exe -L --progress-bar -o "%ZIPFILE%" "%ASSET_URL%"

if not exist "%ZIPFILE%" goto :dl_failed
for %%A in ("%ZIPFILE%") do (
    echo  [INFO] Downloaded %ZIPFILE% (%%~zA bytes^)
    if %%~zA LSS 1000 goto :dl_failed
)
goto :dl_ok

:dl_failed
if exist "%ZIPFILE%" del "%ZIPFILE%"
if exist "%INSTALL_DIR%\run.bat" (
    echo  [WARN] Download failed — launching cached version.
    goto :launch
)
echo  [ERROR] Download failed. Check your internet connection or branch name.
pause
exit /b 1

:dl_ok

:: -- Extract --------------------------------------------------------------
echo  [INFO] Extracting to %EXTRACT%...
if exist "%EXTRACT%" rd /s /q "%EXTRACT%"
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
    "Expand-Archive -Path '%ZIPFILE%' -DestinationPath '%EXTRACT%' -Force"
del "%ZIPFILE%"

:: Find Pulse.Web content — branch zip layout: repo-BRANCH\Pulse.Web\run.bat
set "SRC="
if exist "%EXTRACT%\run.bat" (
    echo  [INFO] Found run.bat at extract root.
    set "SRC=%EXTRACT%"
)
if not defined SRC for /d %%d in ("%EXTRACT%\*") do (
    if exist "%%d\run.bat" (
        echo  [INFO] Found run.bat at %%d
        set "SRC=%%d"
    )
)
if not defined SRC for /d %%d in ("%EXTRACT%\*") do (
    if exist "%%d\Pulse.Web\run.bat" (
        echo  [INFO] Found Pulse.Web at %%d\Pulse.Web
        set "SRC=%%d\Pulse.Web"
    )
)

if not defined SRC (
    echo  [ERROR] Pulse.Web not found in downloaded archive.
    echo  [ERROR] Full directory listing:
    dir /b /s /ad "%EXTRACT%" 2>nul
    if exist "%EXTRACT%" rd /s /q "%EXTRACT%"
    pause
    exit /b 1
)

:: -- Copy to install dir (preserves app\python\ and settings) -------------
if not exist "%INSTALL_DIR%" mkdir "%INSTALL_DIR%"
xcopy "%SRC%\*" "%INSTALL_DIR%\" /s /e /y /q >nul
if exist "%EXTRACT%" rd /s /q "%EXTRACT%"

:: -- Stamp VERSION with branch + commit SHA --------------------------------
for /f "usebackq delims=" %%S in (`
    powershell -NoProfile -ExecutionPolicy Bypass -Command ^
        "try { " ^
        "  $r = Invoke-RestMethod -Uri 'https://api.github.com/repos/%REPO%/commits/%BRANCH%' -TimeoutSec 10; " ^
        "  $r.sha.Substring(0,7) " ^
        "} catch { 'unknown' }"
`) do set "COMMIT_SHA=%%S"
echo %BRANCH%-%COMMIT_SHA%> "%INSTALL_DIR%\VERSION"
echo  [INFO] Version: %BRANCH%-%COMMIT_SHA%

echo  [INFO] Updated to latest '%BRANCH%' branch.
echo.

:: -- Launch ---------------------------------------------------------------
:launch
if not exist "%INSTALL_DIR%\run.bat" (
    echo  [ERROR] Pulse Web not found at %INSTALL_DIR%
    pause
    exit /b 1
)

cd /d "%INSTALL_DIR%"
call run.bat
