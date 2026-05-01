# =============================================================================
#  Set-FeedbackToken.ps1  -  Encrypts and stores the Pulse feedback token
#
#  Called automatically by Pulse.bat on first install. Can also be re-run
#  manually to rotate the token:
#    PowerShell -NoProfile -ExecutionPolicy Bypass -File Set-FeedbackToken.ps1
#
#  The token is encrypted using Windows DPAPI (LocalMachine scope) and stored
#  at C:\ProgramData\Pulse\feedback.key. The ciphertext is machine-specific —
#  it cannot be decrypted on any other machine.
# =============================================================================

# Require admin
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error "This script must be run as Administrator."
    exit 1
}

$Token = "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"   # issues:write

Add-Type -AssemblyName System.Security

$keyDir  = "C:\ProgramData\Pulse"
$keyPath = "$keyDir\feedback.key"

if (-not (Test-Path $keyDir)) {
    New-Item -ItemType Directory -Path $keyDir -Force | Out-Null
}

$bytes     = [System.Text.Encoding]::UTF8.GetBytes($Token)
$encrypted = [System.Security.Cryptography.ProtectedData]::Protect(
    $bytes, $null, [System.Security.Cryptography.DataProtectionScope]::LocalMachine
)
[System.IO.File]::WriteAllBytes($keyPath, $encrypted)

[System.Array]::Clear($bytes, 0, $bytes.Length)
$Token = $null

Write-Host "  Feedback token configured." -ForegroundColor Green
