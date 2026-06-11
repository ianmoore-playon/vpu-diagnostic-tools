#Requires -Version 5.1
<#
.SYNOPSIS
    Kicks off a ScoreConnect III installation in an elevated, visible console.
.DESCRIPTION
    Adapted from Logan's Install-SC3-1.0.bat (PlayOn internal).

    Pulse cannot drive the Canopy installer headlessly: its "Press Enter to
    continue" prompt reads from the console (CONIN$), which a redirected stdin
    pipe does NOT satisfy. An earlier hidden / CreateNoWindow design piped
    newlines into that prompt and hung forever at the parent's optimistic 5%.
    So this version instead:

      1. Writes initial status to C:\ProgramData\Pulse\sc3-install-status.json
      2. Spawns an ELEVATED PowerShell child (the UAC prompt shows so the tech
         can consent). The child downloads the Canopy script and runs it in a
         VISIBLE window so the tech can answer the installer's prompts.
      3. Returns immediately so the Pulse UI can poll status.

    Status is driven by REAL events (download done, installer window open,
    installer window closed, SC III reachable on :5000) - never a fabricated
    timer. The child heartbeats the status file every few seconds while the
    installer window is open so a legitimately long install is not mistaken
    for a stall.

    ASCII ONLY. Windows PowerShell 5.1 parses a BOM-less .ps1 using the system
    ANSI code page (CP-1252 on US VPUs), which corrupts non-ASCII glyphs (the
    ellipsis, em/en dashes) at parse time - that is the "background?" mojibake.
    Keep every string literal and comment to plain ASCII.
.PARAMETER ScriptUrl
    Override the Canopy install script URL (for testing).
#>
[CmdletBinding()]
param(
    [string]$ScriptUrl = 'https://canopy-public-packages.nfhsnetwork.com/SC3/Current/installScript3_current.ps1'
)

$ErrorActionPreference = 'Stop'

# Paths
$statusDir  = 'C:\ProgramData\Pulse'
$statusPath = Join-Path $statusDir 'sc3-install-status.json'
$logPath    = Join-Path $statusDir 'sc3-install.log'
$tempDir    = 'C:\scoreconnecttemp'

# Status writer (a mirror of this also runs inside the elevated child).
function Write-Status {
    param(
        [string]$Stage,
        [int]$Percent,
        [string]$Message,
        [string]$ErrorMsg = $null
    )
    if (-not (Test-Path $statusDir)) {
        New-Item -ItemType Directory -Path $statusDir -Force | Out-Null
    }
    [ordered]@{
        stage     = $Stage
        percent   = $Percent
        message   = $Message
        error     = $ErrorMsg
        updatedAt = (Get-Date).ToString('o')
    } | ConvertTo-Json -Compress | Set-Content -Path $statusPath -Encoding UTF8
}

