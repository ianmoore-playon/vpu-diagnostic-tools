#Requires -Version 5.1
<#
.SYNOPSIS
    Reads the installed Pixellot dependencies version from the registry.
.DESCRIPTION
    Adapted from Canopy/Leaf/getVpuDepsFromRegistry.ps1.

    Pixellot's dependency installer (Pixellot-Installer-Dependencies-X.Y.Z.exe)
    writes the installed version to:

        HKLM:\SOFTWARE\Pixellot   (value name: `dependencies`)

    The "latest" string is the version filename Pulse currently knows how to
    download (PDF #2 — see Install-PixellotDependencies.ps1). When the
    installed version is older than that, the Pixellot Services tab can
    surface a soft "outdated" hint next to the reinstall card.

    Outputs JSON to stdout. Always emits JSON even on registry-missing,
    matching the Audio script's resilient pattern.
#>
[CmdletBinding()]
param(
    # Bumping this constant on a new dependency-installer drop is the only
    # change needed when Pixellot ships a new version. Keep in sync with
    # the URL hardcoded in Install-PixellotDependencies.ps1.
    [string]$LatestKnownVersion = '5.0.0'
)

$result = $null

try {
    $regPath = 'HKLM:\SOFTWARE\Pixellot'
    $valueName = 'dependencies'

    $installed = $null
    $present = $false

    if (Test-Path -LiteralPath $regPath) {
        try {
            $installed = (Get-ItemProperty -LiteralPath $regPath -Name $valueName -ErrorAction Stop).$valueName
            $present = $true
        } catch {
            # Key exists but value doesn't — that's a fresh-install signal.
            $present = $false
        }
    }

    # Compare installed vs latest using a tuple-of-ints comparator. Treat any
    # non-numeric suffix as zero so "5.0.0-beta" parses cleanly.
    function _ParseVer($v) {
        if (-not $v) { return @(0, 0, 0) }
        $parts = @()
        foreach ($p in ([string]$v -split '\.')) {
            $num = 0
            if ([int]::TryParse(($p -replace '[^0-9]', ''), [ref]$num)) {
                $parts += $num
            } else {
                $parts += 0
            }
        }
        # Pad to 3 parts for consistent comparison
        while ($parts.Count -lt 3) { $parts += 0 }
        return $parts
    }

    $status = 'unknown'
    if (-not $present -or -not $installed) {
        $status = 'missing'
    } else {
        $a = _ParseVer $installed
        $b = _ParseVer $LatestKnownVersion
        # Compare element-by-element
        $cmp = 0
        for ($i = 0; $i -lt [Math]::Max($a.Count, $b.Count); $i++) {
            $av = if ($i -lt $a.Count) { $a[$i] } else { 0 }
            $bv = if ($i -lt $b.Count) { $b[$i] } else { 0 }
            if ($av -ne $bv) { $cmp = $av - $bv; break }
        }
        if     ($cmp -gt 0) { $status = 'newer' }
        elseif ($cmp -lt 0) { $status = 'outdated' }
        else                { $status = 'current' }
    }

    $result = [ordered]@{
        installedVersion    = $installed
        latestKnownVersion  = $LatestKnownVersion
        status              = $status
        registryKey         = $regPath
        registryValueName   = $valueName
        registryKeyPresent  = (Test-Path -LiteralPath $regPath)
    }
}
catch {
    $result = [ordered]@{
        error   = $true
        message = $_.Exception.Message
        script  = 'Get-PixellotDependencies.ps1'
    }
}

$result | ConvertTo-Json -Depth 4 -Compress
