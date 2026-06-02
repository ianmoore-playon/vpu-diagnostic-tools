@echo off
setlocal EnableDelayedExpansion
cd /d "%~dp0"
title Pulse  -  starting up

:: ================================================================
::  Pulse runtime launcher
::  Bootstraps embedded Python (first run), then starts the server in
::  a hidden, detached process and opens the browser. This window
::  shows setup progress, then closes itself once Pulse is running -
::  the server has no console window for anyone to click into.
:: ================================================================

set "PYVER=3.12.8"
set "PYDIR=%~dp0app\python"
set "PYEXE=%PYDIR%\python.exe"
set "PYZIP=python-%PYVER%-embed-amd64.zip"
set "PYURL=https://www.python.org/ftp/python/%PYVER%/%PYZIP%"
set "PIPURL=https://bootstrap.pypa.io/get-pip.py"
set "PORT=8765"
set "URL=http://localhost:%PORT%"

where curl.exe >nul 2>&1 && (set "HAS_CURL=1") || (set "HAS_CURL=")

:: -- Step 1/5  Embedded Python --------------------------------
if exist "%PYEXE%" (
    echo  [1/5] Python runtime ............ ready
    goto :deps
)

echo  [1/5] Python runtime ............ installing (first run, ~1-2 min)
if not exist "%PYDIR%" mkdir "%PYDIR%"

echo        - downloading Python %PYVER%
if defined HAS_CURL (
    curl.exe -L --progress-bar -o "%PYDIR%\%PYZIP%" "%PYURL%"
) else (
    powershell -NoProfile -ExecutionPolicy Bypass -Command "[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; Invoke-WebRequest -Uri '%PYURL%' -OutFile '%PYDIR%\%PYZIP%'"
)
if not exist "%PYDIR%\%PYZIP%" (
    echo  [ERROR] Python download failed - check the internet connection.
    goto :fatal
)
for %%A in ("%PYDIR%\%PYZIP%") do if %%~zA LSS 5000 (
    echo  [ERROR] Python download was incomplete ^(%%~zA bytes^).
    del "%PYDIR%\%PYZIP%"
    goto :fatal
)

echo        - extracting
powershell -NoProfile -ExecutionPolicy Bypass -Command "Add-Type -Assembly System.IO.Compression.FileSystem; [System.IO.Compression.ZipFile]::ExtractToDirectory('%PYDIR%\%PYZIP%', '%PYDIR%')" 2>nul
if not exist "%PYEXE%" (
    echo  [ERROR] Python extraction failed - python.exe not found.
    goto :fatal
)
del "%PYDIR%\%PYZIP%"

echo        - verifying
"%PYEXE%" --version >nul 2>&1
if errorlevel 1 (
    echo  [ERROR] Extracted Python won't run - archive may be corrupt.
    echo          Delete "%PYDIR%" and relaunch.
    goto :fatal
)

echo        - enabling site-packages
powershell -NoProfile -ExecutionPolicy Bypass -Command "$f = Get-ChildItem '%PYDIR%' -Filter '*._pth' | Select-Object -First 1; if (-not $f) { exit 1 }; (Get-Content $f.FullName) -replace '#import site','import site' | Set-Content $f.FullName"
if errorlevel 1 (
    echo  [ERROR] Could not enable site-packages - Python install is broken.
    goto :fatal
)

echo        - installing pip
if defined HAS_CURL (
    curl.exe -L --silent -o "%PYDIR%\get-pip.py" "%PIPURL%"
) else (
    powershell -NoProfile -ExecutionPolicy Bypass -Command "[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; Invoke-WebRequest -Uri '%PIPURL%' -OutFile '%PYDIR%\get-pip.py'"
)
if not exist "%PYDIR%\get-pip.py" (
    echo  [ERROR] Failed to download get-pip.py
    goto :fatal
)
"%PYEXE%" "%PYDIR%\get-pip.py" --no-warn-script-location --quiet
if errorlevel 1 (
    echo  [ERROR] pip installation failed.
    goto :fatal
)
del "%PYDIR%\get-pip.py"
echo  [1/5] Python runtime ............ installed

:deps
:: -- Step 2/5  Ensure app/ is importable ----------------------
powershell -NoProfile -ExecutionPolicy Bypass -Command "$f = Get-ChildItem '%PYDIR%' -Filter '*._pth' | Select-Object -First 1; if ($f) { $c = Get-Content $f.FullName; if ($c -notcontains '..') { Add-Content $f.FullName '..' } }"

:: -- Step 2/5  Dependencies -----------------------------------
echo  [2/5] Dependencies ............. checking
"%PYEXE%" -m pip install -r app\requirements.txt --quiet --no-warn-script-location
if errorlevel 1 (
    echo        first attempt failed - retrying with detail...
    "%PYEXE%" -m pip install -r app\requirements.txt --no-warn-script-location
    if errorlevel 1 (
        echo  [ERROR] Dependencies could not be installed.
        goto :fatal
    )
)
echo  [2/5] Dependencies ............. ready

:: -- Step 3/5  Sanity check -----------------------------------
if not exist "app\main.py" (
    echo  [ERROR] app\main.py not found in %CD% - install looks incomplete.
    goto :fatal
)
echo  [3/5] Application files ........ ok

:: -- Step 4/5  Free the port ----------------------------------
set "KILLED="
for /f "tokens=5" %%a in ('netstat -aon 2^>nul ^| findstr ":%PORT% " ^| findstr "LISTENING"') do (
    taskkill /PID %%a /F >nul 2>&1
    set "KILLED=1"
)
if defined KILLED (
    echo  [4/5] Port %PORT% ............... freed previous instance
) else (
    echo  [4/5] Port %PORT% ............... clear
)

:: -- Step 5/5  Start the hidden server + open the browser -----
echo  [5/5] Starting Pulse ........... launching
if not exist "%~dp0pulse-launch.vbs" (
    echo  [ERROR] pulse-launch.vbs missing - cannot start hidden server.
    goto :fatal
)
wscript "%~dp0pulse-launch.vbs"

:: Wait until the server is actually accepting connections, then open
:: the browser. Returns 0 once the port is up, 1 on timeout.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\Wait-AndLaunch.ps1" -Port %PORT% -Url "%URL%" -TimeoutSec 40
if errorlevel 1 (
    echo.
    echo  [ERROR] Pulse did not come up within 40 seconds.
    echo          Check %~dp0pulse-server.log for details.
    goto :fatal
)

echo.
echo  ========================================================
echo    Pulse is running at %URL%
echo    Opened in your browser. This window will now close.
echo  ========================================================
:: Brief pause so the success message is readable, then exit cleanly.
:: The server keeps running hidden; the caller closes this window.
ping -n 3 127.0.0.1 >nul
endlocal
exit /b 0

:: -- Error handler --------------------------------------------
:fatal
echo.
echo  ============================================
echo    PULSE FAILED TO START
echo    See the messages above. Press any key to close.
echo  ============================================
pause >nul
endlocal
exit /b 1
