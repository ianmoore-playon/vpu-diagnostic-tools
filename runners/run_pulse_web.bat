@echo off
setlocal EnableDelayedExpansion
title Pulse  -  updating

:: -- Run as Administrator -------------------------------------------------
::   Pulse's checks read HKLM, query WMI/CIM, and inspect Windows services
::   and the Pixellot install -- all most reliable with admin rights.
::   Self-elevate via UAC so the launcher, the hidden server, and every
::   PowerShell probe it spawns run at full capability. The /elevated
::   sentinel breaks any relaunch loop; if UAC is declined we continue with
::   limited diagnostics rather than failing outright.
if /I "%~1"=="/elevated" ( shift & goto :gotadmin )
net session >nul 2>&1
if %errorlevel% EQU 0 goto :gotadmin
echo   Requesting administrator access ...
powershell -NoProfile -ExecutionPolicy Bypass -Command "try { Start-Process -FilePath '%~f0' -ArgumentList '/elevated %*' -Verb RunAs -ErrorAction Stop } catch { exit 1 }"
if not errorlevel 1 exit /b
echo   Administrator access declined - continuing with limited diagnostics.
:gotadmin

:: ════════════════════════════════════════════════════════════════
::  Pulse updater / launcher  (PRODUCTION channel)
::
::  - Installs to C:\Pulse
::  - Pulls the latest web-v* release from pulse-releases
::    (falls back to the source repo, then a main-branch commit zip)
::  - If offline or the download fails, launches the installed copy
::  - Creates a desktop shortcut; hands off to run.bat, which starts
::    the server hidden and closes this window
:: ════════════════════════════════════════════════════════════════

:: -- Config ---------------------------------------------------------------
set "CHANNEL=production"
set "INSTALL_DIR=C:\Pulse"
set "REPO=ianmoore-playon/vpu-diagnostic-tools"
set "PUBLIC_REPO=ianmoore-playon/pulse-releases"
set "ZIPFILE=%TEMP%\pulse-dl.zip"
set "EXTRACT=%TEMP%\pulse-extract"
set "RESOLVE_OUT=%TEMP%\pulse-resolve.txt"

echo.
echo  .-----------------------------------------------------.
echo  ^|                                                     ^|
echo  ^| __________ ____ ___.____       ____________________ ^|
echo  ^| \______   \    ^|   \    ^|     /   _____/\_   _____/ ^|
echo  ^|  ^|     ___/    ^|   /    ^|     \_____  \  ^|    __)_  ^|
echo  ^|  ^|    ^|   ^|    ^|  /^|    ^|___  /        \ ^|        \ ^|
echo  ^|  ^|____^|   ^|______/ ^|_______ \/_______  //_______  / ^|
echo  ^|                                                     ^|
echo  '-----------------------------------------------------'
echo                    VPU Diagnostics
echo.
echo   Install : %INSTALL_DIR%
echo.

:: -- Chrome (install if missing) ------------------------------------------
reg query "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\chrome.exe" >nul 2>&1
if %errorlevel% NEQ 0 (
    echo   Chrome ......................... installing
    powershell -NoProfile -ExecutionPolicy Bypass -Command "[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; Invoke-WebRequest -Uri 'https://dl.google.com/chrome/install/latest/chrome_installer.exe' -OutFile '%TEMP%\chrome_installer.exe'"
    start /wait "" "%TEMP%\chrome_installer.exe" /silent /install
    del "%TEMP%\chrome_installer.exe" 2>nul
    echo   Chrome ......................... installed
) else (
    echo   Chrome ......................... ok
)

:: -- Offline fast-path ----------------------------------------------------
if exist "%INSTALL_DIR%\run.bat" (
    powershell -NoProfile -ExecutionPolicy Bypass -Command "try { $c = New-Object Net.Sockets.TcpClient; $iar = $c.BeginConnect('github.com',443,$null,$null); if ($iar.AsyncWaitHandle.WaitOne(3000) -and $c.Connected) { $c.Close(); exit 0 } else { exit 1 } } catch { exit 1 }"
    if errorlevel 1 (
        echo   Network ........................ offline - using installed build
        goto :shortcut
    )
)
echo   Network ........................ online

