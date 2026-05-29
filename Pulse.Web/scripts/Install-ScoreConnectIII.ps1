#Requires -Version 5.1
<#
.SYNOPSIS
    Kicks off a ScoreConnect III installation as an elevated background task.
.DESCRIPTION
    Adapted from Logan's Install-SC3-1.0.bat (PlayOn internal). Instead of
    spawning an interactive PowerShell window, this:

    1. Writes initial status to C:\ProgramData\Pulse\sc3-install-status.json
    2. Spawns a hidden elevated PowerShell process to run the actual install
    3. Returns immediately so the Pulse UI can poll status

    The elevated process pipes Enter to the Canopy install script via stdin
    to bypass its "Press Enter to continue" prompts — making the install
    fully non-interactive.

    Frontend polls Get-Sc3InstallStatus.ps1 (or the equivalent API endpoint)
    every 1-2 seconds to drive a progress bar.
.PARAMETER ScriptUrl
    Override the Canopy install script URL (for testing).
#>
[CmdletBinding()]
param(
    [string]$ScriptUrl = 'https://canopy-public-packages.nfhsnetwork.com/SC3/Current/installScript3_current.ps1'
)

$ErrorActionPreference = 'Stop'

# ── Paths ────────────────────────────────────────────────────────────
$statusDir  = 'C:\ProgramData\Pulse'
$statusPath = Join-Path $statusDir 'sc3-install-status.json'
$logPath    = Join-Path $statusDir 'sc3-install.log'
$tempDir    = 'C:\scoreconnecttemp'

# ── Status writer helper (also exists in the elevated child) ─────────
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
    $payload = [ordered]@{
        stage     = $Stage
        percent   = $Percent
        message   = $Message
        error     = $ErrorMsg
        updatedAt = (Get-Date).ToString('o')
    }
    $payload | ConvertTo-Json -Compress | Set-Content -Path $statusPath -Encoding UTF8
}

