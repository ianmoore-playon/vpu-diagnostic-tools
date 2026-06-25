#Requires -Version 5.1
<#
.SYNOPSIS
    Install (or remove) Pulse as an unattended Windows service for the
    proactive-monitoring pilot (PULSEDEV-51 / PULSEDEV-55).

.DESCRIPTION
    Wraps the existing embedded-Python server (app\python\python.exe app\main.py)
    in a Windows service via NSSM, so Pulse runs headless, survives logout and
    reboot, and runs the background readiness loop. The service sets
    PULSE_MONITOR=1 - the ONLY thing that turns the loop on - so an interactive
    launch of run.bat is completely unaffected (no loop, no extra beacons).

    The service still serves the localhost UI on the same port, so it composes
    with the remote-access (Cloudflare tunnel) track: an alert fires, a tech
    clicks in to the live UI on the same box.

    State (pulse-monitor-state.json) and logs land in the install dir, so a
    reinstall (which re-downloads C:\Pulse) clears the ledger cleanly.

.PARAMETER InstallDir
    Pulse install root (default C:\Pulse - what the channel launchers use).

.PARAMETER Port
    Port the service binds (default 8765, the canonical Pulse port). On a pilot
    box the service OWNS this port; do not also run the interactive launcher
    against it (run.bat frees the port on start and would kill the service).

.PARAMETER NssmPath
    Path to nssm.exe. Defaults to <InstallDir>\tools\nssm.exe, then PATH. If not
    found and -DownloadNssm is set, fetches the official nssm release.

.PARAMETER DownloadNssm
    Download nssm.exe from nssm.cc if it isn't found.

.PARAMETER Uninstall
    Stop and remove the service instead of installing.

.EXAMPLE
    # From an ELEVATED shell on the VPU (LMI must be elevated - see runbook):
    powershell -ExecutionPolicy Bypass -File install_pulse_service.ps1 -DownloadNssm

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File install_pulse_service.ps1 -Uninstall
#>
[CmdletBinding()]
param(
    [string]$InstallDir = 'C:\Pulse',
    [int]$Port = 8765,
    [string]$ServiceName = 'Pulse',
    [string]$NssmPath,
    [switch]$DownloadNssm,
    [switch]$Uninstall,
    # Lab affordance: short cadences so you don't wait ~20 min to see a recompute
    # (heartbeat 60 s / full 120 s / incident 30 s). Don't use in production.
    [switch]$FastTest
)

$ErrorActionPreference = 'Stop'

function Fail($msg) { Write-Host "  [ERROR] $msg" -ForegroundColor Red; exit 1 }
function Info($msg) { Write-Host "  $msg" }

# -- Elevation gate -----------------------------------------------------------
# Registering a service requires admin. This is the open question for the LMI
# pilot (PULSEDEV-55): if the LMI shell is NOT elevated, this stops here with a
# clear message rather than half-installing.
$id = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($id)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Fail "Not elevated. Service install/removal needs admin rights. Re-run this from an elevated shell (the LMI session must be elevated)."
}

# -- Locate nssm --------------------------------------------------------------
function Resolve-Nssm {
    if ($NssmPath -and (Test-Path -LiteralPath $NssmPath)) { return (Resolve-Path $NssmPath).Path }
    $local = Join-Path $InstallDir 'tools\nssm.exe'
    if (Test-Path -LiteralPath $local) { return $local }
    $onPath = Get-Command nssm.exe -ErrorAction SilentlyContinue
    if ($onPath) { return $onPath.Source }
    if ($DownloadNssm) {
        $toolsDir = Join-Path $InstallDir 'tools'
        if (-not (Test-Path $toolsDir)) { New-Item -ItemType Directory -Path $toolsDir -Force | Out-Null }
        $zip = Join-Path $env:TEMP 'nssm.zip'
        $extract = Join-Path $env:TEMP 'nssm-extract'
        Info "nssm not found - downloading the official release ..."
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri 'https://nssm.cc/release/nssm-2.24.zip' -OutFile $zip
        if (Test-Path $extract) { Remove-Item $extract -Recurse -Force }
        Add-Type -Assembly System.IO.Compression.FileSystem
        [System.IO.Compression.ZipFile]::ExtractToDirectory($zip, $extract)
        # 64-bit build lives under nssm-2.24\win64\nssm.exe
        $src = Get-ChildItem -Path $extract -Recurse -Filter 'nssm.exe' |
               Where-Object { $_.FullName -match 'win64' } | Select-Object -First 1
        if (-not $src) { Fail "nssm.exe not found in the downloaded archive." }
        Copy-Item $src.FullName $local -Force
        Remove-Item $zip, $extract -Recurse -Force -ErrorAction SilentlyContinue
        return $local
    }
    Fail "nssm.exe not found. Pass -NssmPath, drop it at $local, put it on PATH, or pass -DownloadNssm."
}

