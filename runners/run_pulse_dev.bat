@echo off
setlocal EnableDelayedExpansion
title Pulse  -  updating (dev)

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
::  Pulse updater / launcher  (DEV channel)
::
::  - Installs to C:\Pulse
::  - Pulls the LATEST COMMIT on the dev branch directly (commit zip), so
::    dev always tracks tip-of-branch — no dependency on a tagged release.
::    Pass a branch name as the first arg to test any other branch instead.
::  - If offline or the download fails, launches the already-installed copy
::  - Hands off to run.bat, which starts the server hidden and closes
::    this window
:: ════════════════════════════════════════════════════════════════

:: -- Config ---------------------------------------------------------------
set "BRANCH=dev"
if not "%~1"=="" set "BRANCH=%~1"

set "INSTALL_DIR=C:\Pulse"
set "REPO=playon/pulse"
set "ZIPFILE=%TEMP%\pulse-dl.zip"
set "EXTRACT=%TEMP%\pulse-extract"
:: Repo copy of THIS launcher (on whichever branch we're tracking) -- used to
:: repair %INSTALL_DIR%\Pulse.bat if the runtime self-copy ever fails (see :shortcut).
set "LAUNCHER_URL=https://raw.githubusercontent.com/playon/pulse/%BRANCH%/runners/run_pulse_dev.bat"

echo.
echo  .-----------------------------------------------------.
echo  ^|                                                     ^|
echo  ^| __________ ____ ___.____       ____________________ ^|
echo  ^| \______   \    ^|   \    ^|     /   _____/\_   _____/ ^|
echo  ^|  ^|     ___/    ^|   /    ^|     \_____  \  ^|    __)_  ^|
echo  ^|  ^|    ^|   ^|    ^|  /^|    ^|___  /        \ ^|        \ ^|
echo  ^|  ^|____^|   ^|______/ ^|_______ \/_______  //_______  / ^|
echo  ^|                        [ DEV ]                      ^|
echo  '-----------------------------------------------------'
echo                    VPU Diagnostics
echo.
if /I "%BRANCH%"=="dev" ( echo   Channel : dev ) else ( echo   Channel : dev ^(%BRANCH%^) )
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

:: -- Network check + offline fast-path -----------------------------------
:: If Pulse is already installed and we can't reach GitHub, skip the update
:: entirely and launch the installed copy. A tech on a downed venue network
:: should get Pulse immediately, not after a download timeout.
::   A bare TCP connect says "online" on a network that intercepts HTTPS --
::   the socket opens, then every download fails anyway. Worse, the old check
::   only ran when a build was already installed, so a fresh VPU printed
::   "online" having tested nothing at all (Harrisonburg VA, 2026-08-11: the
::   tech saw "Network online" then "check the internet connection"). Do a
::   real handshake and look at who signed the cert. Intercepted networks
::   cannot download either, so they take the same fast path as offline.
call :netcheck
if "!NET_STATE!"=="INTERCEPTED" (
    echo   Network ........................ online, but HTTPS is intercepted
    echo     Certificates are being signed by: !NET_ISSUER!
    echo     Pulse cannot download until IT exempts GitHub from SSL inspection.
    if exist "%INSTALL_DIR%\run.bat" (
        echo     Starting the installed build instead.
        goto :shortcut
    )
)
if "!NET_STATE!"=="CLOCK" (
    echo   Network ........................ online, but certificate dates are invalid
    echo     This is usually the VPU clock, not the network - check date/time.
    if exist "%INSTALL_DIR%\run.bat" (
        echo     Starting the installed build instead.
        goto :shortcut
    )
)
if "!NET_STATE!"=="OFFLINE" (
    if exist "%INSTALL_DIR%\run.bat" (
        echo   Network ........................ offline - using installed build
        goto :shortcut
    )
    echo   Network ........................ offline
)
if "!NET_STATE!"=="OK" echo   Network ........................ online

