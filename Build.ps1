# =============================================================================
#  Build.ps1  -  Combines launcher + all module files into a single Run.ps1
#  Run automatically by RunDiagnostic.bat before launching the tool.
# =============================================================================

$dest   = $PSScriptRoot
$modDir = Join-Path $dest "Modules"
$mods   = @(
    'UIHelpers','SystemOverview','CameraConnectivity','NetworkDiagnostics',
    'ReportGenerator','HelpAbout','PoeNicHardware','PixellotServices',
    'DiskHealth','EventViewer','HardwareOverview','FullDiagnostic'
)

Write-Host "Building combined launcher..."

if (-not (Test-Path "$dest\TestCameraConnectivity.ps1")) {
    Write-Error "TestCameraConnectivity.ps1 not found in $dest"; exit 1
}
if (-not (Test-Path $modDir)) {
    Write-Error "Modules\ directory not found in $dest"; exit 1
}

$out = [System.Collections.Generic.List[string]]::new()
foreach ($line in (Get-Content "$dest\TestCameraConnectivity.ps1")) {
    $injected = $false
    foreach ($mod in $mods) {
        if ($line.Trim() -eq ('. "$ModulesDir\' + $mod + '.psm1"')) {
            $modPath = "$modDir\$mod.psm1"
            if (Test-Path $modPath) {
                $out.AddRange([string[]](Get-Content $modPath))
            } else {
                Write-Warning "Module not found: $modPath"
            }
            $injected = $true; break
        }
    }
    if (-not $injected) { $out.Add($line) }
}

[System.IO.File]::WriteAllLines(
    "$dest\Run.ps1",
    $out,
    [System.Text.UTF8Encoding]::new($false)
)
Write-Host "Done - Run.ps1 built ($($out.Count) lines)"
