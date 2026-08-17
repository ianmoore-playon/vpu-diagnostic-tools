#Requires -Version 5.1
<#
.SYNOPSIS
    Returns Windows Time service peer + status information.
.DESCRIPTION
    Runs `w32tm /query /status` and `w32tm /query /peers` and parses the
    output into a structured JSON document. Surfaced on the Network tab's
    NTP section per Pixellot Troubleshooting Tips PDF #8.

    Returns:
        {
          status: { source, sourceIp, stratum, lastSync, leapIndicator,
                    rootDelay, rootDispersion, pollInterval },
          peers:  [{ name, state, stratum, mode, lastSyncTimestamp,
                     peerPollInterval, hostPollInterval, timeRemaining }, ...]
        }
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

function Invoke-W32tm {
    # Pass each w32tm token as a separate argument. A single string like
    # "/query /status" is handed to the native exe as ONE argument by
    # PowerShell (it doesn't re-split on spaces), which w32tm rejects -- so
    # the args must arrive pre-split and be splatted with @.
    param([string[]]$Arguments)
    # Run with a hard timeout so a broken NTP config doesn't hang the script.
    # The unary comma keeps the array intact as a single -ArgumentList item.
    $job = Start-Job -ScriptBlock {
        param($wargs)
        & w32tm @wargs 2>&1 | Out-String
    } -ArgumentList (, $Arguments)
    $done = Wait-Job -Job $job -Timeout 5
    $out = if ($done) { (Receive-Job -Job $job).Trim() } else { Stop-Job -Job $job; '' }
    Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
    return $out
}

function Get-Field {
    param([string]$Text, [string]$Label)
    # Match "Label: <value>" with the value running to end-of-line.
    $pattern = [regex]::Escape($Label) + ':\s+(?<v>.+?)\s*(?:\r?\n|$)'
    $m = [regex]::Match($Text, $pattern)
    if ($m.Success) { return $m.Groups['v'].Value.Trim() }
    return $null
}

function Get-Stratum {
    param([string]$Raw)
    # "Stratum: 3 (secondary reference - syncd by (S)NTP)" -> numeric 3
    if ($null -eq $Raw) { return $null }
    $m = [regex]::Match($Raw, '^\s*(\d+)')
    if ($m.Success) { return [int]$m.Groups[1].Value }
    return $null
}

try {
    # -- /query /status -------------------------------------------
    $statusRaw = Invoke-W32tm @('/query', '/status')

    # "Source: time.windows.com,0x9" -- strip the trailing ,0x.. config flag.
    $source        = Get-Field $statusRaw 'Source'
    if ($source) { $source = ($source -replace ',0x[0-9A-Fa-f]+\s*$', '').Trim() }
    $stratumRaw    = Get-Field $statusRaw 'Stratum'
    $stratum       = Get-Stratum $stratumRaw
    $lastSync      = Get-Field $statusRaw 'Last Successful Sync Time'
    $leap          = Get-Field $statusRaw 'Leap Indicator'
    $rootDelay     = Get-Field $statusRaw 'Root Delay'
    $rootDisp      = Get-Field $statusRaw 'Root Dispersion'
    $pollInterval  = Get-Field $statusRaw 'Poll Interval'

    # ReferenceId line is special: "ReferenceId: 0xD8EF2308 (source IP:  216.239.35.8)"
    $sourceIp = $null
    $refIdLine = Get-Field $statusRaw 'ReferenceId'
    if ($refIdLine) {
        $ipMatch = [regex]::Match($refIdLine, '(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})')
        if ($ipMatch.Success) { $sourceIp = $ipMatch.Groups[1].Value }
    }

    # "Last Successful Sync Time: unspecified" means the box never synced.
    if ($lastSync -and $lastSync -match '^(unspecified|n/?a)$') { $lastSync = $null }

    $status = [ordered]@{
        source         = $source
        sourceIp       = $sourceIp
        stratum        = $stratum
        stratumText    = $stratumRaw
        lastSync       = $lastSync
        leapIndicator  = $leap
        rootDelay      = $rootDelay
        rootDispersion = $rootDisp
        pollInterval   = $pollInterval
    }

    # -- /query /peers --------------------------------------------
    $peersRaw = Invoke-W32tm @('/query', '/peers')

    # Each peer block starts with "Peer: <name>". Split on that header but
    # keep the header line attached to its block via a lookahead split.
    $peers = @()
    # The first "#Peers:" line is metadata; ignore it.
    $blocks = [regex]::Split($peersRaw, '(?m)^Peer:\s*')
    foreach ($blk in $blocks) {
        $blk = $blk.Trim()
        if (-not $blk) { continue }
        # First block is the "#Peers: N" header -- skip if it starts with that.
        if ($blk -match '^\#Peers') { continue }

        $firstLine, $rest = $blk -split "`r?`n", 2
        $name = $firstLine.Trim().TrimEnd(',') -replace ',0x\d+$',''  # strip the ",0x1" flag suffix

        $peerStratumRaw    = Get-Field $blk 'Stratum'
        $peer = [ordered]@{
            name              = $name
            state             = Get-Field $blk 'State'
            timeRemaining     = Get-Field $blk 'Time Remaining'
            mode              = Get-Field $blk 'Mode'
            stratum           = Get-Stratum $peerStratumRaw
            stratumText       = $peerStratumRaw
            peerPollInterval  = Get-Field $blk 'PeerPoll Interval'
            hostPollInterval  = Get-Field $blk 'HostPoll Interval'
            lastSyncTimestamp = Get-Field $blk 'Last Successful Sync Time'
        }
        if ($peer.lastSyncTimestamp -and $peer.lastSyncTimestamp -match '^(unspecified|n/?a)$') {
            $peer.lastSyncTimestamp = $null
        }
        $peers += $peer
    }

    [ordered]@{
        status = $status
        peers  = @($peers)
    } | ConvertTo-Json -Depth 5 -Compress
}
catch {
    [ordered]@{
        error   = $true
        message = $_.Exception.Message
        script  = 'Get-NtpPeers.ps1'
    } | ConvertTo-Json -Compress
}
