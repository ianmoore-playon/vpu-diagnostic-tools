@echo off
cd /d "%~dp0"

:: ── Silent mode (launched from launch.vbs — no console window) ─
set "SILENT="
if "%~1"=="--silent" set "SILENT=1"

if not defined SILENT (
    title Pulse Web ^| VPU Diagnostics
    color 0B
)

echo.
echo  .-----------------------------------------------------.
echo  ^|                                                     ^|
echo  ^| __________ ____ ___.____       ____________________ ^|
echo  ^| \______   \    ^|   \    ^|     /   _____/\_   _____/ ^|
echo  ^|  ^|     ___/    ^|   /    ^|     \_____  \  ^|    __)_  ^|
echo  ^|  ^|    ^|   ^|    ^|  /^|    ^|___  /        \ ^|        \ ^|
echo  ^|  ^|____^|   ^|______/ ^|_______ \/_______  //_______  / ^|
echo  ^|                            \/        \/         \/  ^|
echo  ^|                                                     ^|
echo  '-----------------------------------------------------'
echo                    VPU Diagnostic Tools
echo.

:: ── Config ────────────────────────────────────────────────────
set "PYVER=3.12.8"
set "PYDIR=%~dp0app\python"
set "PYEXE=%PYDIR%\python.exe"
set "PYZIP=python-%PYVER%-embed-amd64.zip"
set "PYURL=https://www.python.org/ftp/python/%PYVER%/%PYZIP%"
set "PIPURL=https://bootstrap.pypa.io/get-pip.py"

