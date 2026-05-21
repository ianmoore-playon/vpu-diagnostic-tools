# install-beta.ps1 — Beta channel
# Downloads the latest PRE-RELEASE from pulse-releases and runs Pulse.WPF.
# Deployed to the root of ianmoore-playon/pulse-releases.

$ErrorActionPreference = 'Stop'
$repo       = "ianmoore-playon/pulse-releases"
$installDir = "$env:LOCALAPPDATA\Pulse.WPF-beta"
$zipPath    = "$env:TEMP\Pulse.WPF-beta-latest.zip"

Write-Host "Fetching latest beta pre-release..."
$releases = Invoke-RestMethod "https://api.github.com/repos/$repo/releases"
$release  = $releases | Where-Object { $_.prerelease -eq $true } | Select-Object -First 1

if (-not $release) {
    Write-Host "No beta pre-release found." -ForegroundColor Red
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

Write-Host "Launching Pulse.WPF BETA ($($release.tag_name))..."
Start-Process $exe.FullName
