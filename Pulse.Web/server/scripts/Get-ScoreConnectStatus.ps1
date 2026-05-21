#Requires -Version 5.1
<#
.SYNOPSIS
    Probes ScoreConnect service for status and configuration.
.DESCRIPTION
    Makes HTTP requests to the ScoreConnect local API to check
    reachability and retrieve configuration. Outputs JSON to stdout.
#>
[CmdletBinding()]
param(
    [string]$BaseUrl = 'http://localhost:5000'
)

$ErrorActionPreference = 'Stop'

try {
    $reachable     = $false
    $configuration = $null
    $errorMsg      = $null
    $statusData    = $null

    # Normalize base URL (strip trailing slash)
    $BaseUrl = $BaseUrl.TrimEnd('/')

    # Probe status endpoint
    try {
        $statusUrl = "$BaseUrl/api/configuration/get-status"
        $response = Invoke-WebRequest -Uri $statusUrl -UseBasicParsing -TimeoutSec 2 -ErrorAction Stop
        if ($response.StatusCode -eq 200) {
            $reachable = $true
            try {
                $statusData = $response.Content | ConvertFrom-Json
            }
            catch { }
        }
    }
    catch [System.Net.WebException] {
        $errorMsg = $_.Exception.Message
    }
    catch {
        $errorMsg = $_.Exception.Message
    }

    # If reachable, fetch extended configuration
    if ($reachable) {
        try {
            $configUrl = "$BaseUrl/api/configuration/get-current-configuration-extended"
            $configResponse = Invoke-WebRequest -Uri $configUrl -UseBasicParsing -TimeoutSec 2 -ErrorAction Stop
            if ($configResponse.StatusCode -eq 200) {
                try {
                    $configuration = $configResponse.Content | ConvertFrom-Json
                }
                catch {
                    $configuration = $null
                }
            }
        }
        catch {
            # Reachable but config endpoint failed; not critical
        }
    }

    $result = [ordered]@{
        reachable     = $reachable
        status        = $statusData
        configuration = $configuration
        error         = $errorMsg
    }

    $result | ConvertTo-Json -Depth 10 -Compress
}
catch {
    [ordered]@{
        reachable     = $false
        status        = $null
        configuration = $null
        error         = $_.Exception.Message
    } | ConvertTo-Json -Compress
}
