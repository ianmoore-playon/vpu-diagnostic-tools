#Requires -Version 5.1
<#
.SYNOPSIS
    Runs c:\pixellot\bin\keepagentup.exe to restart the Pixellot Agent and
    Coordinator services.
.DESCRIPTION
    Per Pixellot Troubleshooting Tips PDF #13, keepagentup.exe is the
    documented "fast remedy before escalating" when agent or coordinator
    is down. It re-launches both services and clears the typical hung-state.

    Outputs JSON to stdout with success/failure and the executable's
    stdout/stderr captured.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$keepAgentPath = 'C:\pixellot\bin\keepagentup.exe'

try {
    if (-not (Test-Path -LiteralPath $keepAgentPath)) {
        [ordered]@{
            success = $false
            message = "keepagentup.exe not found at $keepAgentPath. Verify Pixellot is installed."
            path    = $keepAgentPath
        } | ConvertTo-Json -Compress
        return
    }

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

        $stdoutText = (Get-Content -LiteralPath $tmpOut -Raw -ErrorAction SilentlyContinue) -as [string]
        $stderrText = (Get-Content -LiteralPath $tmpErr -Raw -ErrorAction SilentlyContinue) -as [string]

        # Snapshot service state immediately after — gives the UI confirmation
        # that agent + coordinator are actually running again.
        $agent = Get-Service -Name 'agent' -ErrorAction SilentlyContinue
        $coord = Get-Service -Name 'coordinator' -ErrorAction SilentlyContinue

        [ordered]@{
            success     = ($proc.ExitCode -eq 0)
            exitCode    = $proc.ExitCode
            path        = $keepAgentPath
            stdout      = if ($stdoutText) { $stdoutText.Trim() } else { '' }
            stderr      = if ($stderrText) { $stderrText.Trim() } else { '' }
            agentStatus = if ($agent) { $agent.Status.ToString() } else { 'NotFound' }
            coordinatorStatus = if ($coord) { $coord.Status.ToString() } else { 'NotFound' }
            message     = if ($proc.ExitCode -eq 0) { 'keepagentup.exe completed successfully' } else { "keepagentup.exe exited with code $($proc.ExitCode)" }
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
