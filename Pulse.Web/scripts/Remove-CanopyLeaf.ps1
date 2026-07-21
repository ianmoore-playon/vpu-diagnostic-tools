# Remove-CanopyLeaf.ps1 - one-shot removal of the retired Canopy Leaf agent
# (Banyan Hills). PlayOn no longer uses Canopy; the fleet's Leaf installs are
# orphaned and their services still run at boot. This script runs the four
# NSIS uninstallers silently, clears every Leaf scheduled task / service /
# process, then deletes C:\Banyan entirely.
#
# Idempotent: the folder's absence is the "already done" marker, so Pulse can
# fire this on every launch for free. Safe-by-construction choices:
#   - NSIS silent flag /S plus _?=<installdir>: forces the uninstaller to run
#     in-place instead of the copy-to-%TEMP%-and-return-early trick, which
#     makes WaitForExit actually cover the work (validated on VPU2).
#   - Every uninstaller gets a hard timeout; a hung child is killed, recorded,
#     and the sweep continues - the folder delete still reclaims the box.
#   - The recursive delete targets the literal path C:\Banyan only.
# Emits one compressed JSON object on stdout (Pulse collector convention).

$ErrorActionPreference = 'SilentlyContinue'

$BanyanRoot = 'C:\Banyan'
$LeafDir    = 'C:\Banyan\Canopy\Leaf'
$Uninstallers = @(
    'leaf_agent_uninstall.exe',
    'leaf_services_uninstall.exe',
    'leaf_sw_updater_uninstall.exe',
    'leaf_sw_updater_installer_uninstall.exe'
)
$UninstallTimeoutMs = 120000

$result = [ordered]@{
    status          = ''
    uninstallers    = @()
    tasksRemoved    = @()
    servicesDeleted = @()
    processesKilled = @()
    folderDeleted   = $false
    leftovers       = @()
    error           = $null
}

function Emit($r) { Write-Output (ConvertTo-Json $r -Compress -Depth 6) }

# -- Short-circuit: nothing to do ------------------------------------------
if (-not (Test-Path $BanyanRoot)) {
    $result.status = 'not-present'
    Emit $result
    exit 0
}

# -- Admin gate: uninstalls and service deletion need elevation ------------
$identity  = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    $result.status = 'no-admin'
    Emit $result
    exit 0
}

# -- Concurrency lock: two Pulse launches must not overlap -----------------
$lockPath = Join-Path $env:windir 'Temp\pulse-canopy-removal.lock'
$lock = $null
try {
    $lock = [IO.File]::Open($lockPath, 'OpenOrCreate', 'ReadWrite', 'None')
} catch {
    $result.status = 'already-running'
    Emit $result
    exit 0
}

try {
    # -- 1. Scheduled tasks first: LeafWatchdog resurrects services --------
    $tasks = @(Get-ScheduledTask | Where-Object { $_.TaskName -match '^leaf' })
    foreach ($t in $tasks) {
        $null = Stop-ScheduledTask -TaskName $t.TaskName -ErrorAction SilentlyContinue
        Unregister-ScheduledTask -TaskName $t.TaskName -Confirm:$false -ErrorAction SilentlyContinue
        $result.tasksRemoved += $t.TaskName
    }

    # -- 2. Silent uninstallers (each stops + deregisters its own service) -
    foreach ($name in $Uninstallers) {
        $exe = Join-Path $LeafDir $name
        if (-not (Test-Path $exe)) {
            $result.uninstallers += [pscustomobject]@{ name = $name; skipped = 'missing' }
            continue
        }
        $proc = Start-Process -FilePath $exe -ArgumentList '/S', "_?=$LeafDir" `
            -WindowStyle Hidden -PassThru
        $finished = $proc.WaitForExit($UninstallTimeoutMs)
        if (-not $finished) {
            try { $proc.Kill() } catch {}
            $result.uninstallers += [pscustomobject]@{ name = $name; timedOut = $true }
        } else {
            $result.uninstallers += [pscustomobject]@{ name = $name; exitCode = $proc.ExitCode }
        }
    }

    # -- 3. Anything the uninstallers missed: services, then processes -----
    foreach ($svc in @(Get-Service | Where-Object { $_.Name -match '^leaf' })) {
        $null = Stop-Service -Name $svc.Name -Force -ErrorAction SilentlyContinue
        $null = & sc.exe delete $svc.Name
        $result.servicesDeleted += $svc.Name
    }
    foreach ($p in @(Get-Process | Where-Object { $_.Path -like "$BanyanRoot\*" })) {
        $null = Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
        $result.processesKilled += $p.Name
    }

    # -- 4. Delete the folder; retry while released file locks drain -------
    for ($attempt = 1; $attempt -le 5; $attempt++) {
        Remove-Item -LiteralPath 'C:\Banyan' -Recurse -Force -ErrorAction SilentlyContinue
        if (-not (Test-Path $BanyanRoot)) { break }
        Start-Sleep -Seconds 3
    }
    $result.folderDeleted = -not (Test-Path $BanyanRoot)

    # -- 5. Verify ----------------------------------------------------------
    foreach ($svc in @(Get-Service | Where-Object { $_.Name -match '^leaf' })) {
        $result.leftovers += "service:$($svc.Name)"
    }
    if (-not $result.folderDeleted) { $result.leftovers += "folder:$BanyanRoot" }

    if ($result.leftovers.Count -eq 0) { $result.status = 'removed' }
    else { $result.status = 'partial' }
} catch {
    $result.status = 'error'
    $result.error = '' + $_.Exception.Message
} finally {
    if ($null -ne $lock) { $lock.Close() }
}

Emit $result
