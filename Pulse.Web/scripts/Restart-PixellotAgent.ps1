#Requires -Version 5.1
<#
.SYNOPSIS
    Runs c:\pixellot\bin\keepagentup.exe to restart the Pixellot Agent and
    Coordinator services.
.DESCRIPTION
    Per Pixellot Troubleshooting Tips PDF #13, keepagentup.exe is the
    documented "fast remedy before escalating" when agent or coordinator
    is down. It re-launches both services and clears the typical hung-state.

    On most VPUs a resident keepagentup.exe watchdog is already running; a
    second invocation detects it, prints 'KeekAgentUp Exit as another
    "KeekAgentUp" process is running' (Pixellot's typo) and exits 0 without
    restarting anything. Exit code 0 therefore does NOT mean the agent was
    restarted - we detect that marker and report it as watchdogResident so
    the UI can say so honestly.

    Outputs JSON to stdout with success/failure and the executable's
    stdout/stderr captured.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$keepAgentPath = 'C:\pixellot\bin\keepagentup.exe'

# Agent/coordinator may be installed as Windows services, or run as bare
# processes under the keepagentup watchdog (common on fleet VPUs, where no
# service exists at all). Check both so status doesn't read 'NotFound' on a
# perfectly healthy box.
function Get-PixellotComponentState {
    param([string]$Name)
    $svc = Get-Service -Name $Name -ErrorAction SilentlyContinue
    if ($svc) {
        return @{ status = "$($svc.Status) (service)"; pid = $null }
    }
    $proc = @(Get-Process -Name $Name -ErrorAction SilentlyContinue)
    if ($proc.Count -gt 0) {
        return @{ status = "Running (process, PID $($proc[0].Id))"; pid = $proc[0].Id }
    }
    return @{ status = 'Not running (no service or process)'; pid = $null }
}

try {
    if (-not (Test-Path -LiteralPath $keepAgentPath)) {
        [ordered]@{
            success = $false
            message = "keepagentup.exe not found at $keepAgentPath. Verify Pixellot is installed."
            path    = $keepAgentPath
        } | ConvertTo-Json -Compress
        return
    }

    $agentBefore = Get-PixellotComponentState -Name 'agent'

    # Run in a separate process so we can capture stdout/stderr and exit code.
    $tmpOut = [System.IO.Path]::GetTempFileName()
    $tmpErr = [System.IO.Path]::GetTempFileName()
    try {
        $proc = Start-Process -FilePath $keepAgentPath `
            -NoNewWindow `
            -PassThru `
            -RedirectStandardOutput $tmpOut `
            -RedirectStandardError $tmpErr `
            -Wait

        # Keep the stdout/stderr passthrough as-is: Pixellot's logger throws a
        # cosmetic AccessViolationException on exit that lands in stderr and
        # must not be mistaken for the restart failing.
        $stdoutText = (Get-Content -LiteralPath $tmpOut -Raw -ErrorAction SilentlyContinue) -as [string]
        $stderrText = (Get-Content -LiteralPath $tmpErr -Raw -ErrorAction SilentlyContinue) -as [string]

        # keepagentup exits 0 immediately when the resident watchdog instance
        # is already running - nothing was restarted in that case.
        $watchdogResident = ($stdoutText -match '(?i)exit\s+as\s+another\s+.*process\s+is\s+running')

        $agentAfter = Get-PixellotComponentState -Name 'agent'
        $coordAfter = Get-PixellotComponentState -Name 'coordinator'

        $succeeded = ($proc.ExitCode -eq 0) -and (-not $watchdogResident)
        $message = if ($watchdogResident) {
            'The keepagentup watchdog is already resident on this VPU, so this run exited without restarting anything. The agent was NOT restarted.'
        } elseif ($proc.ExitCode -eq 0) {
            'keepagentup.exe completed successfully'
        } else {
            "keepagentup.exe exited with code $($proc.ExitCode)"
        }

        [ordered]@{
            success           = $succeeded
            watchdogResident  = $watchdogResident
            exitCode          = $proc.ExitCode
            path              = $keepAgentPath
            stdout            = if ($stdoutText) { $stdoutText.Trim() } else { '' }
            stderr            = if ($stderrText) { $stderrText.Trim() } else { '' }
            agentStatus       = $agentAfter.status
            coordinatorStatus = $coordAfter.status
            agentPidBefore    = $agentBefore.pid
            agentPidAfter     = $agentAfter.pid
            message           = $message
        } | ConvertTo-Json -Compress
    }
    finally {
        Remove-Item -LiteralPath $tmpOut -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $tmpErr -ErrorAction SilentlyContinue
    }
}
catch {
    [ordered]@{
        success = $false
        message = $_.Exception.Message
        script  = 'Restart-PixellotAgent.ps1'
    } | ConvertTo-Json -Compress
}
