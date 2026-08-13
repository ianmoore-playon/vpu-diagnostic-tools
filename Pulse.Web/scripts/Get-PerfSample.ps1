#Requires -Version 5.1
<#
.SYNOPSIS
    Samples CPU and memory over a few seconds and returns the averages.
.DESCRIPTION
    The Stream Readiness Engine needs SUSTAINED CPU/memory, not a one-instant
    snapshot -- a momentary spike at the moment of a dashboard fetch must not
    move the PASS/WARN/FAIL verdict. Get-Counter samples the processor and
    available-memory counters once per second for a short window and we average
    the cooked values.

    CPU  : \Processor(_Total)\% Processor Time  (averaged across samples)
    Memory: physical used% derived from \Memory\Available MBytes vs the host's
            total physical RAM (matches the dashboard's physical-memory view,
            not commit charge).

    Outputs JSON to stdout: { cpuAvgPercent, memAvgPercent, sampleCount,
    windowSeconds }. Errors fail soft with an {error:true} envelope -- the
    readiness engine then falls back to the single Get-Performance snapshot.
#>
[CmdletBinding()]
param(
    [int]$Samples = 3,        # number of 1-second samples to average
    [int]$IntervalSeconds = 1
)

$ErrorActionPreference = 'Stop'

try {
    $totalPhysMB = [math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1MB)

    $counter = Get-Counter -Counter '\Processor(_Total)\% Processor Time', '\Memory\Available MBytes' `
        -SampleInterval $IntervalSeconds -MaxSamples $Samples -ErrorAction Stop

    $cpuVals = @()
    $memVals = @()
    foreach ($set in $counter) {
        foreach ($s in $set.CounterSamples) {
            if ($s.Path -like '*% processor time*') {
                $cpuVals += [double]$s.CookedValue
            }
            elseif ($s.Path -like '*available mbytes*') {
                if ($totalPhysMB -gt 0) {
                    $usedPct = (($totalPhysMB - [double]$s.CookedValue) / $totalPhysMB) * 100
                    $memVals += $usedPct
                }
            }
        }
    }

    $cpuAvg = if ($cpuVals.Count) { [math]::Round((($cpuVals | Measure-Object -Average).Average), 1) } else { $null }
    $memAvg = if ($memVals.Count) { [math]::Round((($memVals | Measure-Object -Average).Average), 1) } else { $null }

    [ordered]@{
        cpuAvgPercent = $cpuAvg
        memAvgPercent = $memAvg
        sampleCount   = $cpuVals.Count
        windowSeconds = $Samples * $IntervalSeconds
    } | ConvertTo-Json -Compress
}
catch {
    [ordered]@{
        error   = $true
        message = $_.Exception.Message
        script  = 'Get-PerfSample.ps1'
    } | ConvertTo-Json -Compress
}
