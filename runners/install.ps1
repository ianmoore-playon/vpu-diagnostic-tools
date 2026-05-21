# install.ps1 — Production channel
# Downloads the latest STABLE release from pulse-releases and runs Pulse.WPF.
# Deployed to the root of ianmoore-playon/pulse-releases.

$ErrorActionPreference = 'Stop'
$repo       = "ianmoore-playon/pulse-releases"
$installDir = "$env:LOCALAPPDATA\Pulse.WPF"
$zipPath    = "$env:TEMP\Pulse.WPF-latest.zip"

Write-Host "Fetching latest production release..."
$release = Invoke-RestMethod "https://api.github.com/repos/$repo/releases/latest"
$asset   = $release.assets | Where-Object { $_.name -like "*.zip" } | Select-Object -First 1

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

Write-Host "Launching Pulse.WPF ($($release.tag_name))..."
Start-Process $exe.FullName