:: ── Check for curl (some VPUs don't have it) ─────────────────
set "HAS_CURL="
where curl.exe >nul 2>&1 && set "HAS_CURL=1"

:: ── Bootstrap embedded Python (first run only) ────────────────
if exist "%PYEXE%" (
    echo  [INFO] Python %PYVER% found at %PYEXE%
    goto :skip_setup
)

echo  [SETUP] Embedded Python %PYVER% not found.
echo  [SETUP] Downloading from python.org -- please wait...
echo  [SETUP] URL: %PYURL%
echo.

if not exist "%PYDIR%" (
    echo  [SETUP] Creating directory: %PYDIR%
    mkdir "%PYDIR%"
)

echo  [SETUP] Downloading Python...
if defined HAS_CURL (
    curl.exe -L --progress-bar -o "%PYDIR%\%PYZIP%" "%PYURL%"
) else (
    powershell -NoProfile -ExecutionPolicy Bypass -Command "[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; Invoke-WebRequest -Uri '%PYURL%' -OutFile '%PYDIR%\%PYZIP%'"
)
if not exist "%PYDIR%\%PYZIP%" (
    echo.
    echo  [ERROR] Python download failed. File not found: %PYDIR%\%PYZIP%
    echo  [ERROR] Check your internet connection.
    goto :fatal
)
for %%A in ("%PYDIR%\%PYZIP%") do (
    echo  [SETUP] Downloaded %%~zA bytes
    if %%~zA LSS 5000 (
        echo  [ERROR] Download too small ^(%%~zA bytes^) — likely a network error.
        del "%PYDIR%\%PYZIP%"
        goto :fatal
    )
)

echo  [SETUP] Extracting Python...
powershell -NoProfile -ExecutionPolicy Bypass -Command "Add-Type -Assembly System.IO.Compression.FileSystem; try { [System.IO.Compression.ZipFile]::ExtractToDirectory('%PYDIR%\%PYZIP%', '%PYDIR%') } catch { Write-Host '[ERROR] Extraction exception:' $_.Exception.Message }" 2>&1
if not exist "%PYEXE%" (
    echo  [ERROR] Extraction failed — python.exe not found after unzip.
    echo  [ERROR] Expected: %PYEXE%
    echo  [ERROR] Contents of %PYDIR%:
    dir /b "%PYDIR%" 2>nul
    goto :fatal
)
del "%PYDIR%\%PYZIP%"
echo  [SETUP] Python extracted OK.

:: Verify the extracted Python actually runs (catches partial downloads
:: that passed the 5KB size check but were truncated mid-archive).
"%PYEXE%" --version >nul 2>&1
if errorlevel 1 (
    echo  [ERROR] Extracted Python failed to run. Archive may be corrupt.
    echo  [ERROR] Delete %PYDIR% and try again.
    goto :fatal
)

:: Enable site-packages
echo  [SETUP] Enabling site-packages...
powershell -NoProfile -ExecutionPolicy Bypass -Command "$count = (Get-ChildItem '%PYDIR%' -Filter '*._pth' | ForEach-Object { (Get-Content $_.FullName) -replace '#import site', 'import site' | Set-Content $_.FullName; 1 } | Measure-Object).Count; if ($count -lt 1) { Write-Host '[ERROR] No ._pth file found to patch'; exit 1 }"
if errorlevel 1 (
    echo  [ERROR] Could not enable site-packages — Python install is broken.
    goto :fatal
)

:: Bootstrap pip
echo  [SETUP] Installing pip...
if defined HAS_CURL (
    curl.exe -L --silent -o "%PYDIR%\get-pip.py" "%PIPURL%"
) else (
    powershell -NoProfile -ExecutionPolicy Bypass -Command "[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; Invoke-WebRequest -Uri '%PIPURL%' -OutFile '%PYDIR%\get-pip.py'"
)
if not exist "%PYDIR%\get-pip.py" (
    echo  [ERROR] Failed to download get-pip.py from %PIPURL%
    goto :fatal
)
"%PYEXE%" "%PYDIR%\get-pip.py" --no-warn-script-location --quiet
if errorlevel 1 (
    echo  [ERROR] pip installation failed ^(exit code %errorlevel%^).
    goto :fatal
)
del "%PYDIR%\get-pip.py"

echo  [SETUP] Python %PYVER% ready.
echo.

:skip_setup

:: ── Patch ._pth so app/ is on sys.path ───────────────────────
powershell -NoProfile -ExecutionPolicy Bypass -Command "$f=Get-ChildItem '%PYDIR%' -Filter '*._pth' | Select-Object -First 1; if($f){$c=Get-Content $f.FullName; if($c -notcontains '..'){Add-Content $f.FullName '..'}}"

:: ── Kill stale Pulse Web processes ────────────────────────────
for /f "tokens=5" %%a in ('netstat -aon 2^>nul ^| findstr ":8765 " ^| findstr "LISTENING"') do (
    echo  [INFO] Killing stale Pulse process ^(PID %%a^) on port 8765
    taskkill /PID %%a /F >nul 2>&1
)

:: ── Install Python dependencies ───────────────────────────────
echo  [INFO] Checking dependencies...
"%PYEXE%" -m pip install -r app\requirements.txt --quiet --no-warn-script-location
if errorlevel 1 (
    echo.
    echo  [ERROR] Dependency installation failed.
    echo  [ERROR] Retrying with verbose output...
    echo.
    "%PYEXE%" -m pip install -r app\requirements.txt --no-warn-script-location
    if errorlevel 1 (
        echo.
        echo  [ERROR] Dependencies could not be installed.
        goto :fatal
    )
)
echo  [INFO] Dependencies OK.

:: ── Verify main.py exists ────────────────────────────────────
if not exist "app\main.py" (
    echo  [ERROR] app\main.py not found in %CD%
    echo  [ERROR] Directory contents:
    dir /b 2>nul
    echo  [ERROR] app\ contents:
    dir /b app\ 2>nul
    goto :fatal
)

:: ── Open browser after server starts ─────────────────────────
:: Poll port 8765 until uvicorn is actually accepting connections, then
:: launch Chrome. A fixed 3s sleep races on cold VPUs where Python
:: bootstrap takes longer — browser would open to "can't connect".
echo  [INFO] Starting server at http://localhost:8765
start /b "" powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\Wait-AndLaunch.ps1" -Port 8765 -Url "http://localhost:8765" -TimeoutSec 30

:: ── Launch server ─────────────────────────────────────────────
if not defined SILENT (
    echo  [INFO] Press Ctrl+C to stop.
)
echo.
"%PYEXE%" app\main.py
set "EXIT_CODE=%errorlevel%"

:: ── On exit ───────────────────────────────────────────────────
echo.
if %EXIT_CODE% NEQ 0 (
    echo  [ERROR] Server exited with code %EXIT_CODE%.
    goto :fatal
)
echo  Server stopped.
if not defined SILENT pause
goto :eof

:: ── Fatal error handler ──────────────────────────────────────
:fatal
echo.
echo  ============================================
echo   PULSE WEB FAILED TO START
echo   See errors above. Press any key to close.
echo  ============================================
pause
exit /b 1
