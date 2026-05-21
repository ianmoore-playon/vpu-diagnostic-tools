#Requires -Version 5.1
<#
.SYNOPSIS
    Retrieves filtered Windows event log entries.
.DESCRIPTION
    Queries System and Application logs for hardware, network, and
    Pixellot-related events. Outputs JSON to stdout.
#>
[CmdletBinding()]
param(
    [int]$HoursBack = 48,
    [ValidateSet('all', 'error', 'warning', 'info')]
    [string]$Level = 'all'
)

$ErrorActionPreference = 'Stop'

try {
    $startTime = (Get-Date).AddHours(-$HoursBack)

    # Map level filter to numeric values
    $levelFilter = switch ($Level) {
        'error'   { @(1, 2) }
        'warning' { @(3) }
        'info'    { @(4) }
        'all'     { @(1, 2, 3, 4) }
    }

    $providers = @(
        'disk'
        'nvme'
        'iaStorAC'
        'Pixellot*'
        'Service Control Manager'
        'Application Error'
        'WHEA-Logger'
        'NETLOGON'
        'Tcpip'
        'e1iexpress'
        'e1dexpress'
        'e1cexpress'
        'rt640x64'
        'Microsoft-Windows-NDIS'
        'Dhcp-Client'
    )

    $allEvents = @()

    # Query System log per provider (wildcards require individual queries)
    foreach ($provider in $providers) {
        try {
            $filter = @{
                LogName   = 'System'
                ProviderName = $provider
                Level     = $levelFilter
                StartTime = $startTime
            }
            $events = Get-WinEvent -FilterHashtable $filter -MaxEvents 100 -ErrorAction SilentlyContinue
            if ($events) {
                $allEvents += $events
            }
        }
        catch { }

        # Also try Application log for app-level providers
        if ($provider -like 'Pixellot*' -or $provider -eq 'Application Error') {
            try {
                $filter = @{
                    LogName   = 'Application'
                    ProviderName = $provider
                    Level     = $levelFilter
                    StartTime = $startTime
                }
                $events = Get-WinEvent -FilterHashtable $filter -MaxEvents 100 -ErrorAction SilentlyContinue
                if ($events) {
                    $allEvents += $events
                }
            }
            catch { }
        }
    }

    # Sort by time descending and cap at 500
    $allEvents = $allEvents | Sort-Object TimeCreated -Descending | Select-Object -First 500

    $entries = @($allEvents | ForEach-Object {
        $levelStr = switch ($_.Level) {
            1 { 'Critical' }
            2 { 'Error' }
            3 { 'Warning' }
            4 { 'Info' }
            default { "Level$($_.Level)" }
        }
        $msg = if ($_.Message) {
            if ($_.Message.Length -gt 500) { $_.Message.Substring(0, 500) } else { $_.Message }
        } else { $null }

        [ordered]@{
            timeCreated = $_.TimeCreated.ToString('o')
            level       = $levelStr
            source      = $_.ProviderName
            eventId     = $_.Id
            message     = $msg
        }
    })

    [ordered]@{
        count   = $entries.Count
        entries = $entries
    } | ConvertTo-Json -Depth 4 -Compress
}
catch {
    [ordered]@{
        error   = $true
        message = $_.Exception.Message
        script  = 'Get-EventLogs.ps1'
    } | ConvertTo-Json -Compress
}