$nssm = Resolve-Nssm
Info "Using nssm: $nssm"

# -- Uninstall path -----------------------------------------------------------
if ($Uninstall) {
    Info "Stopping + removing service '$ServiceName' ..."
    & $nssm stop $ServiceName 2>$null | Out-Null
    & $nssm remove $ServiceName confirm 2>$null | Out-Null
    Info "Done. (State file left in place; delete $InstallDir\pulse-monitor-state.json to reset the ledger.)"
    exit 0
}

# -- Validate the install layout ----------------------------------------------
$pyExe  = Join-Path $InstallDir 'app\python\python.exe'
$mainPy = Join-Path $InstallDir 'app\main.py'
if (-not (Test-Path -LiteralPath $pyExe))  { Fail "Embedded Python not found at $pyExe. Run the Pulse launcher once first so the runtime bootstraps." }
if (-not (Test-Path -LiteralPath $mainPy)) { Fail "app\main.py not found at $mainPy. Is $InstallDir a Pulse install?" }

$svcLog = Join-Path $InstallDir 'pulse-service.log'

# -- Install / reconfigure (idempotent) ---------------------------------------
$existing = & $nssm status $ServiceName 2>$null
if ($LASTEXITCODE -eq 0 -and $existing) {
    Info "Service exists - stopping to reconfigure ..."
    & $nssm stop $ServiceName 2>$null | Out-Null
} else {
    Info "Installing service '$ServiceName' ..."
    & $nssm install $ServiceName $pyExe $mainPy
    if ($LASTEXITCODE -ne 0) { Fail "nssm install failed (exit $LASTEXITCODE)." }
}

& $nssm set $ServiceName Application $pyExe                | Out-Null
& $nssm set $ServiceName AppParameters "`"$mainPy`""        | Out-Null
& $nssm set $ServiceName AppDirectory $InstallDir          | Out-Null
& $nssm set $ServiceName DisplayName 'Pulse VPU Monitor'   | Out-Null
& $nssm set $ServiceName Description 'Pulse proactive monitoring - unattended readiness loop + check-in beacon (PULSEDEV-50).' | Out-Null
& $nssm set $ServiceName Start SERVICE_AUTO_START          | Out-Null
# PULSE_MONITOR=1 is what enables the loop; PORT pins the bind. -FastTest adds
# short cadences so a lab run shows a recompute in a minute, not twenty.
$envExtra = @("PULSE_MONITOR=1", "PORT=$Port")
if ($FastTest) {
    $envExtra += @("PULSE_MONITOR_HEARTBEAT_SECONDS=60",
                   "PULSE_MONITOR_FULL_SECONDS=120",
                   "PULSE_MONITOR_INCIDENT_SECONDS=30",
                   "PULSE_MONITOR_STARTUP_DELAY_SECONDS=5")
    Info "FastTest cadences: heartbeat 60s / full 120s / incident 30s"
}
& $nssm set $ServiceName AppEnvironmentExtra $envExtra | Out-Null
& $nssm set $ServiceName AppStdout $svcLog                 | Out-Null
& $nssm set $ServiceName AppStderr $svcLog                 | Out-Null
& $nssm set $ServiceName AppRotateFiles 1                  | Out-Null
& $nssm set $ServiceName AppRotateBytes 5242880            | Out-Null
# Auto-restart on crash with a short throttle so a boot-time flap can't hot-loop.
& $nssm set $ServiceName AppExit Default Restart           | Out-Null
& $nssm set $ServiceName AppThrottle 5000                  | Out-Null

Info "Starting service ..."
& $nssm start $ServiceName | Out-Null
Start-Sleep -Seconds 2
$status = & $nssm status $ServiceName 2>$null
Info "Service status: $status"
Info ""
Info "Pulse monitor is installed. UI: http://localhost:$Port   Service log: $svcLog"
Info "Verify the loop started:  Get-Content '$svcLog' -Tail 30   (look for 'Proactive monitor starting')"
