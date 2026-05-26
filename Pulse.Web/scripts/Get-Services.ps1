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
    $serviceList = @(
        @{ name = 'agent';        fallbackDisplay = 'Pixellot Agent' }
        @{ name = 'coordinator';  fallbackDisplay = 'Pixellot Coordinator' }
        @{ name = 'vpu';          fallbackDisplay = 'Pixellot VPU' }
        @{ name = 'scoreconnect'; fallbackDisplay = 'ScoreConnect' }
        @{ name = 'LogMeIn';      fallbackDisplay = 'LogMeIn Remote Access' }
    )

    $services = foreach ($entry in $serviceList) {
        $svc = Get-Service -Name $entry.name -ErrorAction SilentlyContinue
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
                name        = $entry.name
                displayName = $entry.fallbackDisplay
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
