# install-dev.ps1 — Dev channel
# Downloads the latest DEV pre-release from pulse-releases and runs Pulse.WPF.
# Deployed to the root of playon/pulse.

$ErrorActionPreference = 'Stop'
$repo       = "playon/pulse"
$installDir = "$env:LOCALAPPDATA\Pulse.WPF-dev"
$zipPath    = "$env:TEMP\Pulse.WPF-dev-latest.zip"

Write-Host "Fetching latest dev pre-release..."
$releases = Invoke-RestMethod "https://api.github.com/repos/$repo/releases"
$release  = $releases | Where-Object { $_.prerelease -eq $true -and $_.tag_name -like "dev-v*" } | Select-Object -First 1

if (-not $release) {
    Write-Host "No dev pre-release found." -ForegroundColor Red
    pause
    exit 1
}

$asset = $release.assets | Where-Object { $_.name -like "*.zip" } | Select-Object -First 1

if (-not $asset) {
    Write-Host "No zip asset found in release $($release.tag_name)." -ForegroundColor Red
    pause
    exit 1
}

Write-Host "Downloading $($asset.name) ($($release.tag_name))..."
Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $zipPath -UseBasicParsing

if (Test-Path $installDir) { Remove-Item $installDir -Recurse -Force }
New-Item -ItemType Directory -Force $installDir | Out-Null
Expand-Archive -Path $zipPath -DestinationPath $installDir -Force
Remove-Item $zipPath -Force

$exe = Get-ChildItem $installDir -Recurse -Filter "Pulse.WPF.exe" | Select-Object -First 1
if (-not $exe) {
    Write-Host "Pulse.WPF.exe not found after extraction." -ForegroundColor Red
    pause
    exit 1
}

Write-Host "Launching Pulse.WPF DEV ($($release.tag_name))..."
Start-Process $exe.FullName
