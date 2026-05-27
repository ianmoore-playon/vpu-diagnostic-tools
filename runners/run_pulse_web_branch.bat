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
set "BRANCH=dev"
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

:: -- Resolve latest commit SHA (used for cache-bust download) -------------
echo  [INFO] Resolving latest commit on '%BRANCH%'...
set "COMMIT_SHA=unknown"
for /f "usebackq delims=" %%S in (`
    powershell -NoProfile -ExecutionPolicy Bypass -Command ^
        "try { " ^
        "  [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; " ^
        "  $r = Invoke-RestMethod -Uri 'https://api.github.com/repos/%REPO%/commits/%BRANCH%' -TimeoutSec 10; " ^
        "  $r.sha " ^
        "} catch { '' }"
`) do set "COMMIT_SHA=%%S"

:: -- Download branch zip (commit-specific to bypass CDN cache) -----------
set "ASSET_URL="
if "%COMMIT_SHA%"=="" set "ASSET_URL=https://github.com/%REPO%/archive/refs/heads/%BRANCH%.zip"
if "%COMMIT_SHA%"=="unknown" set "ASSET_URL=https://github.com/%REPO%/archive/refs/heads/%BRANCH%.zip"
if not defined ASSET_URL set "ASSET_URL=https://github.com/%REPO%/archive/%COMMIT_SHA%.zip"
echo  [INFO] SHA: %COMMIT_SHA%
echo  [INFO] URL: %ASSET_URL%
echo  [INFO] Downloading branch '%BRANCH%'...

:: -- Check for curl (some VPUs don't have it) --
set "HAS_CURL="
where curl.exe >nul 2>&1 && set "HAS_CURL=1"

if defined HAS_CURL (
    curl.exe -L --progress-bar -o "%ZIPFILE%" "%ASSET_URL%"
) else (
    echo  [INFO] curl not found, using PowerShell...
    powershell -NoProfile -ExecutionPolicy Bypass -Command "[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; Invoke-WebRequest -Uri '%ASSET_URL%' -OutFile '%ZIPFILE%'"
)

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
goto :fatal

:dl_ok

:: -- Extract --------------------------------------------------------------
echo  [INFO] Extracting to %EXTRACT%...
if exist "%EXTRACT%" rd /s /q "%EXTRACT%"
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
    "Expand-Archive -Path '%ZIPFILE%' -DestinationPath '%EXTRACT%' -Force"
echo  [INFO] Extraction complete.
del "%ZIPFILE%"

:: Find Pulse.Web content — branch zip layout: repo-BRANCH\Pulse.Web\run.bat
echo  [INFO] Searching for Pulse.Web in extracted files...
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
    goto :fatal
)
echo  [INFO] Source: %SRC%

:: -- Copy to install dir (preserves app\python\ and settings) -------------
echo  [INFO] Copying to %INSTALL_DIR%...
if not exist "%INSTALL_DIR%" mkdir "%INSTALL_DIR%"
xcopy "%SRC%\*" "%INSTALL_DIR%\" /s /e /y /q >nul
if exist "%EXTRACT%" rd /s /q "%EXTRACT%"
echo  [INFO] Copy complete.

:: -- Stamp VERSION with branch + commit SHA --------------------------------
set "SHORT_SHA=%COMMIT_SHA:~0,7%"
if "%SHORT_SHA%"=="" set "SHORT_SHA=unknown"
echo %BRANCH%-%SHORT_SHA%> "%INSTALL_DIR%\VERSION"
echo  [INFO] Version: %BRANCH%-%SHORT_SHA%

echo  [INFO] Updated to latest '%BRANCH%' branch.
echo.

:: -- Launch ---------------------------------------------------------------
:launch
if not exist "%INSTALL_DIR%\run.bat" (
    echo  [ERROR] Pulse Web not found at %INSTALL_DIR%
    goto :fatal
)

echo  [INFO] Launching from %INSTALL_DIR%...
cd /d "%INSTALL_DIR%"
call run.bat
goto :done

:: -- Error handler --------------------------------------------------------
:fatal
echo.
echo  ============================================
echo   PULSE WEB FAILED — see errors above.
echo   Press any key to close.
echo  ============================================
pause >nul
exit /b 1

:done

:: If we get here, run.bat exited — keep window open so errors are visible
echo.
echo  [INFO] Pulse Web exited. Press any key to close.
pause >nul
