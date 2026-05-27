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

$elapsed = 0
while ($elapsed -lt $TimeoutSec) {
    try {
        $client = New-Object System.Net.Sockets.TcpClient
        $iar = $client.BeginConnect('127.0.0.1', $Port, $null, $null)
        $ok = $iar.AsyncWaitHandle.WaitOne(500)
        if ($ok -and $client.Connected) {
            $client.Close()
            Start-Process $Url
            exit 0
        }
        $client.Close()
    } catch {
        # Port not open yet — sleep and retry
    }
    Start-Sleep -Milliseconds 500
    $elapsed += 1
}

# Timeout — try launching anyway so the user at least sees the browser
Start-Process $Url
exit 1