:: -- Resolve latest commit SHA (cache-bust download) ----------------------
set "COMMIT_SHA="
for /f "usebackq delims=" %%S in (`
    powershell -NoProfile -ExecutionPolicy Bypass -Command ^
        "try { [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; (Invoke-RestMethod -Uri 'https://api.github.com/repos/%REPO%/commits/%BRANCH%' -TimeoutSec 10).sha } catch { '' }"
`) do set "COMMIT_SHA=%%S"

:: Lookup failure isn't fatal (the branch-zip URL below still works without a
:: SHA) but say so -- api.github.com being blocked is a real field failure.
if not defined COMMIT_SHA echo   Update ......................... commit lookup failed ^(api.github.com unreachable?^) - trying branch zip

:: Already up to date? Skip the download entirely. Don't re-stream a build
:: that's already installed — just go straight to launch.
if defined COMMIT_SHA if exist "%INSTALL_DIR%\VERSION" (
    set "SHORT_SHA=!COMMIT_SHA:~0,7!"
    set "INSTALLED_VER="
    set /p INSTALLED_VER=<"%INSTALL_DIR%\VERSION"
    if "!INSTALLED_VER!"=="%BRANCH%-!SHORT_SHA!" (
        echo   Update ......................... already up to date ^(!INSTALLED_VER!^)
        goto :shortcut
    )
)

if defined COMMIT_SHA (
    set "ASSET_URL=https://github.com/%REPO%/archive/!COMMIT_SHA!.zip"
) else (
    set "ASSET_URL=https://github.com/%REPO%/archive/refs/heads/%BRANCH%.zip"
)

:: -- Download -------------------------------------------------------------
:: curl is primary (clean progress bar), but the Windows-bundled curl+schannel
:: can fail the GitHub archive CDN redirect with SEC_E_WRONG_PRINCIPAL.
:: If curl yields no usable zip (failed or absent), fall back to PowerShell,
:: whose .NET stack uses the Windows cert store and follows the redirect cleanly.
echo   Update ......................... downloading %BRANCH%
if exist "%ZIPFILE%" del "%ZIPFILE%" 2>nul
where curl.exe >nul 2>&1 && curl.exe -L --progress-bar -o "%ZIPFILE%" "!ASSET_URL!"

set "DL_OK="
if exist "%ZIPFILE%" for %%A in ("%ZIPFILE%") do if %%~zA GEQ 1000 set "DL_OK=1"
if not defined DL_OK (
    echo   Update ......................... retrying via PowerShell
    if exist "%ZIPFILE%" del "%ZIPFILE%" 2>nul
    powershell -NoProfile -ExecutionPolicy Bypass -Command "$ProgressPreference='SilentlyContinue';[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; try{ Invoke-WebRequest -UseBasicParsing -Uri '!ASSET_URL!' -OutFile '%ZIPFILE%' }catch{ Write-Host ('   Download failed: '+$_.Exception.Message); exit 1 }"
)

if not exist "%ZIPFILE%" goto :dl_failed
for %%A in ("%ZIPFILE%") do if %%~zA LSS 1000 goto :dl_failed
goto :dl_ok

:dl_failed
if exist "%ZIPFILE%" del "%ZIPFILE%"
if exist "%INSTALL_DIR%\run.bat" (
    echo   Update ......................... failed - using installed build
    goto :shortcut
)
echo.
echo   [ERROR] Download failed and no installed build to fall back on.
call :netdiag
goto :fatal

:dl_ok
echo   Update ......................... extracting
if exist "%EXTRACT%" rd /s /q "%EXTRACT%"
powershell -NoProfile -ExecutionPolicy Bypass -Command "Expand-Archive -Path '%ZIPFILE%' -DestinationPath '%EXTRACT%' -Force"
del "%ZIPFILE%"

:: Find the Pulse.Web folder inside the extracted archive.
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
:: /s /e copies subdirs incl. the app\python\ runtime and settings,
:: which are preserved across updates (xcopy only overwrites shipped files).
xcopy "%SRC%\*" "%INSTALL_DIR%\" /s /e /y /q >nul
if exist "%EXTRACT%" rd /s /q "%EXTRACT%"

