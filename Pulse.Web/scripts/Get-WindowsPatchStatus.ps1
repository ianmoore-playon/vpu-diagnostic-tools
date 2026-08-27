#Requires -Version 5.1
<#
.SYNOPSIS
    Windows patch-level report for a VPU where Windows Update is disabled.
.DESCRIPTION
    STANDALONE field script -- prints a human-readable report to the console
    (NOT a JSON collector; not wired into the Pulse app). Run it directly on
    a VPU, ideally from an elevated PowerShell prompt.

    Pixellot applies Windows patches selectively/offline, so the Windows
    Update UI and agent history look empty or years stale. That is expected
    and proves nothing. Offline installs (wusa/DISM) still go through the
    Component Based Servicing stack, which leaves durable evidence. This
    script reads that evidence:

      1. OS identity + full build number (CurrentBuild.UBR) -- the ground
         truth for cumulative patch level, regardless of install method.
      2. Windows Update service/policy state -- is WU disabled, and is a
         WSUS server configured (i.e. HOW does Pixellot deliver patches)?
      3. Installed hotfix inventory (Get-HotFix) with install dates.
      4. Servicing timeline from the Setup event log -- every CBS package
         install, with timestamp, even when the WU agent never ran.
      5. Pending-reboot flags (a patch may be installed but not active).
      6. Defender engine/signature versions (patched separately from the OS).

    Compare the full build number against Microsoft's release-history pages
    to date the last cumulative update:
      Windows 10: https://learn.microsoft.com/windows/release-health/release-information
      Windows 11: https://learn.microsoft.com/windows/release-health/windows11-release-information
.PARAMETER Full
    Also run "dism /online /get-packages" for the exhaustive CBS package
    list (slower, needs elevation).
.PARAMETER OutFile
    Optional path; the report is additionally written there as plain text.
.EXAMPLE
    .\Get-WindowsPatchStatus.ps1
.EXAMPLE
    .\Get-WindowsPatchStatus.ps1 -Full -OutFile C:\Pulse\patch-report.txt
#>
[CmdletBinding()]
param(
    [switch]$Full,
    [string]$OutFile
)

$ErrorActionPreference = 'Continue'
$report = New-Object System.Collections.Generic.List[string]

function Add-Line {
    param([string]$Text = '')
    $script:report.Add($Text)
    Write-Host $Text
}

function Add-Section {
    param([string]$Title)
    Add-Line
    Add-Line ('=' * 72)
    Add-Line "  $Title"
    Add-Line ('=' * 72)
}

function Add-Block {
    # Renders any object/table through Out-String so it lands in the report too.
    param($InputObject)
    ($InputObject | Out-String -Width 120).TrimEnd() -split "`r?`n" | ForEach-Object { Add-Line $_ }
}

Add-Line "Windows Patch Status Report"
Add-Line "Generated : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') on $env:COMPUTERNAME"
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
           ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
Add-Line "Elevated  : $isAdmin $(if (-not $isAdmin) { '(some sections may be incomplete; rerun as admin for full detail)' })"

# ---------------------------------------------------------------- 1. OS + build
Add-Section '1. OS IDENTITY & PATCH LEVEL (ground truth)'
$cv = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
$fullBuild = "$($cv.CurrentMajorVersionNumber).$($cv.CurrentMinorVersionNumber).$($cv.CurrentBuild).$($cv.UBR)"
$osInstall = if ($cv.InstallDate) {
    ([DateTime]'1970-01-01').AddSeconds($cv.InstallDate).ToLocalTime().ToString('yyyy-MM-dd')
} else { 'unknown' }
Add-Line "Product          : $($cv.ProductName) ($($cv.EditionID))"
Add-Line "Feature release  : $(if ($cv.DisplayVersion) { $cv.DisplayVersion } else { $cv.ReleaseId })"
Add-Line "Full build       : $fullBuild   <-- compare to Microsoft release history to date the last cumulative update"
Add-Line "OS installed     : $osInstall (image deployment date)"
Add-Line ""
Add-Line "The UBR (last segment, $($cv.UBR)) maps 1:1 to a specific monthly cumulative"
Add-Line "KB. Cumulative updates are cumulative: this one number IS the patch level,"
Add-Line "no matter how the update was delivered."

