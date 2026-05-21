#Requires -Version 5.1
<#
.SYNOPSIS
    Lists installed software on the system.
.DESCRIPTION
    Reads from both 64-bit and 32-bit Uninstall registry paths.
    Filters out system components and empty entries. Outputs JSON to stdout.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

try {
    $regPaths = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )

    $allSoftware = @()

    foreach ($path in $regPaths) {
        try {
            $items = Get-ItemProperty -Path $path -ErrorAction SilentlyContinue |
                Where-Object {
                    $_.DisplayName -and
                    $_.DisplayName.Trim() -ne '' -and
                    $_.SystemComponent -ne 1
                }

            if ($items) {
                $allSoftware += $items | ForEach-Object {
                    [ordered]@{
                        displayName    = $_.DisplayName.Trim()
                        publisher      = if ($_.Publisher) { $_.Publisher.Trim() } else { $null }
                        displayVersion = $_.DisplayVersion
                        installDate    = $_.InstallDate
                    }
                }
            }
        }
        catch { }
    }

    # Deduplicate by display name (prefer the one with a version)
    $deduped = $allSoftware |
        Sort-Object displayName, @{ Expression = { if ($_.displayVersion) { 0 } else { 1 } } } |
        Group-Object displayName |
        ForEach-Object { $_.Group | Select-Object -First 1 }

    # Sort alphabetically
    $sorted = @($deduped | Sort-Object displayName)

    [ordered]@{
        count    = $sorted.Count
        software = $sorted
    } | ConvertTo-Json -Depth 4 -Compress
}
catch {
    [ordered]@{
        error   = $true
        message = $_.Exception.Message
        script  = 'Get-InstalledSoftware.ps1'
    } | ConvertTo-Json -Compress
}
