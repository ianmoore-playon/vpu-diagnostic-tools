# =============================================================================
#  Set-FeedbackToken.ps1  -  Encrypts and stores the Pulse feedback token
#
#  Run once on each VPU after installing Pulse:
#    PowerShell -NoProfile -ExecutionPolicy Bypass -File Set-FeedbackToken.ps1
#
#  Or pass the token directly (e.g. via remote script):
#    PowerShell -NoProfile -ExecutionPolicy Bypass -File Set-FeedbackToken.ps1 -Token "github_pat_..."
#
#  The token is encrypted using Windows DPAPI (LocalMachine scope) and stored
#  at C:\ProgramData\Pulse\feedback.key. The ciphertext is machine-specific —
#  it cannot be decrypted on any other machine.
# =============================================================================

param([string]$Token = "")

# Require admin
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error "This script must be run as Administrator."
    exit 1
}

# Prompt securely if no token supplied
if (-not $Token) {
    $secure = Read-Host "Enter the Pulse feedback token" -AsSecureString
    $bstr   = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    try { $Token = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr) }
    finally { [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
}

if (-not $Token.Trim()) {
    Write-Error "No token provided. Aborting."
    exit 1
}

Add-Type -AssemblyName System.Security

$keyDir  = "C:\ProgramData\Pulse"
$keyPath = "$keyDir\feedback.key"

if (-not (Test-Path $keyDir)) {
    New-Item -ItemType Directory -Path $keyDir -Force | Out-Null
}

$bytes     = [System.Text.Encoding]::UTF8.GetBytes($Token.Trim())
$encrypted = [System.Security.Cryptography.ProtectedData]::Protect(
    $bytes, $null, [System.Security.Cryptography.DataProtectionScope]::LocalMachine
)
[System.IO.File]::WriteAllBytes($keyPath, $encrypted)

# Clear plaintext from memory
[System.Array]::Clear($bytes, 0, $bytes.Length)
$Token = $null

Write-Host ""
Write-Host "  Feedback token encrypted and saved." -ForegroundColor Green
Write-Host "  Location : $keyPath"
Write-Host "  Scope    : LocalMachine (this machine only)"
Write-Host ""
