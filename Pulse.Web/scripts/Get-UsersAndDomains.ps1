#Requires -Version 5.1
<#
.SYNOPSIS
    Reports domain/workgroup membership, local user accounts, and the
    currently-logged-in user.
.DESCRIPTION
    Adapted from Canopy/Leaf/userAndDomain.ps1 (which only reported the
    current user + domain). Expanded for the System Overview "Users &
    Domains" panel:
      - domain vs workgroup, domain role, computer name
      - local user accounts (enabled state, admin membership, last logon)
      - the interactive console user

    Resilient pattern (same as Get-AudioDevices.ps1): every branch is
    caught and the script ALWAYS emits one JSON object to stdout, so a
    cmdlet that's missing on an odd Windows build can't blank the panel.

    Local-account enumeration uses WMI (Win32_UserAccount LocalAccount=true)
    rather than Get-LocalUser for max compatibility across VPU images.
    Admin membership uses `net localgroup Administrators` -- reliable and
    fast on the US-English VPU images Pulse targets.
.OUTPUTS
    JSON to stdout.
#>
[CmdletBinding()]
param()

$result = $null
$diagnostics = [ordered]@{ usersError = $null; domainError = $null }

# -- Domain / workgroup ----------------------------------------
$domainBlock = [ordered]@{
    computerName = $env:COMPUTERNAME
    partOfDomain = $null
    domain       = $null
    workgroup    = $null
    role         = $null
    currentUser  = $null
}
try {
    $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop
    $domainBlock.partOfDomain = [bool]$cs.PartOfDomain
    # When domain-joined, Domain holds the AD domain; otherwise it holds the
    # workgroup name. Win32_ComputerSystem.Workgroup is only populated when
    # NOT domain-joined, so derive both cleanly.
    if ($cs.PartOfDomain) {
        $domainBlock.domain = $cs.Domain
    } else {
        $domainBlock.workgroup = if ($cs.Workgroup) { $cs.Workgroup } else { $cs.Domain }
    }
    $domainBlock.currentUser = $cs.UserName   # console interactive user; null if none
    $domainBlock.role = switch ([int]$cs.DomainRole) {
        0 { 'Standalone Workstation' }
        1 { 'Member Workstation' }
        2 { 'Standalone Server' }
        3 { 'Member Server' }
        4 { 'Backup Domain Controller' }
        5 { 'Primary Domain Controller' }
        default { 'Unknown' }
    }
} catch {
    $diagnostics.domainError = $_.Exception.Message
}

# -- Local Administrators membership (name set for the isAdmin flag) --
$adminNames = New-Object System.Collections.Generic.HashSet[string] ([System.StringComparer]::OrdinalIgnoreCase)
try {
    # net localgroup output: header lines, a row of dashes, member names one
    # per line, then "The command completed successfully." Grab the names
    # between the dashes line and the trailing blank/summary line.
    $raw = & net localgroup Administrators 2>$null
    if ($raw) {
        $started = $false
        foreach ($line in $raw) {
            if ($line -match '^-+$') { $started = $true; continue }
            if (-not $started) { continue }
            $t = $line.Trim()
            if ($t -eq '' -or $t -match 'command completed') { continue }
            # Members may be "DOMAIN\user" or "user" -- store the leaf name too.
            [void]$adminNames.Add($t)
            if ($t -match '\\([^\\]+)$') { [void]$adminNames.Add($Matches[1]) }
        }
    }
} catch {}

# -- Local user accounts ---------------------------------------
$users = @()
try {
    $accts = Get-CimInstance Win32_UserAccount -Filter "LocalAccount=true" -ErrorAction Stop
    foreach ($u in $accts) {
        $isAdmin = $adminNames.Contains($u.Name) -or
                   $adminNames.Contains("$($u.Domain)\$($u.Name)")
        $users += [ordered]@{
            name     = $u.Name
            fullName = if ($u.FullName) { $u.FullName } else { $null }
            enabled  = (-not $u.Disabled)
            isAdmin  = [bool]$isAdmin
            lockedOut = [bool]$u.Lockout
            # SID tail (RID) helps identify built-ins: 500=Administrator, 501=Guest
            rid      = if ($u.SID -match '-(\d+)$') { [int]$Matches[1] } else { $null }
        }
    }
    # Sort: admins first, then enabled, then name -- most-relevant on top.
    $users = $users | Sort-Object @{e={-[int]$_.isAdmin}}, @{e={-[int]$_.enabled}}, name
} catch {
    $diagnostics.usersError = $_.Exception.Message
}

$result = [ordered]@{
    domain      = $domainBlock
    users       = @($users)
    userCount   = @($users).Count
    adminCount  = @($users | Where-Object { $_.isAdmin }).Count
    diagnostics = $diagnostics
}

$result | ConvertTo-Json -Depth 5 -Compress
