@echo off
setlocal EnableDelayedExpansion
title Pulse  -  updating (beta)

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

:: ================================================================
::  Pulse updater / launcher  (BETA channel)
::
::  - Installs to C:\Pulse
::  - Pulls the latest web-beta-v* pre-release from playon/pulse
::    (falls back to the source repo, then a beta-branch commit zip)
::  - If offline or the download fails, launches the installed copy
::  - Creates a desktop shortcut; hands off to run.bat, which starts
::    the server hidden and closes this window
:: ================================================================

:: -- Config ---------------------------------------------------------------
set "CHANNEL=beta"
set "INSTALL_DIR=C:\Pulse"
set "REPO=playon/pulse"
set "PUBLIC_REPO=playon/pulse"
set "ZIPFILE=%TEMP%\pulse-dl.zip"
set "EXTRACT=%TEMP%\pulse-extract"
set "RESOLVE_OUT=%TEMP%\pulse-resolve.txt"
:: Repo copy of THIS launcher -- used to repair %INSTALL_DIR%\Pulse.bat if the
:: runtime self-copy below ever fails (see :shortcut).
set "LAUNCHER_URL=https://raw.githubusercontent.com/playon/pulse/beta/runners/run_pulse_beta.bat"

:: -- Debug mode -----------------------------------------------------------
::   Empty ("") = the quiet tester experience: the server starts hidden, the
::   browser opens on its own, and this window closes. Launch failures still
::   surface — run.bat pauses on a fatal error and everything is logged to
::   %INSTALL_DIR%\pulse-server.log.
::   Set to 1 ONLY to chase a specific launch failure: the server then runs in
::   THIS window so the traceback is visible and the window won't close on its
::   own. (Foreground mode looks "frozen" to a tester — it's just the running
::   server — so keep it off for the beta rollout.)
set "PULSE_DEBUG="

echo.
echo  .-----------------------------------------------------.
echo  ^|                                                     ^|
echo  ^| __________ ____ ___.____       ____________________ ^|
echo  ^| \______   \    ^|   \    ^|     /   _____/\_   _____/ ^|
echo  ^|  ^|     ___/    ^|   /    ^|     \_____  \  ^|    __)_  ^|
echo  ^|  ^|    ^|   ^|    ^|  /^|    ^|___  /        \ ^|        \ ^|
echo  ^|  ^|____^|   ^|______/ ^|_______ \/_______  //_______  / ^|
echo  ^|                       [ BETA ]                      ^|
echo  '-----------------------------------------------------'
echo                    VPU Diagnostics
echo.
echo   Channel : beta
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
:: Already installed and GitHub is unreachable? Launch the installed copy
:: immediately rather than waiting on a download timeout.
if exist "%INSTALL_DIR%\run.bat" (
    powershell -NoProfile -ExecutionPolicy Bypass -Command "try { $c = New-Object Net.Sockets.TcpClient; $iar = $c.BeginConnect('github.com',443,$null,$null); if ($iar.AsyncWaitHandle.WaitOne(3000) -and $c.Connected) { $c.Close(); exit 0 } else { exit 1 } } catch { exit 1 }"
    if errorlevel 1 (
        echo   Network ........................ offline - using installed build
        goto :shortcut
    )
)
echo   Network ........................ online

