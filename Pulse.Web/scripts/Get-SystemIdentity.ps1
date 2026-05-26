#Requires -Version 5.1
<#
.SYNOPSIS
    Collects system identity information for VPU diagnostics.
.DESCRIPTION
    Gathers computer system, BIOS, OS, timezone, and Pixellot-specific
    registry/file data. Outputs a single JSON object to stdout.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

try {
    # Batch CIM queries
    $cs   = Get-CimInstance Win32_ComputerSystem
    $bios = Get-CimInstance Win32_BIOS
    $enc  = Get-CimInstance Win32_SystemEnclosure
    $os   = Get-CimInstance Win32_OperatingSystem
    $tz   = Get-CimInstance Win32_TimeZone

    # Calculate uptime
    $lastBoot = $os.LastBootUpTime
    $uptime   = (Get-Date) - $lastBoot
    $uptimeStr = '{0}d {1}h {2}m' -f [int]$uptime.TotalDays, $uptime.Hours, $uptime.Minutes

    # Pixellot registry
    $pixReg = $null
    $pixVersion = $null
    $pixImageVersion = $null
    $hasPixellotRegistry = $false
    try {
        $regPath = 'HKLM:\SOFTWARE\Pixellot'
        if (Test-Path $regPath) {
            $hasPixellotRegistry = $true
            $pixVersion = (Get-ItemProperty -Path $regPath -Name 'Version' -ErrorAction SilentlyContinue).Version
            $pixImageVersion = (Get-ItemProperty -Path $regPath -Name 'ImageVersion' -ErrorAction SilentlyContinue).ImageVersion
        }
    }
    catch { }

    # VPU friendly name from the latest agent_vpu2 log
    $vpuName = $null
    try {
        $logDir = 'C:\Pixellot\Data\Log'
        if (Test-Path $logDir) {
            $latestLog = Get-ChildItem -Path $logDir -Filter 'agent_vpu2_*.log' -ErrorAction SilentlyContinue |
                Sort-Object Name -Descending | Select-Object -First 1
            if ($latestLog) {
                # Search entire file for the last BROADCAST_NAME entry
                $hit = Select-String -Path $latestLog.FullName -Pattern 'BROADCAST_NAME\s+result:\s*(.+)$' -ErrorAction SilentlyContinue |
                    Select-Object -Last 1
                if ($hit) {
                    $vpuName = $hit.Matches[0].Groups[1].Value.Trim()
                }
            }
        }
    }
    catch { }

    # Detect non-VPU host
    $hasPixellotLogs = Test-Path 'D:\Pixellot\PixellotAgent\logs\*'
    $hasCPixellot    = Test-Path 'C:\Pixellot'
    $isNonVpuHost    = (-not $hasPixellotRegistry) -and (-not $hasPixellotLogs) -and (-not $hasCPixellot)

    $result = [ordered]@{
        computerSystem = [ordered]@{
            name          = $cs.Name
            manufacturer  = $cs.Manufacturer
            model         = $cs.Model
            domain        = $cs.Domain
            partOfDomain  = $cs.PartOfDomain
        }
        bios = [ordered]@{
            smbiosVersion = $bios.SMBIOSBIOSVersion
            releaseDate   = if ($bios.ReleaseDate) { $bios.ReleaseDate.ToString('o') } else { $null }
            serialNumber  = $bios.SerialNumber
        }
        assetTag = ($enc | Select-Object -First 1).SMBIOSAssetTag
        operatingSystem = [ordered]@{
            caption              = $os.Caption
            version              = $os.Version
            buildNumber          = $os.BuildNumber
            osArchitecture       = $os.OSArchitecture
            installDate          = if ($os.InstallDate) { $os.InstallDate.ToString('o') } else { $null }
            lastBootUpTime       = if ($lastBoot) { $lastBoot.ToString('o') } else { $null }
            totalVisibleMemoryKB = $os.TotalVisibleMemorySize
            freePhysicalMemoryKB = $os.FreePhysicalMemory
        }
        timezone = $tz.Caption
        uptime = [ordered]@{
            totalSeconds = [math]::Round($uptime.TotalSeconds, 0)
            formatted    = $uptimeStr
        }
        pixellot = [ordered]@{
            version      = $pixVersion
            imageVersion = $pixImageVersion
            vpuName      = $vpuName
        }
        isNonVpuHost = $isNonVpuHost
    }

    $result | ConvertTo-Json -Depth 5 -Compress
}
catch {
    [ordered]@{
        error   = $true
        message = $_.Exception.Message
        script  = 'Get-SystemIdentity.ps1'
    } | ConvertTo-Json -Compress
}
