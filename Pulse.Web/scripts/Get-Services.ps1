#Requires -Version 5.1
<#
.SYNOPSIS
    Checks Pixellot service statuses.
.DESCRIPTION
    Queries the status of known Pixellot and supporting services.
    Outputs JSON to stdout.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

try {
    $serviceNames = @(
        'PixellotAgent'
        'PixellotCoordinator'
        'PixellotVPU'
        'ScoreConnect'
        'LogMeIn'
    )

    $services = foreach ($name in $serviceNames) {
        $svc = Get-Service -Name $name -ErrorAction SilentlyContinue
        if ($svc) {
            [ordered]@{
                name        = $svc.Name
                displayName = $svc.DisplayName
                status      = $svc.Status.ToString()
                startType   = $svc.StartType.ToString()
            }
        }
        else {
            [ordered]@{
                name        = $name
                displayName = $null
                status      = 'NotFound'
                startType   = $null
            }
        }
    }

    [ordered]@{
        services = @($services)
    } | ConvertTo-Json -Depth 3 -Compress
}
catch {
    [ordered]@{
        error   = $true
        message = $_.Exception.Message
        script  = 'Get-Services.ps1'
    } | ConvertTo-Json -Compress
}
