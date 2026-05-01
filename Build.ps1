# =============================================================================
#  Build.ps1  -  Combines Pulse.ps1 + all module files into a single Run.ps1
#  Required for VPU deployment: .psm1 files cannot be dot-sourced on VPUs
#  (Windows file association opens them in Notepad instead of executing).
# =============================================================================

$dest   = $PSScriptRoot
$modDir = Join-Path $dest "Modules"
$mods   = @(
    'UIHelpers','SystemOverview','CameraConnectivity','NetworkDiagnostics',
    'ReportGenerator','HelpAbout','PoeNicHardware','PixellotServices',
    'DiskHealth','EventLogs','SystemInformation','FullDiagnostic'
)

Write-Verbose "Building combined launcher..."

if (-not (Test-Path "$dest\Pulse.ps1")) {
    Write-Error "Pulse.ps1 not found in $dest"; exit 1
}
if (-not (Test-Path $modDir)) {
    Write-Error "Modules\ directory not found in $dest"; exit 1
}

$out = [System.Collections.Generic.List[string]]::new()
foreach ($line in (Get-Content "$dest\Pulse.ps1" -Encoding UTF8)) {
    $injected = $false
    foreach ($mod in $mods) {
        if ($line.Trim() -eq ('. "$ModulesDir\' + $mod + '.psm1"')) {
            $modPath = "$modDir\$mod.psm1"
            if (Test-Path $modPath) {
                $out.AddRange([string[]](Get-Content $modPath -Encoding UTF8))
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
    [System.Text.UTF8Encoding]::new($true)
)
Write-Verbose "Done - Run.ps1 built ($($out.Count) lines)"
