#Requires -Version 5.1
<#
.SYNOPSIS
    Discover JAI S1 cameras via the JAI SDK.
.DESCRIPTION
    S1 4-camera systems use JAI cameras, not Dynacolor — so Pulse's CGI
    probe can't see them. This enumerates them through the JAI factory
    (Jai_FactoryDotNet.dll) and returns serial numbers, IP addresses, and
    model names. Outputs JSON.

    Adapted from Canopy getConnectedS1Cameras.ps1. The Banyan localhost:8000
    HTTP POST is stripped per Pulse's run_ps convention (JSON to stdout).

    The JAI SDK ships with S1 systems at C:\Program Files\JAI\SDK\bin\. On a
    non-S1 VPU the DLL is absent — we report available=false rather than
    erroring, so the caller can simply skip the S1 section.
.OUTPUTS
    { available, count, cameras: [ { serialNumber, ip, model } ], ... }
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

# Canonical JAI SDK install path on S1 systems (+ x86 fallback).
$jaiDllCandidates = @(
    'C:\Program Files\JAI\SDK\bin\Jai_FactoryDotNet.dll',
    'C:\Program Files (x86)\JAI\SDK\bin\Jai_FactoryDotNet.dll'
)

try {
    $dll = $jaiDllCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
    if (-not $dll) {
        [ordered]@{
            available = $false
            reason    = 'JAI SDK not found (Jai_FactoryDotNet.dll absent). This VPU is not an S1 system.'
            count     = 0
            cameras   = @()
        } | ConvertTo-Json -Depth 5 -Compress
        return
    }

    Add-Type -Path $dll

    $factory = New-Object Jai_FactoryDotNET.CFactory
    # Discard the SDK's status returns (Open -> "Success", UpdateCameraList
    # -> bool, Close -> "Success"): anything left on the pipeline lands on
    # stdout ahead of our JSON and the app has to salvage it as noisy output.
    $null = $factory.Open()
    $driverType = [Jai_FactoryDotNET.CFactory+EDriverType]::Undefined
    $null = $factory.UpdateCameraList($driverType)
    Start-Sleep -Seconds 1

    # Only count entries with a real serial number; dedupe by serial.
    $realCams   = $factory.CameraList | Where-Object { $_.SerialNumber -and $_.SerialNumber.Trim() -ne "" }
    $uniqueCams = $realCams | Sort-Object SerialNumber | Select-Object -Unique SerialNumber, IPAddress, ModelName

    $cameras = @($uniqueCams | ForEach-Object {
        [ordered]@{
            serialNumber = "$($_.SerialNumber)".Trim()
            # IPAddress may be a UInt32 from the SDK; emit it as a string
            # either way. Validate the format on real S1 hardware.
            ip           = "$($_.IPAddress)".Trim()
            model        = "$($_.ModelName)".Trim()
        }
    })

    $null = $factory.Close()
    $factory.Dispose()

    [ordered]@{
        available = $true
        count     = $cameras.Count
        cameras   = $cameras
    } | ConvertTo-Json -Depth 5 -Compress
}
catch {
    [ordered]@{
        error   = $true
        message = $_.Exception.Message
        script  = 'Get-S1Cameras.ps1'
    } | ConvertTo-Json -Compress
}