# ------------------------------------------- 2. WU service + policy (delivery path)
Add-Section '2. WINDOWS UPDATE SERVICE & POLICY (how patches arrive)'
$svc = Get-Service -Name wuauserv, UsoSvc, TrustedInstaller -ErrorAction SilentlyContinue |
    Select-Object Name, Status, StartType
Add-Block ($svc | Format-Table -AutoSize)

$wuPolicy = Get-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate' -ErrorAction SilentlyContinue
$auPolicy = Get-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU' -ErrorAction SilentlyContinue
if ($wuPolicy -or $auPolicy) {
    Add-Line 'Group-policy overrides found:'
    if ($wuPolicy.WUServer)      { Add-Line "  WSUS server        : $($wuPolicy.WUServer)   <-- Pixellot-managed update source" }
    if ($wuPolicy.TargetGroup)   { Add-Line "  WSUS target group  : $($wuPolicy.TargetGroup)" }
    if ($null -ne $auPolicy.NoAutoUpdate) { Add-Line "  NoAutoUpdate       : $($auPolicy.NoAutoUpdate) (1 = automatic updates disabled)" }
    if ($null -ne $auPolicy.UseWUServer)  { Add-Line "  UseWUServer        : $($auPolicy.UseWUServer) (1 = updates come from the WSUS server above)" }
    if ($null -ne $auPolicy.AUOptions)    { Add-Line "  AUOptions          : $($auPolicy.AUOptions)" }
} else {
    Add-Line 'No WindowsUpdate group-policy keys, so WU is not WSUS-redirected. Patches'
    Add-Line 'are most likely applied offline (wusa/DISM) by Pixellot tooling.'
}

foreach ($phase in 'Detect', 'Download', 'Install') {
    $k = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\Results\$phase" -ErrorAction SilentlyContinue
    if ($k.LastSuccessTime) { Add-Line "WU agent last successful ${phase}: $($k.LastSuccessTime) (UTC)" }
}

# ---------------------------------------------------------------- 3. Hotfix list
Add-Section '3. INSTALLED UPDATES (Get-HotFix / QFE)'
$hotfixes = Get-HotFix | Sort-Object InstalledOn -Descending
if ($hotfixes) {
    $latest = $hotfixes | Where-Object InstalledOn | Select-Object -First 1
    Add-Line "Total packages   : $($hotfixes.Count)"
    if ($latest) {
        $ageDays = [int]((Get-Date) - $latest.InstalledOn).TotalDays
        Add-Line "Most recent      : $($latest.HotFixID) installed $($latest.InstalledOn.ToString('yyyy-MM-dd')) ($ageDays days ago)"
    }
    Add-Block ($hotfixes | Select-Object HotFixID, Description, InstalledOn, InstalledBy |
        Format-Table -AutoSize)
} else {
    Add-Line 'Get-HotFix returned nothing (unusual; check the Setup event log below).'
}

# ---------------------------------------------- 4. Servicing timeline (event log)
Add-Section '4. SERVICING TIMELINE (Setup event log, which catches offline installs)'
try {
    $servicingEvents = Get-WinEvent -FilterHashtable @{
        LogName = 'Setup'; ProviderName = 'Microsoft-Windows-Servicing'; Id = 2
    } -MaxEvents 25 -ErrorAction Stop
    Add-Line 'Last 25 successful package installs (any delivery method):'
    $rows = foreach ($e in $servicingEvents) {
        $kb = if ($e.Message -match '(KB\d{6,7})') { $Matches[1] } else { '-' }
        $pkg = if ($e.Message -match 'Package (\S+?) was') { $Matches[1] } else { $e.Message.Substring(0, [Math]::Min(70, $e.Message.Length)) }
        [pscustomobject]@{ Installed = $e.TimeCreated.ToString('yyyy-MM-dd HH:mm'); KB = $kb; Package = $pkg }
    }
    Add-Block ($rows | Format-Table -AutoSize)
} catch {
    Add-Line "Could not read the Setup event log: $($_.Exception.Message)"
}