try {
    # Initial status - the bar sits here until the tech consents to UAC.
    Write-Status -Stage 'starting' -Percent 5 -Message 'Approve the Windows administrator prompt to begin installing ScoreConnect III.'

    if (-not (Test-Path $tempDir)) {
        New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
    }
    $elevatedScript = Join-Path $tempDir 'pulse-sc3-elevated.ps1'

    # The elevated child body. It runs (hidden) as Administrator after the UAC
    # prompt, then launches the Canopy installer in a VISIBLE window the tech
    # interacts with. In the here-string, `$ defers a variable to the child;
    # $statusDir / $statusPath / $logPath / $tempDir / $ScriptUrl interpolate
    # now, from this parent. (Confirmed correct - do not "fix" the escaping.)
    $elevatedBody = @"
`$ErrorActionPreference = 'Stop'
`$statusDir  = '$statusDir'
`$statusPath = '$statusPath'
`$logPath    = '$logPath'
`$tempDir    = '$tempDir'
`$scriptUrl  = '$ScriptUrl'
`$scriptFile = Join-Path `$tempDir 'installScript3_current.ps1'

function Write-Status {
    param([string]`$Stage, [int]`$Percent, [string]`$Message, [string]`$ErrorMsg = `$null)
    if (-not (Test-Path `$statusDir)) { New-Item -ItemType Directory -Path `$statusDir -Force | Out-Null }
    [ordered]@{
        stage     = `$Stage
        percent   = `$Percent
        message   = `$Message
        error     = `$ErrorMsg
        updatedAt = (Get-Date).ToString('o')
    } | ConvertTo-Json -Compress | Set-Content -Path `$statusPath -Encoding UTF8
}

function Write-Log {
    param([string]`$Line)
    "`$(Get-Date -Format 'HH:mm:ss')  `$Line" | Add-Content -Path `$logPath -Encoding UTF8
}

try {
    # Reset the log immediately so any later failure is never silent.
    '' | Set-Content -Path `$logPath -Encoding UTF8

    Write-Status -Stage 'downloading' -Percent 20 -Message 'Downloading the ScoreConnect III installer from Canopy.'
    Write-Log "Downloading from `$scriptUrl"

    `$curlPath = (Get-Command curl.exe -ErrorAction SilentlyContinue).Source
    if (`$curlPath) {
        & `$curlPath -sSL --fail -o `$scriptFile `$scriptUrl --connect-timeout 15 --max-time 60 2>`$null
        if (`$LASTEXITCODE -ne 0) { throw "Download failed (curl exit `$LASTEXITCODE). Verify *.nfhsnetwork.com is reachable from this VPU." }
    } else {
        Invoke-WebRequest -Uri `$scriptUrl -OutFile `$scriptFile -UseBasicParsing -TimeoutSec 60
    }
    if (-not (Test-Path `$scriptFile)) { throw 'Installer script did not download.' }
    Write-Log "Downloaded `$((Get-Item `$scriptFile).Length) bytes"

    Write-Status -Stage 'installing' -Percent 50 -Message 'Follow the prompts in the ScoreConnect III installer window. It will finish automatically.'
    Write-Log 'Launching Canopy installer in a visible window'

    # Launch the Canopy installer in a VISIBLE window. It inherits this child's
    # elevation (no RunAs needed). The tech answers the 'Press Enter' prompt in
    # that window - we deliberately do NOT redirect/pipe stdin, because a
    # console pause reads CONIN$ and ignores a redirected pipe.
    `$p = Start-Process powershell.exe -ArgumentList '-ExecutionPolicy','Bypass','-NoProfile','-File',`$scriptFile -WorkingDirectory `$tempDir -PassThru
    if (-not `$p) { throw 'Could not launch the installer window.' }

    # Heartbeat the status file while the installer window is open so a long
    # install (or a tech reading the prompt) is never mistaken for a stall.
    `$installStart = Get-Date
    while (-not `$p.HasExited) {
        if (((Get-Date) - `$installStart).TotalSeconds -gt 900) {
            Write-Log 'Installer exceeded 15 minutes - abandoning wait'
            throw 'The installer did not finish within 15 minutes. Complete it in the installer window, then click Refresh.'
        }
        Write-Status -Stage 'installing' -Percent 50 -Message 'Follow the prompts in the ScoreConnect III installer window. It will finish automatically.'
        Start-Sleep -Seconds 5
    }
    Write-Log "Installer window closed (exit `$(`$p.ExitCode))"

    # Verify against the REAL signal: SC III answering on :5000.
    Write-Status -Stage 'verifying' -Percent 85 -Message 'Verifying ScoreConnect III is running.'
    `$ok = `$false
    `$verifyStart = Get-Date
    while (((Get-Date) - `$verifyStart).TotalSeconds -lt 60) {
        try {
            `$r = Invoke-WebRequest -Uri 'http://localhost:5000/api/configuration/get-status' -UseBasicParsing -TimeoutSec 3
            if (`$r.StatusCode -eq 200) { `$ok = `$true; break }
        } catch {}
        Start-Sleep -Seconds 2
    }

    if (`$ok) {
        Write-Status -Stage 'complete' -Percent 100 -Message 'ScoreConnect III is installed and running.'
        Write-Log 'SC III reachable on :5000 - install complete'
    } else {
        Write-Status -Stage 'complete' -Percent 100 -Message 'Installer finished. ScoreConnect III may need a moment or a reboot to start.'
        Write-Log 'Install finished but SC III not responding on :5000 yet'
    }

    try { Remove-Item -Path `$scriptFile -Force -ErrorAction SilentlyContinue } catch {}
}
catch {
    `$err = `$_.Exception.Message
    Write-Log "FAILED: `$err"
    Write-Status -Stage 'failed' -Percent 0 -Message 'Installation failed.' -ErrorMsg `$err
}
"@

    Set-Content -Path $elevatedScript -Value $elevatedBody -Encoding UTF8

    # Spawn the elevated child. -Verb RunAs triggers the UAC prompt the tech
    # approves. The child runs hidden but launches the Canopy installer in a
    # visible window. -PassThru lets us confirm it actually launched, so we
    # never write an optimistic "running" status for a child that never ran.
    $child = $null
    try {
        $child = Start-Process -FilePath 'powershell.exe' `
            -ArgumentList "-ExecutionPolicy Bypass -NoProfile -WindowStyle Hidden -File `"$elevatedScript`"" `
            -WindowStyle Hidden `
            -Verb RunAs `
            -PassThru `
            -ErrorAction Stop
    }
    catch {
        Write-Status -Stage 'failed' -Percent 0 -Message 'Administrator permission was declined. Click Retry and approve the Windows prompt.' -ErrorMsg $_.Exception.Message
        @{ ok = $false; error = $_.Exception.Message } | ConvertTo-Json -Depth 5
        return
    }

    if (-not $child) {
        Write-Status -Stage 'failed' -Percent 0 -Message 'Could not launch the elevated installer.' -ErrorMsg 'Start-Process returned no process handle.'
        @{ ok = $false; error = 'Start-Process returned no process handle.' } | ConvertTo-Json -Depth 5
        return
    }

    # The child is live and now owns the status file. Do NOT overwrite it here -
    # the previous design's unconditional 5% write is exactly what froze the bar.
    @{
        ok        = $true
        message   = 'Install started. Poll /api/scoreconnect/install-sc3/status for progress.'
        statusUrl = '/api/scoreconnect/install-sc3/status'
    } | ConvertTo-Json -Depth 5
}
catch {
    Write-Status -Stage 'failed' -Percent 0 -Message 'Failed to launch the installer.' -ErrorMsg $_.Exception.Message
    @{
        ok    = $false
        error = $_.Exception.Message
    } | ConvertTo-Json -Depth 5
}