:: Stamp the installed version.
set "SHORT_SHA=unknown"
if defined COMMIT_SHA set "SHORT_SHA=!COMMIT_SHA:~0,7!"
echo %BRANCH%-!SHORT_SHA!> "%INSTALL_DIR%\VERSION"
echo   Version ........................ %BRANCH%-!SHORT_SHA!

:shortcut
:: -- Self-copy + Start Menu shortcut --------------------------------------
:: Stealth footprint: no desktop icon. Findable via Start Menu — press Win,
:: type "pulse", hit Enter. Also auto-removes any existing Desktop\Pulse.lnk
:: from older launcher builds so existing installs migrate on next launch.
:: Copy this launcher into the install dir so the shortcut has a stable
:: target. Guard against copying onto itself (when launched FROM the
:: shortcut, %~f0 already IS the install copy).
::
:: If that copy is ever missing, the shortcut points at nothing and the Start
:: Menu entry dies ("Missing Shortcut - Windows is searching for Pulse.bat").
:: So: self-copy; if it didn't land, fetch the launcher from the repo; and only
:: (re)create the shortcut AFTER confirming the target exists -- never orphan it.
if /I not "%~f0"=="%INSTALL_DIR%\Pulse.bat" copy /y "%~f0" "%INSTALL_DIR%\Pulse.bat" >nul
if not exist "%INSTALL_DIR%\Pulse.bat" (
    echo   Launcher self-copy ............. failed - fetching from repo
    powershell -NoProfile -ExecutionPolicy Bypass -Command "$ProgressPreference='SilentlyContinue';[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; try{ Invoke-WebRequest -UseBasicParsing -Uri '%LAUNCHER_URL%' -OutFile '%INSTALL_DIR%\Pulse.bat' }catch{}" 2>nul
)
:: Record the channel so the in-app "Check for update" knows which release line to track
>"%INSTALL_DIR%\CHANNEL" echo dev

set "ICON=%INSTALL_DIR%\app\static\img\pulse.ico"
if not exist "%ICON%" set "ICON=%INSTALL_DIR%\Pulse.bat"
:: Only (re)create the shortcut once its target is confirmed present -- never
:: orphan it. (goto, not an if/else block: keeps the powershell line below in
:: top-level parse context so its quoted parens and ^ continuation are safe.)
if not exist "%INSTALL_DIR%\Pulse.bat" goto :no_shortcut
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
    "$old=[Environment]::GetFolderPath('DesktopDirectory')+'\Pulse.lnk'; if (Test-Path $old) { Remove-Item $old -Force -ErrorAction SilentlyContinue }; $d=[Environment]::GetFolderPath('Programs'); $s=(New-Object -ComObject WScript.Shell).CreateShortcut(\"$d\Pulse.lnk\"); $s.TargetPath='%INSTALL_DIR%\Pulse.bat'; $s.WorkingDirectory='%INSTALL_DIR%'; $s.IconLocation='%ICON%'; $s.Description='Pulse - VPU Diagnostics'; $s.Save()" 2>nul
echo   Start Menu shortcut ............ ready
goto :after_shortcut
:no_shortcut
echo   Start Menu shortcut ............ SKIPPED - launcher copy unavailable
:after_shortcut

:: -- Hand off to the runtime launcher -------------------------------------
echo.
if not exist "%INSTALL_DIR%\run.bat" (
    echo   [ERROR] %INSTALL_DIR%\run.bat not found — install incomplete.
    goto :fatal
)
cd /d "%INSTALL_DIR%"
call run.bat
:: run.bat starts the hidden server and closes this window on success,
:: or pauses on its own error. Nothing left to do here.
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

