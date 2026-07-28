#Requires -Version 5.1
<#
.SYNOPSIS
    Restarts a named Pixellot service.
.DESCRIPTION
    Validates the service name against an allowlist, then stops and starts it.
    Outputs JSON result to stdout.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ServiceName
)

$ErrorActionPreference = 'Stop'

try {
    # Allowlist of services that may be restarted. ScoreConnect ships under
    # versioned service names (SC I/II/III), so all three are permitted — the
    # Service Status tab reports whichever is installed. Matching is
    # case-insensitive (-notin), so casing from the SCM doesn't matter.
    $allowedServices = @(
        'PixellotAgent'
        'PixellotCoordinator'
        'PixellotVPU'
        'ScoreConnect'
        'ScoreConnectII'
        'ScoreConnectIII'
    )

    if ($ServiceName -notin $allowedServices) {
        [ordered]@{
            success = $false
            message = "Service '$ServiceName' is not in the allowed list. Permitted: $($allowedServices -join ', ')"
        } | ConvertTo-Json -Compress
        return
    }

    # Verify service exists
    $svc = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    if (-not $svc) {
        [ordered]@{
            success = $false
            message = "Service '$ServiceName' not found on this system."
        } | ConvertTo-Json -Compress
        return
    }

    # Stop the service
    if ($svc.Status -eq 'Running') {
        Stop-Service -Name $ServiceName -Force -ErrorAction Stop
        # Wait for stop (up to 30 seconds)
        $svc.WaitForStatus('Stopped', [TimeSpan]::FromSeconds(30))
    }

    # Start the service
    Start-Service -Name $ServiceName -ErrorAction Stop
    # Wait for start (up to 30 seconds)
    $svc = Get-Service -Name $ServiceName
    $svc.WaitForStatus('Running', [TimeSpan]::FromSeconds(30))

    # Verify final state
    $finalSvc = Get-Service -Name $ServiceName
    [ordered]@{
        success = ($finalSvc.Status -eq 'Running')
        message = "Service '$ServiceName' is now $($finalSvc.Status)."
    } | ConvertTo-Json -Compress
}
catch {
    [ordered]@{
        success = $false
        message = $_.Exception.Message
    } | ConvertTo-Json -Compress
}
