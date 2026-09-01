<#
.SYNOPSIS
    Open the Windows firewall for Pulse's LAN share listener.

.DESCRIPTION
    "Receive over LAN" binds a listener on 0.0.0.0:<port>, but Windows Defender
    Firewall silently drops inbound connections to it until an allow-rule exists
    -- so a peer's send just times out. This adds a single inbound TCP allow-rule
    named "Pulse LAN Share".

    Adding a firewall rule needs admin. The script is idempotent: if the rule
    already exists it returns immediately (no prompt). Otherwise it tries to add
    it; if that's denied (normal -- Pulse runs unelevated), it relaunches itself
    once via Start-Process -Verb RunAs (a single UAC prompt), the same elevation
    pattern as the ScoreConnect III installer.

    Emits one compact JSON object on the last stdout line, per Pulse convention.
.PARAMETER Port
    TCP port to allow inbound. Defaults to 8766.
.PARAMETER Elevated
    Internal -- set when the script relaunches itself as administrator.
#>
param(
    [string]$Port = "8766",
    [switch]$Elevated
)

$ErrorActionPreference = "Stop"
$RuleName = "Pulse LAN Share"

function Write-Result($obj) { $obj | ConvertTo-Json -Compress }

# Already allowed? (cheap, no elevation needed)
& netsh advfirewall firewall show rule name="$RuleName" *> $null
if ($LASTEXITCODE -eq 0) {
    Write-Result @{ applied = $true; already = $true; port = $Port; message = "Firewall already allows port $Port." }
    exit 0
}

# Try to add the rule (succeeds only if we're already elevated).
& netsh advfirewall firewall add rule name="$RuleName" dir=in action=allow protocol=TCP localport=$Port *> $null
if ($LASTEXITCODE -eq 0) {
    Write-Result @{ applied = $true; port = $Port; message = "Opened firewall for port $Port." }
    exit 0
}

if ($Elevated) {
    # We were the elevated child and still failed -- report it rather than loop.
    Write-Result @{ applied = $false; port = $Port; error = "Could not add firewall rule even when elevated." }
    exit 1
}

# Not elevated: relaunch self once as administrator to add the rule.
try {
    $scriptPath = $MyInvocation.MyCommand.Path
    $argLine = "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`" -Port $Port -Elevated"
    Start-Process -FilePath "powershell.exe" -Verb RunAs -WindowStyle Hidden -ArgumentList $argLine | Out-Null
    Write-Result @{ applied = $true; elevating = $true; port = $Port; message = "Asked Windows for permission to open the firewall. Approve the prompt." }
    exit 0
} catch {
    Write-Result @{ applied = $false; port = $Port; error = "Couldn't request administrator approval: $($_.Exception.Message)" }
    exit 1
}
