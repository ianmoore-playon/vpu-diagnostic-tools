#Requires -Version 5.1
<#
.SYNOPSIS
    Waits for a local port to start accepting connections, then launches a URL.
.DESCRIPTION
    Used by run.bat to open Chrome only after uvicorn has bound to localhost:8765.
    A fixed sleep would race on cold VPUs where Python bootstrap is slow.
#>
[CmdletBinding()]
param(
    [int]$Port = 8765,
    [string]$Url = "http://localhost:8765",
    [int]$TimeoutSec = 30
)

# Resolve chrome.exe explicitly. Start-Process on a bare URL hands it to the
# DEFAULT browser handler — and a fresh VPU often has no default browser set,
# so Windows pops a "How do you want to open this?" picker (with IE as the
# first option) instead of opening Pulse. The launcher guarantees Chrome is
# installed, so open it directly; fall back to the default handler only if
# Chrome is genuinely missing.
function Get-ChromePath {
    # Plain string interpolation (not Join-Path): a missing env var must yield
    # a harmless non-existent path, not a binding error.
    $candidates = @(
        (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\chrome.exe' -ErrorAction SilentlyContinue).'(default)'
        "$env:ProgramFiles\Google\Chrome\Application\chrome.exe"
        "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe"
        "$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe"
    )
    foreach ($p in $candidates) {
        if ($p -and (Test-Path $p)) { return $p }
    }
    return $null
}

$elapsed = 0
while ($elapsed -lt $TimeoutSec) {
    try {
        $client = New-Object System.Net.Sockets.TcpClient
        $iar = $client.BeginConnect('127.0.0.1', $Port, $null, $null)
        $ok = $iar.AsyncWaitHandle.WaitOne(500)
        if ($ok -and $client.Connected) {
            $client.Close()
            # A self-update restart sets PULSE_NO_BROWSER=1: the page that
            # triggered the update is still open and reconnects on its own,
            # so opening a second browser tab would just be noise.
            if (-not $env:PULSE_NO_BROWSER) {
                $chrome = Get-ChromePath
                if ($chrome) { Start-Process $chrome $Url }
                else         { Start-Process $Url }
            }
            exit 0   # server is up
        }
        $client.Close()
    } catch {
        # Port not open yet — sleep and retry
    }
    Start-Sleep -Milliseconds 500
    $elapsed += 1
}

# Timed out — the server never came up. Do NOT open the browser (it would
# just show a connection error); exit non-zero so run.bat surfaces the
# failure and points the user at pulse-server.log.
exit 1