try {
    # ── Initial status ───────────────────────────────────────────────
    Write-Status -Stage 'starting' -Percent 2 -Message 'Requesting elevation…'

    # ── Build the elevated script that does the actual work ──────────
    # This is written to a temp file and executed via Start-Process -Verb RunAs.
    # Using a file (vs -Command inline) makes the args clean and the elevated
    # session won't choke on quoting.
    if (-not (Test-Path $tempDir)) {
        New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
    }
    $elevatedScript = Join-Path $tempDir 'pulse-sc3-elevated.ps1'

    # The elevated script — runs as Administrator after the UAC prompt.
    # It updates the status file at each stage and pipes Enter via stdin
    # to the Canopy script so any "Press Enter to continue" prompts are
    # auto-acknowledged.
    $elevatedBody = @"
`$ErrorActionPreference = 'Continue'
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

# Reset log
'' | Set-Content -Path `$logPath -Encoding UTF8

try {
    Write-Status -Stage 'downloading' -Percent 10 -Message 'Downloading SC III installer from Canopy…'
    Write-Log "Downloading from `$scriptUrl"

    # Download Canopy install script
    `$curlPath = (Get-Command curl.exe -ErrorAction SilentlyContinue).Source
    if (`$curlPath) {
        `$prevEAP = `$ErrorActionPreference
        `$ErrorActionPreference = 'Continue'
        & `$curlPath -sSL --fail -o `$scriptFile `$scriptUrl --connect-timeout 15 --max-time 60 2>`$null
        `$exit = `$LASTEXITCODE
        `$ErrorActionPreference = `$prevEAP
        if (`$exit -ne 0) { throw "curl failed (exit `$exit) — verify *.nfhsnetwork.com is reachable" }
    } else {
        Invoke-WebRequest -Uri `$scriptUrl -OutFile `$scriptFile -UseBasicParsing -TimeoutSec 60 -ErrorAction Stop
    }
    Write-Log "Downloaded `$((Get-Item `$scriptFile).Length) bytes"

    Write-Status -Stage 'installing' -Percent 30 -Message 'Running installer (this may take 2–3 minutes)…'
    Write-Log "Launching install script"

    # Run the Canopy install script with stdin redirection to auto-acknowledge
    # any 'Press Enter to continue' prompts. We pipe 20 newlines via Echo.
    `$psi = New-Object System.Diagnostics.ProcessStartInfo
    `$psi.FileName  = 'powershell.exe'
    `$psi.Arguments = "-ExecutionPolicy Bypass -NoProfile -File `"`$scriptFile`""
    `$psi.UseShellExecute = `$false
    `$psi.RedirectStandardInput  = `$true
    `$psi.RedirectStandardOutput = `$true
    `$psi.RedirectStandardError  = `$true
    `$psi.CreateNoWindow = `$true
    `$psi.WorkingDirectory = `$tempDir

    `$proc = [System.Diagnostics.Process]::Start(`$psi)

    # Stream stdin: push Enter many times so any prompt is auto-satisfied.
    # Also async-read stdout/stderr so the pipe doesn't fill up.
    `$stdoutBuilder = New-Object System.Text.StringBuilder
    `$stderrBuilder = New-Object System.Text.StringBuilder
    `$stdoutAction = { if (`$EventArgs.Data) { `$Event.MessageData.AppendLine(`$EventArgs.Data) | Out-Null } }
    `$stderrAction = { if (`$EventArgs.Data) { `$Event.MessageData.AppendLine(`$EventArgs.Data) | Out-Null } }
    Register-ObjectEvent -InputObject `$proc -EventName OutputDataReceived -Action `$stdoutAction -MessageData `$stdoutBuilder | Out-Null
    Register-ObjectEvent -InputObject `$proc -EventName ErrorDataReceived  -Action `$stderrAction -MessageData `$stderrBuilder | Out-Null
    `$proc.BeginOutputReadLine()
    `$proc.BeginErrorReadLine()

    # Push a few Enters with a small delay so the script reads them as
    # separate keypresses at separate prompts.
    1..30 | ForEach-Object {
        `$proc.StandardInput.WriteLine('')
        Start-Sleep -Milliseconds 100
    }
    `$proc.StandardInput.Close()

    # Update progress periodically while the install runs.
    `$installStart = Get-Date
    `$stages = @(
        @{ at = 30;  pct = 40; msg = 'Installing SC III components…' },
        @{ at = 60;  pct = 55; msg = 'Configuring services…' },
        @{ at = 90;  pct = 70; msg = 'Finalising installation…' },
        @{ at = 120; pct = 85; msg = 'Starting ScoreConnect III service…' },
        @{ at = 180; pct = 92; msg = 'Almost done…' }
    )

    while (-not `$proc.HasExited) {
        `$elapsed = ((Get-Date) - `$installStart).TotalSeconds
        `$stage = `$stages | Where-Object { `$_.at -le `$elapsed } | Select-Object -Last 1
        if (`$stage) {
            Write-Status -Stage 'installing' -Percent `$stage.pct -Message `$stage.msg
        }
        if (`$elapsed -gt 600) {
            Write-Log "Install timeout after 10 minutes — killing process"
            try { `$proc.Kill() } catch {}
            throw "Install exceeded 10 minute timeout"
        }
        Start-Sleep -Seconds 3
    }

    `$exitCode = `$proc.ExitCode
    Write-Log "Install process exited with code `$exitCode"
    Write-Log "STDOUT:"; Write-Log `$stdoutBuilder.ToString()
    Write-Log "STDERR:"; Write-Log `$stderrBuilder.ToString()

    if (`$exitCode -ne 0) {
        throw "Installer exited with code `$exitCode. See `$logPath for details."
    }

    # ── Verify SC III is now reachable ───────────────────────────────
    Write-Status -Stage 'verifying' -Percent 95 -Message 'Verifying ScoreConnect III is running…'
    `$ok = `$false
    `$verifyStart = Get-Date
    while (((Get-Date) - `$verifyStart).TotalSeconds -lt 30) {
        try {
            `$r = Invoke-WebRequest -Uri 'http://localhost:5000/api/configuration/get-status' -UseBasicParsing -TimeoutSec 3 -ErrorAction Stop
            if (`$r.StatusCode -eq 200) { `$ok = `$true; break }
        } catch {}
        Start-Sleep -Seconds 2
    }

    if (`$ok) {
        Write-Status -Stage 'complete' -Percent 100 -Message 'ScoreConnect III installed and running.'
        Write-Log "SC III reachable — install complete"
    } else {
        Write-Status -Stage 'complete' -Percent 100 -Message 'Install complete. SC III may take a moment to start.'
        Write-Log "Install complete but SC III not yet responding"
    }

    # Cleanup
    if (Test-Path `$tempDir) {
        try { Remove-Item -Path `$tempDir -Recurse -Force -ErrorAction SilentlyContinue } catch {}
    }
}
catch {
    `$err = `$_.Exception.Message
    Write-Log "FAILED: `$err"
    Write-Status -Stage 'failed' -Percent 0 -Message 'Installation failed' -ErrorMsg `$err
}
"@

    Set-Content -Path $elevatedScript -Value $elevatedBody -Encoding UTF8

    # ── Spawn elevated, hidden background process ────────────────────
    # -Verb RunAs triggers UAC. -WindowStyle Hidden hides the console.
    # We don't -Wait — return immediately so Pulse can poll status.
    try {
        Start-Process -FilePath 'powershell.exe' `
            -ArgumentList "-ExecutionPolicy Bypass -NoProfile -WindowStyle Hidden -File `"$elevatedScript`"" `
            -WindowStyle Hidden `
            -Verb RunAs `
            -ErrorAction Stop | Out-Null
    }
    catch {
        # User declined UAC, or elevation failed
        Write-Status -Stage 'failed' -Percent 0 -Message 'Elevation declined or unavailable' -ErrorMsg $_.Exception.Message
        throw "Could not launch elevated install: $($_.Exception.Message)"
    }

    Write-Status -Stage 'starting' -Percent 5 -Message 'Installer launched. Working in background…'

    # ── Return success — frontend takes over with polling ────────────
    @{
        ok        = $true
        message   = 'Install started. Poll /api/scoreconnect/install-sc3/status for progress.'
        statusUrl = '/api/scoreconnect/install-sc3/status'
    } | ConvertTo-Json -Depth 5
}
catch {
    Write-Status -Stage 'failed' -Percent 0 -Message 'Failed to launch installer' -ErrorMsg $_.Exception.Message
    @{
        ok    = $false
        error = $_.Exception.Message
    } | ConvertTo-Json -Depth 5
}
