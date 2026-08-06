# Get-EventWindowSignals.ps1 -- LOCAL collector
#
# Time-anchored failure signals for the Event Streaming lane: boots/shutdowns,
# GPU driver faults, Pixellot service failures, and Pixellot app crashes from
# the Windows event logs, over the last N days. The backend intersects these
# timestamps with each event's scheduled window to say WHAT was wrong on the
# box while a stream was failing (unit off, GPU fault, agent down, crash) --
# evidence anchored to the event itself, not present-state guessing.
#
# Read-only; Windows event log queries only.

param(
    [int]$DaysBack = 21
)

$ErrorActionPreference = 'Stop'

function Get-SafeMessage($evt, $max) {
    $msg = $null
    try { $msg = $evt.Message } catch { }
    if ($null -eq $msg) { return '' }
    $msg = ($msg -replace '\s+', ' ').Trim()
    if ($msg.Length -gt $max) { $msg = $msg.Substring(0, $max) }
    return $msg
}

try {
    $since = (Get-Date).AddDays(-$DaysBack)
    $boots = @()
    $shutdowns = @()
    $gpuErrors = @()
    $serviceEvents = @()
    $appCrashes = @()

    # -- Power timeline: 6005 boot (event log started), 6006 clean shutdown
    #    (logged at the actual shutdown), 6008 unexpected shutdown. NOTE:
    #    6008 (and kernel-power 41, which we skip entirely) are logged at the
    #    NEXT BOOT -- the true off time is only in 6008's properties (time
    #    string + date string). We parse those; if parsing fails the record
    #    falls back to TimeCreated (~boot instant), which degrades to a
    #    zero-length off-period instead of a false one.
    try {
        $power = Get-WinEvent -FilterHashtable @{
            LogName = 'System'; Id = @(6005, 6006, 6008); StartTime = $since
        } -ErrorAction SilentlyContinue
        foreach ($e in @($power)) {
            $t = $e.TimeCreated.ToString('o')
            if ($e.Id -eq 6005) {
                $boots += $t
            }
            elseif ($e.Id -eq 6006) {
                $shutdowns += [pscustomobject]@{
                    time       = $t
                    unexpected = $false
                }
            }
            else {
                # 6008: properties[0] = time-of-day string, [1] = date string
                $actual = $null
                try {
                    $timeStr = [string]$e.Properties[0].Value
                    $dateStr = [string]$e.Properties[1].Value
                    $actual = [datetime]::Parse("$dateStr $timeStr")
                } catch { }
                $shutdowns += [pscustomobject]@{
                    time       = $(if ($actual) { $actual.ToString('o') } else { $t })
                    unexpected = $true
                }
            }
        }
    } catch { }

    # -- GPU faults: 4101 = display driver stopped responding (TDR); plus any
    #    error-level events from the NVIDIA kernel driver.
    try {
        $gpu = Get-WinEvent -FilterHashtable @{
            LogName = 'System'; Id = 4101; StartTime = $since
        } -ErrorAction SilentlyContinue
        foreach ($e in @($gpu)) {
            $gpuErrors += [pscustomobject]@{
                time     = $e.TimeCreated.ToString('o')
                provider = $e.ProviderName
                detail   = Get-SafeMessage $e 160
            }
        }
    } catch { }
    try {
        $nv = Get-WinEvent -FilterHashtable @{
            LogName = 'System'; ProviderName = 'nvlddmkm'; Level = @(1, 2, 3); StartTime = $since
        } -ErrorAction SilentlyContinue
        foreach ($e in @($nv)) {
            $gpuErrors += [pscustomobject]@{
                time     = $e.TimeCreated.ToString('o')
                provider = 'nvlddmkm'
                detail   = Get-SafeMessage $e 160
            }
        }
    } catch { }

    # -- Pixellot service trouble: SCM events for services whose name mentions
    #    pixellot / agent / coordinator / keepagentup. 7031/7034 crash-stops,
    #    7000/7009 start failures.
    try {
        $scm = Get-WinEvent -FilterHashtable @{
            LogName = 'System'; ProviderName = 'Service Control Manager';
            Id = @(7000, 7009, 7031, 7034); StartTime = $since
        } -ErrorAction SilentlyContinue
        foreach ($e in @($scm)) {
            $msg = Get-SafeMessage $e 200
            if ($msg -match '(?i)pixellot|keepagentup|coordinator|\bagent\b') {
                $serviceEvents += [pscustomobject]@{
                    time   = $e.TimeCreated.ToString('o')
                    id     = $e.Id
                    detail = $msg
                }
            }
        }
    } catch { }

    # -- Pixellot app crashes: Application Error 1000 mentioning Pixellot bits.
    try {
        $app = Get-WinEvent -FilterHashtable @{
            LogName = 'Application'; ProviderName = 'Application Error';
            Id = 1000; StartTime = $since
        } -ErrorAction SilentlyContinue
        foreach ($e in @($app)) {
            $msg = Get-SafeMessage $e 200
            if ($msg -match '(?i)pixellot|keepagentup|coordinator') {
                $appCrashes += [pscustomobject]@{
                    time   = $e.TimeCreated.ToString('o')
                    detail = $msg
                }
            }
        }
    } catch { }

    # Bound the payload; newest first where it matters.
    $gpuErrors     = @($gpuErrors     | Sort-Object -Property time -Descending | Select-Object -First 50)
    $serviceEvents = @($serviceEvents | Sort-Object -Property time -Descending | Select-Object -First 50)
    $appCrashes    = @($appCrashes    | Sort-Object -Property time -Descending | Select-Object -First 50)

    $result = [ordered]@{
        available     = $true
        daysBack      = $DaysBack
        collectedAt   = (Get-Date).ToString('o')
        boots         = @($boots | Sort-Object)
        shutdowns     = @($shutdowns | Sort-Object -Property time)
        gpuErrors     = $gpuErrors
        serviceEvents = $serviceEvents
        appCrashes    = $appCrashes
    }

    $result | ConvertTo-Json -Depth 4 -Compress
}
catch {
    $err = [ordered]@{
        error   = $true
        message = $_.Exception.Message
    }
    $err | ConvertTo-Json -Compress
}