:: -- Resolve the latest production release (tag^|url) ---------------------
::   1) newest web-v* (non-prerelease) on pulse-releases
::   2) same on the source repo
::   3) fallback: main-branch commit zip, tagged main-<sha7>
powershell -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference='SilentlyContinue';[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12;$pat='web-v*';$out='';foreach($repo in @('%PUBLIC_REPO%','%REPO%')){try{$r=Invoke-RestMethod -Uri ('https://api.github.com/repos/'+$repo+'/releases') -TimeoutSec 10}catch{continue};$rel=$r|Where-Object{$_.tag_name -like $pat -and -not $_.prerelease}|Select-Object -First 1;if($rel){$out=$rel.tag_name+'|'+$rel.assets[0].browser_download_url;break}};if(-not $out){try{$sha=(Invoke-RestMethod -Uri 'https://api.github.com/repos/%REPO%/commits/main' -TimeoutSec 10).sha;if($sha){$out='main-'+$sha.Substring(0,7)+'|https://github.com/%REPO%/archive/'+$sha+'.zip'}}catch{}};Write-Output $out" > "%RESOLVE_OUT%" 2>nul

set "RESOLVED="
if exist "%RESOLVE_OUT%" set /p RESOLVED=<"%RESOLVE_OUT%"
del "%RESOLVE_OUT%" 2>nul

set "REL_TAG="
set "ASSET_URL="
for /f "tokens=1,* delims=|" %%A in ("!RESOLVED!") do (
    set "REL_TAG=%%A"
    set "ASSET_URL=%%B"
)

if not defined ASSET_URL (
    echo   Update ......................... no release found
    goto :dl_failed
)

:: -- Already up to date? Skip the download --------------------------------
if exist "%INSTALL_DIR%\VERSION" (
    set "INSTALLED_VER="
    set /p INSTALLED_VER=<"%INSTALL_DIR%\VERSION"
    if "!INSTALLED_VER!"=="!REL_TAG!" (
        echo   Update ......................... already up to date ^(!REL_TAG!^)
        goto :shortcut
    )
)

:: -- Download -------------------------------------------------------------
echo   Update ......................... downloading !REL_TAG!
where curl.exe >nul 2>&1 && (set "HAS_CURL=1") || (set "HAS_CURL=")
if defined HAS_CURL (
    curl.exe -L --progress-bar -o "%ZIPFILE%" "!ASSET_URL!"
) else (
    powershell -NoProfile -ExecutionPolicy Bypass -Command "[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; Invoke-WebRequest -Uri '!ASSET_URL!' -OutFile '%ZIPFILE%'"
)

if not exist "%ZIPFILE%" goto :dl_failed
for %%A in ("%ZIPFILE%") do if %%~zA LSS 1000 goto :dl_failed
goto :dl_ok

:dl_failed
if exist "%ZIPFILE%" del "%ZIPFILE%"
if exist "%INSTALL_DIR%\run.bat" (
    echo   Update ......................... unavailable - using installed build
    goto :shortcut
)
echo   [ERROR] No release could be downloaded and none is installed.
echo           Check the internet connection and try again.
goto :fatal

:dl_ok
echo   Update ......................... extracting
if exist "%EXTRACT%" rd /s /q "%EXTRACT%"
powershell -NoProfile -ExecutionPolicy Bypass -Command "Expand-Archive -Path '%ZIPFILE%' -DestinationPath '%EXTRACT%' -Force"
del "%ZIPFILE%"

set "SRC="
if exist "%EXTRACT%\run.bat" set "SRC=%EXTRACT%"
if not defined SRC for /d %%d in ("%EXTRACT%\*") do if exist "%%d\run.bat" set "SRC=%%d"
if not defined SRC for /d %%d in ("%EXTRACT%\*") do if exist "%%d\Pulse.Web\run.bat" set "SRC=%%d\Pulse.Web"

if not defined SRC (
    echo   [ERROR] Downloaded archive did not contain Pulse.Web.
    if exist "%EXTRACT%" rd /s /q "%EXTRACT%"
    goto :fatal
)

echo   Update ......................... installing to %INSTALL_DIR%
if not exist "%INSTALL_DIR%" mkdir "%INSTALL_DIR%" 2>nul
if not exist "%INSTALL_DIR%" (
    echo   [ERROR] Could not create %INSTALL_DIR%.
    echo           Run this launcher as Administrator.
    if exist "%EXTRACT%" rd /s /q "%EXTRACT%"
    goto :fatal
)
xcopy "%SRC%\*" "%INSTALL_DIR%\" /s /e /y /q >nul
if exist "%EXTRACT%" rd /s /q "%EXTRACT%"

echo !REL_TAG!> "%INSTALL_DIR%\VERSION"
echo   Version ........................ !REL_TAG!

:shortcut
:: -- Self-copy + Start Menu shortcut --------------------------------------
:: Stealth footprint: no desktop icon. Findable via Start Menu — press Win,
:: type "pulse", hit Enter. Also auto-removes any existing Desktop\Pulse.lnk
:: from older launcher builds so existing installs migrate on next launch.
if /I not "%~f0"=="%INSTALL_DIR%\Pulse.bat" copy /y "%~f0" "%INSTALL_DIR%\Pulse.bat" >nul 2>&1
:: Record the channel so the in-app "Check for update" knows which release line to track
>"%INSTALL_DIR%\CHANNEL" echo %CHANNEL%

set "ICON=%INSTALL_DIR%\app\static\img\pulse.ico"
if not exist "%ICON%" set "ICON=%INSTALL_DIR%\Pulse.bat"
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
    "$old=[Environment]::GetFolderPath('DesktopDirectory')+'\Pulse.lnk'; if (Test-Path $old) { Remove-Item $old -Force -ErrorAction SilentlyContinue }; $d=[Environment]::GetFolderPath('Programs'); $s=(New-Object -ComObject WScript.Shell).CreateShortcut(\"$d\Pulse.lnk\"); $s.TargetPath='%INSTALL_DIR%\Pulse.bat'; $s.WorkingDirectory='%INSTALL_DIR%'; $s.IconLocation='%ICON%'; $s.Description='Pulse - VPU Diagnostics'; $s.Save()" 2>nul
echo   Start Menu shortcut ............ ready

:: -- Hand off to the runtime launcher -------------------------------------
echo.
if not exist "%INSTALL_DIR%\run.bat" (
    echo   [ERROR] %INSTALL_DIR%\run.bat not found — install incomplete.
    goto :fatal
)
cd /d "%INSTALL_DIR%"
call run.bat
endlocal
exit /b 0

:: -- Update-phase error handler -------------------------------------------
:fatal
echo.
echo  ============================================
echo    PULSE UPDATE FAILED — see messages above.
echo    Press any key to close.
echo  ============================================
pause >nul
endlocal
exit /b 1
