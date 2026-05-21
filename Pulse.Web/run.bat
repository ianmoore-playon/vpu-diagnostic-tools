@echo off
title Pulse Web ^| VPU Diagnostics
cd /d "%~dp0"
color 0B

echo.
echo  =========================================
echo   Pulse Web  ^|  VPU Diagnostic Tools
echo  =========================================
echo.

:: ── Config ────────────────────────────────────────────────────
set "PYVER=3.12.8"
set "PYDIR=%~dp0app\python"
set "PYEXE=%PYDIR%\python.exe"
set "PYZIP=python-%PYVER%-embed-amd64.zip"
set "PYURL=https://www.python.org/ftp/python/%PYVER%/%PYZIP%"
set "PIPURL=https://bootstrap.pypa.io/get-pip.py"

:: ── Bootstrap embedded Python (first run only) ────────────────
if exist "%PYEXE%" goto :skip_setup

echo  [SETUP] Embedded Python %PYVER% not found.
echo  [SETUP] Downloading from python.org -- please wait...
echo.

if not exist "%PYDIR%" mkdir "%PYDIR%"

curl.exe -L --progress-bar -o "%PYDIR%\%PYZIP%" "%PYURL%"
if not exist "%PYDIR%\%PYZIP%" (
    echo  [ERROR] Download failed. Check your internet connection.
    pause
    exit /b 1
)

echo  [SETUP] Extracting...
powershell -NoProfile -ExecutionPolicy Bypass -Command "Add-Type -Assembly System.IO.Compression.FileSystem; try { [System.IO.Compression.ZipFile]::ExtractToDirectory('%PYDIR%\%PYZIP%', '%PYDIR%') } catch { }" >nul 2>&1
if not exist "%PYEXE%" (
    echo  [ERROR] Extraction failed -- python.exe not found after unzip.
    pause
    exit /b 1
)
del "%PYDIR%\%PYZIP%"

:: Enable site-packages
powershell -NoProfile -ExecutionPolicy Bypass -Command "Get-ChildItem '%PYDIR%' -Filter '*._pth' | ForEach-Object { (Get-Content $_.FullName) -replace '#import site', 'import site' | Set-Content $_.FullName }"

:: Bootstrap pip
echo  [SETUP] Installing pip...
curl.exe -L --silent -o "%PYDIR%\get-pip.py" "%PIPURL%"
"%PYEXE%" "%PYDIR%\get-pip.py" --no-warn-script-location --quiet
del "%PYDIR%\get-pip.py"

echo  [SETUP] Python %PYVER% ready.
echo.

:skip_setup

:: ── Patch ._pth so app/ is on sys.path ───────────────────────
powershell -NoProfile -ExecutionPolicy Bypass -Command "$f=Get-ChildItem '%PYDIR%' -Filter '*._pth' | Select-Object -First 1; if($f){$c=Get-Content $f.FullName; if($c -notcontains '..'){Add-Content $f.FullName '..'}}"

:: ── Install Python dependencies ───────────────────────────────
echo  [INFO] Checking dependencies...
"%PYEXE%" -m pip install -r app\requirements.txt --quiet --no-warn-script-location
if errorlevel 1 (
    echo  [ERROR] Dependency installation failed.
    pause
    exit /b 1
)

:: ── Open browser after server starts ─────────────────────────
echo  [INFO] Starting server at http://localhost:8765
start /b "" cmd /c "timeout /t 3 /nobreak >nul && start http://localhost:8765"

:: ── Launch server ─────────────────────────────────────────────
echo  [INFO] Press Ctrl+C to stop.
echo.
"%PYEXE%" app\main.py

:: ── On exit ───────────────────────────────────────────────────
echo.
echo  Server stopped.
pause
