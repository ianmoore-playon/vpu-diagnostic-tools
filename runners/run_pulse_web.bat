@echo off
title Pulse Web ^| VPU Diagnostics
color 0B

echo.
echo  =========================================
echo   Pulse Web  ^|  VPU Diagnostic Tools
echo  =========================================
echo.

set "INSTALL_DIR=%LOCALAPPDATA%\PulseWeb"
set "REPO=ianmoore-playon/vpu-diagnostic-tools"
set "PUBLIC_REPO=ianmoore-playon/pulse-releases"
set "ZIPFILE=%TEMP%\pulse-web-dl.zip"
set "EXTRACT=%TEMP%\pulse-web-extract"

:: ── Install Chrome if missing ────────────────────────────────
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

:: ── Try release download first ──────────────────────────────
echo  [INFO] Checking for latest Pulse Web release...
set "ASSET_URL="
for /f "usebackq delims=" %%U in (`
    powershell -NoProfile -ExecutionPolicy Bypass -Command ^
        "try { " ^
        "  $r = Invoke-RestMethod -Uri 'https://api.github.com/repos/%PUBLIC_REPO%/releases' -TimeoutSec 10; " ^
        "  $rel = $r | Where-Object { $_.tag_name -like 'web-v*' -and -not $_.prerelease } | Select-Object -First 1; " ^
        "  if ($rel) { $rel.assets[0].browser_download_url } " ^
        "} catch {}"
`) do set "ASSET_URL=%%U"

if not defined ASSET_URL (
    echo  [INFO] No release found on pulse-releases, trying source repo...
    for /f "usebackq delims=" %%U in (`
        powershell -NoProfile -ExecutionPolicy Bypass -Command ^
            "try { " ^
            "  $r = Invoke-RestMethod -Uri 'https://api.github.com/repos/%REPO%/releases' -TimeoutSec 10; " ^
            "  $rel = $r | Where-Object { $_.tag_name -like 'web-v*' -and -not $_.prerelease } | Select-Object -First 1; " ^
            "  if ($rel) { $rel.assets[0].browser_download_url } " ^
            "} catch {}"
    `) do set "ASSET_URL=%%U"
)

if not defined ASSET_URL (
    echo  [WARN] No releases found — falling back to branch zip.
    set "ASSET_URL=https://github.com/%REPO%/archive/refs/heads/web-convert.zip"
)

:: ── Download ────────────────────────────────────────────────
echo  [INFO] URL: %ASSET_URL%
echo  [INFO] Downloading latest Pulse Web...
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
echo  [ERROR] Download failed. Check your internet connection.
pause
exit /b 1

:dl_ok

:: ── Extract ─────────────────────────────────────────────────
echo  [INFO] Extracting to %EXTRACT%...
if exist "%EXTRACT%" rd /s /q "%EXTRACT%"
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
    "Expand-Archive -Path '%ZIPFILE%' -DestinationPath '%EXTRACT%' -Force"
del "%ZIPFILE%"

echo  [INFO] Archive contents:
dir /b /s "%EXTRACT%\run.bat" 2>nul || echo         (no run.bat found anywhere)
echo  [INFO] Top-level folders:
dir /b /ad "%EXTRACT%" 2>nul || echo         (none)

:: Find Pulse.Web content — try every known zip layout:
::   release zip:  run.bat at extract root or one folder deep
::   branch zip:   repo-BRANCH\Pulse.Web\run.bat
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

:: ── Copy to install dir (preserves app\python\ and settings) ─
if not exist "%INSTALL_DIR%" mkdir "%INSTALL_DIR%"
xcopy "%SRC%\*" "%INSTALL_DIR%\" /s /e /y /q >nul
if exist "%EXTRACT%" rd /s /q "%EXTRACT%"

echo  [INFO] Updated to latest version.
echo.

:: ── Launch ───────────────────────────────────────────────────
:launch
if not exist "%INSTALL_DIR%\run.bat" (
    echo  [ERROR] Pulse Web not found at %INSTALL_DIR%
    pause
    exit /b 1
)

cd /d "%INSTALL_DIR%"
call run.bat
