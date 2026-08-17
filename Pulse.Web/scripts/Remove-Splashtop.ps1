# Remove-Splashtop.ps1 - one-shot removal of Splashtop Streamer, deployed to
# the fleet as part of the retired Banyan Hills Canopy stack (see
# Remove-CanopyLeaf.ps1 for the agent itself). Runs separately from the Leaf
# sweep because boxes already swept clean of C:\Banyan still carry Splashtop.
#
# Splashtop Streamer is an MSI install (verified on VPU2), so removal is
# msiexec /x {ProductCode} /qn /norestart per registry uninstall entry, then
# a leftover sweep: services, SR* processes, and the two install/data dirs.
# Idempotent: gates on the uninstall registry entry / install dir, both of
# which the removal deletes. Safe-by-construction choices:
#   - /norestart always: an uninstall must never reboot a VPU. msiexec exit
#     code 3010 (success, reboot pending) is recorded and treated as success.
#   - Every msiexec gets a hard timeout; a hung child is killed, recorded,
#     and the sweep continues - the leftover sweep still reclaims the box.
#   - Dir deletes target the literal Splashtop paths only.
# NOTE: uninstalling kills any live Splashtop remote-control session on the
# box by design - the fleet's supported remote path is LogMeIn.
# Emits one compressed JSON object on stdout (Pulse collector convention).

$ErrorActionPreference = 'SilentlyContinue'

$InstallDirs = @(
    'C:\Program Files (x86)\Splashtop',
    'C:\Program Files\Splashtop'
)
$LeftoverDirs = $InstallDirs + @('C:\ProgramData\Splashtop')
$UninstallHives = @(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
)
$UninstallTimeoutMs = 300000

$result = [ordered]@{
    status          = ''
    uninstalls      = @()
    servicesDeleted = @()
    processesKilled = @()
    foldersDeleted  = @()
    leftovers       = @()
    error           = $null
}

function Emit($r) { Write-Output (ConvertTo-Json $r -Compress -Depth 6) }

function Get-SplashtopEntries {
    @(Get-ItemProperty $UninstallHives -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName -like 'Splashtop*' })
}

function Test-AnyDir($dirs) {
    foreach ($d in $dirs) { if (Test-Path -LiteralPath $d) { return $true } }
    return $false
}

# -- Short-circuit: nothing to do ------------------------------------------
$entries = Get-SplashtopEntries
if ($entries.Count -eq 0 -and -not (Test-AnyDir $LeftoverDirs)) {
    $result.status = 'not-present'
    Emit $result
    exit 0
}

# -- Admin gate: MSI uninstall and service deletion need elevation ---------
$identity  = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    $result.status = 'no-admin'
    Emit $result
    exit 0
}

# -- Concurrency lock: two Pulse launches must not overlap -----------------
$lockPath = Join-Path $env:windir 'Temp\pulse-splashtop-removal.lock'
$lock = $null
try {
    $lock = [IO.File]::Open($lockPath, 'OpenOrCreate', 'ReadWrite', 'None')
} catch {
    $result.status = 'already-running'
    Emit $result
    exit 0
}

try {
    # -- 1. MSI uninstall per registry entry (stops its own service) -------
    foreach ($entry in $entries) {
        $name = '' + $entry.DisplayName
        $guid = $null
        if ($entry.PSChildName -match '^\{[0-9A-Fa-f-]+\}$') {
            $guid = $entry.PSChildName
        } elseif (('' + $entry.UninstallString) -match '(\{[0-9A-Fa-f-]+\})') {
            $guid = $Matches[1]
        }
        if ($null -eq $guid) {
            $result.uninstalls += [pscustomobject]@{ name = $name; skipped = 'no-product-code' }
            continue
        }
        $proc = Start-Process -FilePath 'msiexec.exe' `
            -ArgumentList '/x', $guid, '/qn', '/norestart' `
            -WindowStyle Hidden -PassThru
        $finished = $proc.WaitForExit($UninstallTimeoutMs)
        if (-not $finished) {
            try { $proc.Kill() } catch {}
            $result.uninstalls += [pscustomobject]@{ name = $name; guid = $guid; timedOut = $true }
        } else {
            # 0 = success, 3010 = success + reboot pending (suppressed by /norestart)
            $result.uninstalls += [pscustomobject]@{ name = $name; guid = $guid; exitCode = $proc.ExitCode }
        }
    }

    # -- 2. Anything the MSI missed: services, then processes --------------
    foreach ($svc in @(Get-Service | Where-Object {
            $_.Name -like 'SplashtopRemote*' -or $_.DisplayName -like '*Splashtop*' })) {
        $null = Stop-Service -Name $svc.Name -Force -ErrorAction SilentlyContinue
        $null = & sc.exe delete $svc.Name
        $result.servicesDeleted += $svc.Name
    }
    foreach ($root in $InstallDirs) {
        foreach ($p in @(Get-Process | Where-Object { $_.Path -like "$root\*" })) {
            $null = Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
            $result.processesKilled += $p.Name
        }
    }

    # -- 3. Delete leftover dirs; retry while released file locks drain ----
    foreach ($dir in $LeftoverDirs) {
        if (-not (Test-Path -LiteralPath $dir)) { continue }
        for ($attempt = 1; $attempt -le 5; $attempt++) {
            Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue
            if (-not (Test-Path -LiteralPath $dir)) { break }
            Start-Sleep -Seconds 3
        }
        if (-not (Test-Path -LiteralPath $dir)) { $result.foldersDeleted += $dir }
    }

    # -- 4. Verify -----------------------------------------------------------
    foreach ($entry in Get-SplashtopEntries) {
        $result.leftovers += "registry:$($entry.DisplayName)"
    }
    foreach ($svc in @(Get-Service | Where-Object { $_.Name -like 'SplashtopRemote*' })) {
        $result.leftovers += "service:$($svc.Name)"
    }
    foreach ($dir in $LeftoverDirs) {
        if (Test-Path -LiteralPath $dir) { $result.leftovers += "folder:$dir" }
    }

    if ($result.leftovers.Count -eq 0) { $result.status = 'removed' }
    else { $result.status = 'partial' }
} catch {
    $result.status = 'error'
    $result.error = '' + $_.Exception.Message
} finally {
    if ($null -ne $lock) { $lock.Close() }
}

Emit $result
