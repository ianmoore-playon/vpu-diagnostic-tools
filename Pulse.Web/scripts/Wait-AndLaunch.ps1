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

# Append-only breadcrumb log, separate from pulse-server.log (which the hidden
# server holds open for writing). The browser launch used to be completely
# silent, so a tester reporting "said it's running but no window appeared" left
# us guessing. This records which Chrome we found and whether the launch took,
# so the next report is diagnosable instead of inferred. Never throws.
$LaunchLog = Join-Path $PSScriptRoot '..\pulse-launch.log'
function Write-LaunchLog($msg) {
    try {
        $stamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
        Add-Content -Path $LaunchLog -Value "$stamp  $msg" -ErrorAction SilentlyContinue
    } catch { }
}

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

# Open Pulse in Chrome. The first launch on a freshly transferred VPU hits a
# COLD Chrome profile: Chrome's first-run path (profile creation + the
# "welcome / set as default" interstitial) swallows the URL and never surfaces
# a window, so the launcher prints "running" and closes with nothing on screen
# — and the tester has to run it a second time, when the profile is warm. The
# flags below skip that first-run friction and force the URL into a new window;
# --no-first-run + --no-default-browser-check are exactly what a cold profile
# needs to open straight to the page.
function Open-Browser {
    if ($env:PULSE_NO_BROWSER) {
        # A self-update restart sets this: the page that triggered the update is
        # still open and reconnects on its own, so a second tab would be noise.
        Write-LaunchLog "PULSE_NO_BROWSER set - skipping browser launch"
        return
    }

    $chrome = Get-ChromePath
    if (-not $chrome) {
        # No Chrome found — fall back to the default handler. Can't pass the
        # cold-profile flags here, but this is the rare "Chrome genuinely
        # missing" path; the launcher normally guarantees it's installed.
        Write-LaunchLog "Chrome not found - opening $Url via default handler"
        try { Start-Process $Url } catch { Write-LaunchLog "default-handler launch threw: $_" }
        return
    }

    $chromeArgs = @('--no-first-run', '--no-default-browser-check', '--new-window', $Url)
    Write-LaunchLog "Launching Chrome: $chrome $($chromeArgs -join ' ')"
    try { Start-Process -FilePath $chrome -ArgumentList $chromeArgs } catch { Write-LaunchLog "Chrome launch threw: $_" }

    # Start-Process can't confirm a window actually appeared, and the cold
    # first-run can drop the launch entirely. Give Chrome a moment, then if no
    # chrome.exe is running at all, our launch produced nothing — retry once.
    # (If Chrome was already open this check sees those processes and skips the
    # retry, which is correct: --new-window into a warm instance is reliable.)
    Start-Sleep -Seconds 3
    if (-not (Get-Process -Name chrome -ErrorAction SilentlyContinue)) {
        Write-LaunchLog "No chrome.exe after launch - retrying once"
        try { Start-Process -FilePath $chrome -ArgumentList $chromeArgs } catch { Write-LaunchLog "Chrome retry threw: $_" }
    } else {
        Write-LaunchLog "Chrome is running"
    }
}

$elapsed = 0
while ($elapsed -lt $TimeoutSec) {
    try {
        $client = New-Object System.Net.Sockets.TcpClient
        $iar = $client.BeginConnect('127.0.0.1', $Port, $null, $null)
        $ok = $iar.AsyncWaitHandle.WaitOne(500)
        if ($ok -and $client.Connected) {
            $client.Close()
            Write-LaunchLog "Port $Port up after ~$elapsed s - opening browser"
            Open-Browser
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
Write-LaunchLog "Timed out after ${TimeoutSec}s waiting for port $Port"
exit 1