# Also surface any installs the WU agent itself performed (wusa uses it too).
try {
    $wuEvents = Get-WinEvent -FilterHashtable @{
        LogName = 'System'; ProviderName = 'Microsoft-Windows-WindowsUpdateClient'; Id = 19
    } -MaxEvents 10 -ErrorAction Stop
    Add-Line 'Last WU-agent-reported installs (System log, event 19):'
    Add-Block ($wuEvents | Select-Object @{n = 'Installed'; e = { $_.TimeCreated.ToString('yyyy-MM-dd HH:mm') } },
        @{n = 'Update'; e = { ($_.Message -split "`n")[0].Trim() } } | Format-Table -Wrap)
} catch {
    Add-Line 'No WU-agent install events in the System log (expected when patches are applied offline).'
}

# ---------------------------------------------------------------- 5. Pending reboot
Add-Section '5. PENDING REBOOT (installed but not yet active?)'
$pendingFlags = @(
    @{ Name = 'CBS RebootPending';         Path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending' }
    @{ Name = 'WU RebootRequired';         Path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired' }
)
$anyPending = $false
foreach ($f in $pendingFlags) {
    $set = Test-Path $f.Path
    if ($set) { $anyPending = $true }
    Add-Line ("{0,-22}: {1}" -f $f.Name, $(if ($set) { 'SET' } else { 'clear' }))
}
$pfro = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -ErrorAction SilentlyContinue).PendingFileRenameOperations
Add-Line ("{0,-22}: {1}" -f 'PendingFileRenames', $(if ($pfro) { $anyPending = $true; 'SET' } else { 'clear' }))
if ($anyPending) { Add-Line 'A servicing operation is waiting on a reboot, so the reported patch level is not fully applied yet.' }

# ---------------------------------------------------------------- 6. Defender
Add-Section '6. DEFENDER (updated separately from the OS)'
try {
    $mp = Get-MpComputerStatus -ErrorAction Stop
    Add-Line "Engine version       : $($mp.AMEngineVersion)"
    Add-Line "Platform version     : $($mp.AMProductVersion)"
    Add-Line "Signature version    : $($mp.AntivirusSignatureVersion)"
    Add-Line "Signatures updated   : $($mp.AntivirusSignatureLastUpdated) ($($mp.AntivirusSignatureAge) days old)"
} catch {
    # Get-MpComputerStatus throws an opaque "extrinsic Method could not be
    # executed" when the Defender service isn't running (common on VPU
    # images) -- report the service state instead of the CIM error.
    $defSvc = Get-Service WinDefend -ErrorAction SilentlyContinue
    if (-not $defSvc) {
        Add-Line 'Defender service (WinDefend) is not present on this image.'
    } elseif ($defSvc.Status -ne 'Running') {
        Add-Line "Defender service (WinDefend) is $($defSvc.Status) (StartType: $($defSvc.StartType)). Defender is not active on this image."
    } else {
        Add-Line "Defender status unavailable: $($_.Exception.Message)"
    }
}

# ---------------------------------------------------------------- 7. Full CBS dump
if ($Full) {
    Add-Section '7. FULL CBS PACKAGE LIST (dism /online /get-packages)'
    try {
        Add-Block (& dism.exe /online /get-packages /format:table 2>&1)
    } catch {
        Add-Line "DISM failed: $($_.Exception.Message) (requires elevation)"
    }
}

# ---------------------------------------------------------------- Summary
Add-Section 'SUMMARY'
Add-Line "Full build       : $fullBuild"
if ($latest) { Add-Line "Last QFE install : $($latest.HotFixID) on $($latest.InstalledOn.ToString('yyyy-MM-dd'))" }
Add-Line "Pending reboot   : $(if ($anyPending) { 'YES' } else { 'no' })"
Add-Line ""
Add-Line "To date the patch level: look up build $fullBuild on Microsoft's Windows"
Add-Line "release-history page; the matching row names the KB and its release month."

if ($OutFile) {
    $report -join [Environment]::NewLine | Set-Content -Path $OutFile -Encoding UTF8
    Write-Host "`nReport written to $OutFile"
}
