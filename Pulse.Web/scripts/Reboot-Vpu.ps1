#Requires -Version 5.1
<#
.SYNOPSIS
    Reboots the VPU after a short delay so the HTTP reply can flush first.
.DESCRIPTION
    Triggered from Pulse's Settings page ("Reboot VPU"). Uses shutdown.exe
    /r /t <delay> so Windows schedules the restart and this script returns
    immediately — Restart-Computer would tear the box down before the server's
    HTTP reply lands, leaving the UI unsure whether the reboot started.

    /f forces apps to close so a stuck process (or an in-progress recording)
    can't veto the reboot. The UI confirms this is destructive before calling.

    Outputs JSON to stdout: { success, scheduledSec, message }.
#>
[CmdletBinding()]
param(
    [int]$DelaySec = 8
)

$ErrorActionPreference = 'Stop'

try {
    # /r reboot, /t delay (s), /c comment (shown in the shutdown event log),
    # /f force-close apps. Start-Process -Wait so we can read the exit code.
    $shutdownArgs = @(
        '/r', '/t', "$DelaySec",
        '/c', 'Reboot requested from Pulse diagnostics',
        '/f'
    )
    $proc = Start-Process -FilePath 'shutdown.exe' -ArgumentList $shutdownArgs `
        -NoNewWindow -PassThru -Wait

    if ($proc.ExitCode -eq 0) {
        [ordered]@{
            success      = $true
            scheduledSec = $DelaySec
            message      = "VPU will reboot in $DelaySec seconds."
        } | ConvertTo-Json -Compress
    }
    else {
        [ordered]@{
            success  = $false
            exitCode = $proc.ExitCode
            message  = "shutdown.exe exited with code $($proc.ExitCode). The Pulse account may not have permission to reboot the VPU."
        } | ConvertTo-Json -Compress
    }
}
catch {
    [ordered]@{
        success = $false
        message = $_.Exception.Message
        script  = 'Reboot-Vpu.ps1'
    } | ConvertTo-Json -Compress
}
