@echo off
>nul 2>&1 "%SYSTEMROOT%\system32\cacls.exe" "%SYSTEMROOT%\system32\config\system"

if '%errorlevel%' NEQ '0' (
    echo Requesting Admin access...
    goto goUAC )
    goto runpulse

:goUAC
    echo Set UAC = CreateObject^("Shell.Application"^) > "%temp%\getadmin.vbs"
    set params = %*:"=""
    echo UAC.ShellExecute "cmd.exe", "/c %~s0 %params%", "", "runas", 1 >> "%temp%\getadmin.vbs"
    "%temp%\getadmin.vbs"
    del "%temp%\getadmin.vbs"
    exit /b 0

:runpulse
echo Installing Chrome...
powershell -Command "Invoke-WebRequest -Uri 'https://dl.google.com/chrome/install/latest/chrome_installer.exe' -OutFile '%TEMP%\chrome_installer.exe'"
echo Installing Chrome
start /wait "" "%TEMP%\chrome_installer.exe" /silent /install
echo Deleting Chrome installer
del "%TEMP%\chrome_installer.exe"
echo Downloading Pulse now...
powershell -Command "irm https://raw.githubusercontent.com/playon/pulse/main/install.ps1 | iex"