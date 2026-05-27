#Requires -Version 5.1
<#
.SYNOPSIS
    Reads system temperature with multi-source fallback.
.DESCRIPTION
    Tries WMI thermal zone, then performance counters, then returns null.
    Outputs JSON to stdout.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

try {
    $celsius = $null
    $source  = 'unavailable'

    # Try 1: MSAcpi_ThermalZoneTemperature (tenths of Kelvin)
    try {
        $thermal = Get-CimInstance -Namespace root\WMI -ClassName MSAcpi_ThermalZoneTemperature -ErrorAction Stop
        if ($thermal) {
            $maxTemp = ($thermal | Measure-Object -Property CurrentTemperature -Maximum).Maximum
            if ($maxTemp -and $maxTemp -gt 0) {
                $celsius = [math]::Round(($maxTemp / 10) - 273.15, 1)
                $source = 'MSAcpi_ThermalZoneTemperature'
            }
        }
    }
    catch { }

    # Try 2: Win32_PerfFormattedData_Counters_ThermalZoneInformation (Kelvin)
    if ($null -eq $celsius) {
        try {
            $perfThermal = Get-CimInstance -ClassName Win32_PerfFormattedData_Counters_ThermalZoneInformation -ErrorAction Stop
            if ($perfThermal) {
                $maxTemp = ($perfThermal | Measure-Object -Property Temperature -Maximum).Maximum
                if ($null -ne $maxTemp) {
                    $converted = [math]::Round([double]$maxTemp - 273.15, 1)
                    if ($converted -gt 0 -and $converted -lt 110) {
                        $celsius = $converted
                        $source = 'Win32_PerfFormattedData_Counters_ThermalZoneInformation'
                    }
                }
            }
        }
        catch { }
    }

    [ordered]@{
        celsius = $celsius
        source  = $source
    } | ConvertTo-Json -Depth 2 -Compress
}
catch {
    [ordered]@{
        error   = $true
        message = $_.Exception.Message
        script  = 'Get-Temperature.ps1'
    } | ConvertTo-Json -Compress
}
