@echo off
REM ============================================================================
REM  Pulse Beta - share-once launcher
REM
REM  Hand THIS file to beta testers (one time). It is intentionally tiny and
REM  never needs to change: on every run it downloads the CURRENT beta launcher
REM  from the repo, then runs it. So when we fix or update the launcher during
REM  beta, testers pick it up automatically on their next launch - nobody has to
REM  re-download anything. Keep it on the Desktop and double-click to start Pulse.
REM ============================================================================
setlocal EnableExtensions
title Pulse - starting (beta)

set "LAUNCHER_URL=https://raw.githubusercontent.com/playon/pulse/beta/runners/run_pulse_beta.bat"
set "CACHE_DIR=%LOCALAPPDATA%\PulseBeta"
set "LAUNCHER=%CACHE_DIR%\run_pulse_beta.bat"
if not exist "%CACHE_DIR%" mkdir "%CACHE_DIR%" >nul 2>&1

echo.
echo   Getting the latest Pulse launcher...

REM Download to a temp name first, then swap in - a failed or partial download
REM must never clobber a known-good cached copy.
set "OK="
where curl.exe >nul 2>&1
if not errorlevel 1 (
    curl.exe -fsSL --connect-timeout 10 -o "%LAUNCHER%.new" "%LAUNCHER_URL%" && set "OK=1"
)
if not defined OK (
    powershell -NoProfile -ExecutionPolicy Bypass -Command "try{[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; Invoke-WebRequest -UseBasicParsing -TimeoutSec 15 -Uri '%LAUNCHER_URL%' -OutFile '%LAUNCHER%.new'; exit 0}catch{Write-Host ('   Download failed: '+$_.Exception.Message); exit 1}" && set "OK=1"
)

REM Only accept the download if it looks like a real launcher (>200 bytes),
REM not a tiny error page. Otherwise keep whatever we already had cached.
if defined OK (
    for %%A in ("%LAUNCHER%.new") do if %%~zA GTR 200 move /y "%LAUNCHER%.new" "%LAUNCHER%" >nul
)
if exist "%LAUNCHER%.new" del "%LAUNCHER%.new" >nul 2>&1

if not exist "%LAUNCHER%" (
    echo.
    echo   [ERROR] Couldn't download the Pulse launcher and there's no cached
    echo           copy yet. The messages above show the exact error.
    echo.
    echo   This download comes from raw.githubusercontent.com - school and
    echo   venue web filters often block that host even when github.com
    echo   itself opens fine in a browser. If this VPU is otherwise online,
    echo   ask the site's network admin to allow HTTPS ^(TCP 443^) to:
    echo     raw.githubusercontent.com   github.com   api.github.com
    echo     codeload.github.com         *.githubusercontent.com
    echo.
    pause
    exit /b 1
)

if not defined OK echo   (offline - using the last downloaded launcher)

REM Hand off to the real launcher. It self-elevates (UAC), installs/updates
REM Pulse under C:\Pulse, and opens it in Chrome. %* forwards any arguments.
endlocal & call "%LAUNCHER%" %*