:: -- Network diagnostics ---------------------------------------------------
:: Runs when no build could be downloaded AND none is installed, so the tech
:: (or the venue's IT) can see exactly which GitHub hostname this network
:: blocks. School/venue web filters commonly allow github.com but block
:: *.githubusercontent.com -- that shows up here as an OK first line with
:: FAIL lines underneath. Results also land in %TEMP%\pulse-launcher-diag.txt
:: so support can ask for the file.
:netdiag
set "DIAG_LOG=%TEMP%\pulse-launcher-diag.txt"
> "%DIAG_LOG%" echo Pulse launcher network diagnostics - %DATE% %TIME% - channel dev - branch %BRANCH%
echo.
echo   -- Network check: every host Pulse downloads from ----------------
call :probe github.com
call :probe api.github.com
call :probe codeload.github.com
call :probe objects.githubusercontent.com
call :probe release-assets.githubusercontent.com
call :probe raw.githubusercontent.com
echo   -------------------------------------------------------------------
findstr /l /c:"[FAIL]" "%DIAG_LOG%" >nul 2>&1
if errorlevel 1 goto :diag_allok
findstr /l /c:"[ OK ] github.com " "%DIAG_LOG%" >nul 2>&1
if errorlevel 1 goto :diag_list
echo   github.com works but other GitHub hosts are blocked. This is
echo   typical of a school/venue web filter, and it is why the download
echo   fails even though github.com opens fine in a browser.
:diag_list
echo   Ask the site's network admin to allow HTTPS - TCP 443 - to:
echo     api.github.com                        - finds the latest release
echo     github.com                            - starts the download
echo     objects.githubusercontent.com         - release file storage
echo     release-assets.githubusercontent.com  - release file storage
echo     codeload.github.com                   - source zip fallback
echo     raw.githubusercontent.com             - launcher updates
goto :diag_certs
:diag_allok
echo   All GitHub hosts are reachable from this machine, so the failure
echo   above may be transient - run this launcher again. If it keeps
echo   failing, send the report file below to the Pulse team.
:diag_certs
findstr /l /c:"CERT WARNING" "%DIAG_LOG%" >nul 2>&1
if not errorlevel 1 (
    echo.
    echo   A CERT WARNING above means this network intercepts HTTPS
    echo   ^(SSL inspection^). Downloads will keep failing until IT exempts
    echo   the hosts listed above from inspection.
)
echo.
echo   Report saved to: %DIAG_LOG%
goto :eof

:: -- HTTPS integrity check ------------------------------------------------
:: Sets NET_STATE to OK / INTERCEPTED / CLOCK / OFFLINE and NET_ISSUER to the
:: presented certificate's issuer CN. Same TLS technique as :probe below --
:: protocols pinned to Tls/Tls11/Tls12 (the .NET Framework default on this
:: image negotiates SSL3/TLS1.0 and false-fails modern hosts) and the
:: validation callback cast to its delegate type explicitly (PS 5.1 fails the
:: implicit conversion inside New-Object silently).
::
:: A date-only chain failure is the VPU's clock, NOT interception: an expired
:: certificate also drags in PartialChain, so classifying on "untrusted" alone
:: reports a wrong clock as SSL inspection. Verified against badssl.com --
:: untrusted-root and self-signed report INTERCEPTED, expired reports CLOCK.
::
:: The issuer is filtered to letters, digits and " ._()-" before it reaches
:: batch, so a CN containing & or a redirection character cannot break the echo.
:netcheck
set "NET_STATE=OFFLINE"
set "NET_ISSUER="
set "NETCHK_OUT=%TEMP%\pulse-netcheck.txt"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$h='github.com';$r='';try{$null=[Net.Dns]::GetHostAddresses($h)}catch{$r='OFFLINE|dns'};if(-not $r){$c=New-Object Net.Sockets.TcpClient;$c.ReceiveTimeout=8000;$c.SendTimeout=8000;$iar=$c.BeginConnect($h,443,$null,$null);if(-not ($iar.AsyncWaitHandle.WaitOne(4000) -and $c.Connected)){$r='OFFLINE|tcp'}else{try{$script:pe='None';$script:cs='';$cb=[Net.Security.RemoteCertificateValidationCallback]{param($s,$cert,$chain,$e) $script:pe=$e; if($chain -and $chain.ChainStatus){$script:cs=($chain.ChainStatus|ForEach-Object{$_.Status}) -join ','}; $true};$ss=New-Object Net.Security.SslStream($c.GetStream(),$false,$cb);$ss.AuthenticateAsClient($h,$null,[Security.Authentication.SslProtocols]'Tls,Tls11,Tls12',$false);$cert2=New-Object Security.Cryptography.X509Certificates.X509Certificate2 $ss.RemoteCertificate;$raw=(($cert2.Issuer -split ',')[0]) -replace 'CN=','';$iss=(-join ($raw.ToCharArray()|Where-Object{[char]::IsLetterOrDigit($_) -or ' ._()-'.Contains($_)})).Trim();if(-not $iss){$iss='unknown'};if($script:pe.ToString() -eq 'None'){$r='OK|'+$iss}elseif($script:cs -match 'NotTimeValid|NotTimeNested'){$r='CLOCK|'+$iss}else{$r='INTERCEPTED|'+$iss}}catch{$r='OFFLINE|tls'};$c.Close()}};Write-Output $r" > "%NETCHK_OUT%" 2>nul
set "NETCHK="
if exist "%NETCHK_OUT%" set /p NETCHK=<"%NETCHK_OUT%"
del "%NETCHK_OUT%" 2>nul
for /f "tokens=1,* delims=|" %%A in ("!NETCHK!") do (
    set "NET_STATE=%%A"
    set "NET_ISSUER=%%B"
)
goto :eof

:: One host: DNS, then TCP 443, then a real TLS handshake with the protocol
:: list pinned to Tls/Tls11/Tls12 (the .NET Framework default on this image
:: negotiates SSL3/TLS1.0 and false-fails modern hosts). Reports the
:: certificate issuer so an SSL-inspection appliance is visible at a glance.
:: PS 5.1: the validation callback MUST be cast to its delegate type
:: explicitly -- implicit conversion inside New-Object fails silently.
:probe
powershell -NoProfile -ExecutionPolicy Bypass -Command "$h='%~1';$line='';try{$null=[Net.Dns]::GetHostAddresses($h)}catch{$line=('  [FAIL] {0,-38} DNS lookup failed - {1}' -f $h,$_.Exception.Message.Trim())};if(-not $line){$c=New-Object Net.Sockets.TcpClient;$c.ReceiveTimeout=10000;$c.SendTimeout=10000;$iar=$c.BeginConnect($h,443,$null,$null);if(-not ($iar.AsyncWaitHandle.WaitOne(5000) -and $c.Connected)){$line=('  [FAIL] {0,-38} DNS ok but no connection on port 443' -f $h)}else{try{$script:pe='None';$cb=[Net.Security.RemoteCertificateValidationCallback]{param($s,$cert,$chain,$e) $script:pe=$e; $true};$ss=New-Object Net.Security.SslStream($c.GetStream(),$false,$cb);$ss.AuthenticateAsClient($h,$null,[Security.Authentication.SslProtocols]'Tls,Tls11,Tls12',$false);$cert2=New-Object Security.Cryptography.X509Certificates.X509Certificate2 $ss.RemoteCertificate;$iss=(($cert2.Issuer -split ',')[0]) -replace 'CN=','';$warn='';if($script:pe.ToString() -ne 'None'){$warn=' ** CERT WARNING: '+$script:pe};$line=('  [ OK ] {0,-38} cert issuer: {1}{2}' -f $h,$iss,$warn)}catch{$line=('  [FAIL] {0,-38} TLS handshake failed - {1}' -f $h,$_.Exception.Message.Trim())};$c.Close()}};Write-Output $line;Add-Content -LiteralPath '%DIAG_LOG%' -Value $line"
goto :eof