:: -- Resolve the latest beta release (tag^|url) ---------------------------
:: Pipes live inside the quoted -Command, so cmd won't mis-parse them; the
:: result is written to a temp file and parsed below. Output form: tag|url
::   1) newest web-beta-v* pre-release on playon/pulse
::   2) same on the source repo
::   3) fallback: beta-branch commit zip, tagged beta-<sha7>
::   On total failure the real error is reported as ERR|<why> instead of
::   being swallowed -- "no beta build found" alone is undebuggable in the field.
powershell -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference='Stop';[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12;$pat='web-beta-v*';$out='';$err='';foreach($repo in @('%PUBLIC_REPO%','%REPO%')){try{$r=Invoke-RestMethod -Uri ('https://api.github.com/repos/'+$repo+'/releases') -TimeoutSec 10}catch{$err=$_.Exception.Message;continue};$rel=$r|Where-Object{$_.tag_name -like $pat -and $_.prerelease}|Select-Object -First 1;if($rel){$asset=$rel.assets|Where-Object{$_.name -like '*.zip'}|Select-Object -First 1;if($asset){$out=$rel.tag_name+'|'+$asset.browser_download_url;break}}};if(-not $out){try{$sha=(Invoke-RestMethod -Uri 'https://api.github.com/repos/%REPO%/commits/beta' -TimeoutSec 10).sha;if($sha){$out='beta-'+$sha.Substring(0,7)+'|https://github.com/%REPO%/archive/'+$sha+'.zip'}}catch{if(-not $err){$err=$_.Exception.Message}}};if(-not $out -and $err){$out='ERR|'+($err -replace '[|]',' ' -replace '\s+',' ')};Write-Output $out" > "%RESOLVE_OUT%" 2>nul

set "RESOLVED="
if exist "%RESOLVE_OUT%" set /p RESOLVED=<"%RESOLVE_OUT%"
del "%RESOLVE_OUT%" 2>nul

set "REL_TAG="
set "ASSET_URL="
for /f "tokens=1,* delims=|" %%A in ("!RESOLVED!") do (
    set "REL_TAG=%%A"
    set "ASSET_URL=%%B"
)

:: A lookup that failed outright arrives as ERR|<why> -- show the tech the
:: real error instead of a bare "no beta build found".
if "!REL_TAG!"=="ERR" (
    echo   Update ......................... release lookup FAILED:
    echo       !ASSET_URL!
    set "ASSET_URL="
    goto :dl_failed
)
if not defined ASSET_URL (
    echo   Update ......................... no beta build found
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
:: curl is primary (clean progress bar), but the Windows-bundled curl+schannel
:: can fail the GitHub release-asset CDN redirect with SEC_E_WRONG_PRINCIPAL.
:: If curl yields no usable zip (failed or absent), fall back to PowerShell,
:: whose .NET stack uses the Windows cert store and follows the redirect cleanly.
echo   Update ......................... downloading !REL_TAG!
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
    echo   Update ......................... unavailable - using installed build
    goto :shortcut
)
echo.
echo   [ERROR] No beta build could be downloaded and none is installed.
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
xcopy "%SRC%\*" "%INSTALL_DIR%\" /s /e /y /q >nul
if exist "%EXTRACT%" rd /s /q "%EXTRACT%"

echo !REL_TAG!> "%INSTALL_DIR%\VERSION"
echo   Version ........................ !REL_TAG!

:shortcut
:: -- Self-copy + Start Menu shortcut --------------------------------------
:: Stealth footprint: no desktop icon. Findable via Start Menu — press Win,
:: type "pulse", hit Enter. Also auto-removes any existing Desktop\Pulse.lnk
:: from older launcher builds so existing installs migrate on next launch.
::
:: The shortcut targets %INSTALL_DIR%\Pulse.bat -- a self-copy of this launcher.
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
>"%INSTALL_DIR%\CHANNEL" echo %CHANNEL%

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
    echo   [ERROR] %INSTALL_DIR%\run.bat not found - install incomplete.
    goto :fatal
)
cd /d "%INSTALL_DIR%"

if not defined PULSE_DEBUG (
    call run.bat
    endlocal
    exit /b 0
)

:: -- DEBUG MODE -----------------------------------------------------------
:: Run the server in THIS window so any Python/uvicorn startup error is
:: visible, instead of starting it hidden and closing the window.
set "PYEXE=%INSTALL_DIR%\app\python\python.exe"
if not exist "%PYEXE%" (
    echo   First run - bootstrapping the runtime via run.bat ...
    set "PULSE_NO_BROWSER=1"
    call run.bat
    :: Clear the flag — the foreground server run below SHOULD open Chrome.
    set "PULSE_NO_BROWSER="
    :: run.bat starts the server hidden on success; stop it so we can run it
    :: here in the foreground, where errors are visible.
    for /f "tokens=5" %%a in ('netstat -aon 2^>nul ^| findstr ":8765 " ^| findstr "LISTENING"') do taskkill /PID %%a /F >nul 2>&1
)
if not exist "%PYEXE%" (
    echo   [ERROR] Python runtime still missing at "%PYEXE%" - bootstrap failed.
    echo           See the messages above and %INSTALL_DIR%\pulse-server.log
    goto :fatal
)
:: Free the port in case a hidden instance is already holding it.
for /f "tokens=5" %%a in ('netstat -aon 2^>nul ^| findstr ":8765 " ^| findstr "LISTENING"') do taskkill /PID %%a /F >nul 2>&1

