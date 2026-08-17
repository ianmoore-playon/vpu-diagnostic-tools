#Requires -Version 5.1
<#
.SYNOPSIS
    Reports status of Pixellot core components + supporting Windows services.
.DESCRIPTION
    Pixellot's core components (Agent, Coordinator, VPU, KeepAgentUp) are NOT
    Windows services -- they are plain executables in C:\Pixellot\Bin launched
    by the KeepAgentUp watchdog. Querying them with Get-Service always returns
    "NotFound" even while they're running (visible as Agent.exe / Coordinator.exe
    / KeepAgentUp.exe in Task Manager). So we detect those by PROCESS, scoped to
    the Pixellot\Bin path to avoid matching look-alikes (e.g. leaf_agent.exe).

    Supporting components (ScoreConnect, LogMeIn) ARE real Windows services and
    are queried with Get-Service. ScoreConnect ships under three versioned
    service names -- 'scoreconnect' (SC I), 'scoreconnectii' (SC II) and
    'scoreconnectiii' (SC III) -- and Get-Service -Name matches exactly, so we
    probe all three and surface whichever is present (a Running instance wins;
    otherwise the newest installed). This mirrors Get-ScoreConnectStatus.ps1 and
    fixes a stale "Not Found" on SC III boxes where only the bare 'scoreconnect'
    name was queried.

    KeepAgentUp is monitored explicitly: it's the watchdog that relaunches
    Agent/Coordinator if they die, so "watchdog down" is itself a finding.

    Output schema (per entry) -- superset of the old shape so the frontend and
    _compute_findings keep working:
        name, displayName, status (Running|Stopped|NotFound), startType,
        kind (process|service), pid, path, memoryMB
    Outputs JSON to stdout.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$PIX_BIN = 'C:\Pixellot\Bin'

# kind=process  -> matched by executable basename, scoped to C:\Pixellot\Bin
# kind=service  -> matched by Get-Service name. Optional 'names' lists candidate
#                 service names to probe, newest-first; falls back to 'name'.
$components = @(
    @{ name = 'agent';        display = 'Pixellot Agent';              kind = 'process'; exe = 'Agent.exe' }
    @{ name = 'coordinator';  display = 'Pixellot Coordinator';        kind = 'process'; exe = 'Coordinator.exe' }
    @{ name = 'vpu';          display = 'Pixellot VPU';                kind = 'process'; exe = 'vpu.exe' }
    @{ name = 'keepagentup';  display = 'Pixellot Watchdog (KeepAgentUp)'; kind = 'process'; exe = 'KeepAgentUp.exe'; watchdog = $true }
    @{ name = 'scoreconnect'; display = 'ScoreConnect';                kind = 'service'; names = @('scoreconnectiii', 'scoreconnectii', 'scoreconnect') }
    @{ name = 'LogMeIn';      display = 'LogMeIn Remote Access';       kind = 'service' }
)

try {
    # One CIM pull for all processes -- Win32_Process exposes ExecutablePath and
    # ProcessId without the access-denied issues Get-Process .Path can hit.
    $allProcs = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue)

    $results = foreach ($c in $components) {
        if ($c.kind -eq 'process') {
            $exe = $c.exe
            $binLower = $PIX_BIN.ToLower()

            # Prefer an exact-name match whose ExecutablePath is under
            # C:\Pixellot\Bin (definitively ours). Fall back to a name-only
            # match if ExecutablePath is unavailable (CIM returned null) -- a
            # null path shouldn't cause a false "Stopped" when the proc exists.
            $match = $allProcs | Where-Object {
                $_.Name -ieq $exe -and $_.ExecutablePath -and
                $_.ExecutablePath.ToLower().StartsWith($binLower)
            } | Select-Object -First 1
            if (-not $match) {
                $match = $allProcs | Where-Object { $_.Name -ieq $exe } | Select-Object -First 1
            }

            if ($match) {
                [ordered]@{
                    name        = $c.name
                    displayName = $c.display
                    status      = 'Running'
                    startType   = $null
                    kind        = 'process'
                    pid         = [int]$match.ProcessId
                    path        = $match.ExecutablePath
                    memoryMB    = if ($match.WorkingSetSize) { [math]::Round($match.WorkingSetSize / 1MB, 0) } else { $null }
                    watchdog    = [bool]$c.watchdog
                }
            }
            else {
                [ordered]@{
                    name        = $c.name
                    displayName = $c.display
                    status      = 'Stopped'   # process not found = not running
                    startType   = $null
                    kind        = 'process'
                    pid         = $null
                    path        = $null
                    memoryMB    = $null
                    watchdog    = [bool]$c.watchdog
                }
            }
        }
        else {
            # Probe every candidate service name (newest-first). Prefer a
            # Running instance; otherwise take the first that exists, which --
            # because 'names' is ordered newest-first -- is the newest installed.
            $names = if ($c.names) { $c.names } else { @($c.name) }
            $found = @(foreach ($n in $names) { Get-Service -Name $n -ErrorAction SilentlyContinue })
            $svc = $found | Where-Object { $_.Status -eq 'Running' } | Select-Object -First 1
            if (-not $svc) { $svc = $found | Select-Object -First 1 }
            if ($svc) {
                [ordered]@{
                    name        = $svc.Name
                    displayName = $svc.DisplayName
                    status      = $svc.Status.ToString()
                    startType   = $svc.StartType.ToString()
                    kind        = 'service'
                    pid         = $null
                    path        = $null
                    memoryMB    = $null
                    watchdog    = $false
                }
            }
            else {
                [ordered]@{
                    name        = $c.name
                    displayName = $c.display
                    status      = 'NotFound'
                    startType   = $null
                    kind        = 'service'
                    pid         = $null
                    path        = $null
                    memoryMB    = $null
                    watchdog    = $false
                }
            }
        }
    }

    [ordered]@{
        services = @($results)
    } | ConvertTo-Json -Depth 3 -Compress
}
catch {
    [ordered]@{
        error   = $true
        message = $_.Exception.Message
        script  = 'Get-Services.ps1'
    } | ConvertTo-Json -Compress
}