:: Background waiter that opens Chrome the moment the server binds the port.
:: Same script normal-mode uses; the START makes it asynchronous so it polls
:: while the foreground server boots in this window.
set "WAITER=%INSTALL_DIR%\scripts\Wait-AndLaunch.ps1"
if exist "%WAITER%" (
    start "" /b powershell -NoProfile -ExecutionPolicy Bypass -File "%WAITER%" -Port 8765 -Url "http://localhost:8765" -TimeoutSec 60
)

echo.
echo  ================================================================
echo    PULSE DEBUG MODE - the server runs HERE so you can see any error.
echo    Chrome will open automatically once the server is up.
echo    Press Ctrl+C to stop.  This window will NOT close on its own.
echo  ================================================================
echo.
"%PYEXE%" "%INSTALL_DIR%\app\main.py"
echo.
echo  ================================================================
echo    [DEBUG] The server process exited. Any error/traceback is above.
echo    Also check %INSTALL_DIR%\pulse-server.log
echo  ================================================================
pause
endlocal
exit /b 0

:: -- Update-phase error handler -------------------------------------------
:fatal
echo.
echo  ============================================
echo    PULSE FAILED - see the messages above.
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
> "%DIAG_LOG%" echo Pulse launcher network diagnostics - %DATE% %TIME% - channel %CHANNEL%
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

:: One host: DNS, then TCP 443, then a real TLS handshake with the protocol
:: list pinned to Tls/Tls11/Tls12 (the .NET Framework default on this image
:: negotiates SSL3/TLS1.0 and false-fails modern hosts). Reports the
:: certificate issuer so an SSL-inspection appliance is visible at a glance.
:: PS 5.1: the validation callback MUST be cast to its delegate type
:: explicitly -- implicit conversion inside New-Object fails silently.
:probe
powershell -NoProfile -ExecutionPolicy Bypass -Command "$h='%~1';$line='';try{$null=[Net.Dns]::GetHostAddresses($h)}catch{$line=('  [FAIL] {0,-38} DNS lookup failed - {1}' -f $h,$_.Exception.Message.Trim())};if(-not $line){$c=New-Object Net.Sockets.TcpClient;$iar=$c.BeginConnect($h,443,$null,$null);if(-not ($iar.AsyncWaitHandle.WaitOne(5000) -and $c.Connected)){$line=('  [FAIL] {0,-38} DNS ok but no connection on port 443' -f $h)}else{try{$script:pe='None';$cb=[Net.Security.RemoteCertificateValidationCallback]{param($s,$cert,$chain,$e) $script:pe=$e; $true};$ss=New-Object Net.Security.SslStream($c.GetStream(),$false,$cb);$ss.AuthenticateAsClient($h,$null,[Security.Authentication.SslProtocols]'Tls,Tls11,Tls12',$false);$cert2=New-Object Security.Cryptography.X509Certificates.X509Certificate2 $ss.RemoteCertificate;$iss=(($cert2.Issuer -split ',')[0]) -replace 'CN=','';$warn='';if($script:pe.ToString() -ne 'None'){$warn=' ** CERT WARNING: '+$script:pe};$line=('  [ OK ] {0,-38} cert issuer: {1}{2}' -f $h,$iss,$warn)}catch{$line=('  [FAIL] {0,-38} TLS handshake failed - {1}' -f $h,$_.Exception.Message.Trim())};$c.Close()}};Write-Output $line;Add-Content -LiteralPath '%DIAG_LOG%' -Value $line"
goto :eof
