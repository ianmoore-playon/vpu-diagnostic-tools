#Requires -Version 5.1
<#
.SYNOPSIS
    Patch/update evidence for a VPU where the Windows Update UI looks empty.
.DESCRIPTION
    LOCAL collector (event log + registry + WMI, no network). Answers the
    question a school's IT department asks when they want proof a security
    patch landed: "show me what was updated on this box, and when."

    Pixellot owns patching on the fleet and applies updates selectively /
    offline, so the Windows Update control panel and the WU agent history
    look empty or years stale. That is expected and proves NOTHING either
    way. Offline installs (wusa/DISM) still go through the Component Based
    Servicing stack, which leaves durable, dated evidence. This collector
    reads that evidence, in four blocks:

      os        -- full build number including UBR. Cumulative updates are
                   cumulative, so this ONE number is the OS patch level no
                   matter how the update was delivered. Compare it to
                   Microsoft's release-history page to date it.
      delivery  -- WU service + policy state: is WU disabled, is a WSUS
                   server configured? This is HOW patches arrive, and it's
                   what explains the empty Windows Update UI.
      defender  -- security definitions: current AV/AS/NIS signature
                   versions and the timestamp each was APPLIED (registry,
                   readable even when the service is stopped), plus a dated
                   history of definition updates from the Defender
                   Operational log.
      updates   -- installed Windows patches with install dates, from
                   Get-HotFix (QFE) merged with the Setup log's servicing
                   timeline (which catches offline installs the WU agent
                   never saw). DRIVER packages are excluded by design --
                   they are not security patches; the count of what was
                   dropped is reported so the exclusion is visible.

    Also reports pending-reboot flags: a patch can be installed but not
    active, in which case the reported level overstates reality.

    Outputs a single JSON object on stdout.
.PARAMETER MaxUpdates
    Cap on merged update rows returned (newest first).
.PARAMETER MaxDefenderEvents
    Cap on definition-update history rows returned (newest first).
#>
[CmdletBinding()]
param(
    [int]$MaxUpdates = 200,
    [int]$MaxDefenderEvents = 60
)

$ErrorActionPreference = 'Stop'

function Get-RegValue {
    # Registry reads here are all "absent is normal" -- a missing policy key
    # is itself a finding, not an error.
    param([string]$Path, [string]$Name)
    try {
        $k = Get-ItemProperty -Path $Path -Name $Name -ErrorAction Stop
        return $k.$Name
    } catch { return $null }
}

function ConvertFrom-FileTimeBytes {
    # Defender stamps its "signature applied" times as REG_BINARY FILETIME
    # (8 bytes, little-endian). This is the most reliable proof of WHEN a
    # definition landed: it survives the service being stopped, and unlike
    # Get-MpComputerStatus it needs no Defender PowerShell module.
    param($Bytes)
    if ($null -eq $Bytes) { return $null }
    try {
        if ($Bytes -isnot [byte[]]) { return $null }
        if ($Bytes.Length -lt 8) { return $null }
        $ticks = [System.BitConverter]::ToInt64($Bytes, 0)
        if ($ticks -le 0) { return $null }
        return [DateTime]::FromFileTimeUtc($ticks).ToLocalTime()
    } catch { return $null }
}

function Get-AgeDays {
    param($When)
    if ($null -eq $When) { return $null }
    try { return [int]((Get-Date) - $When).TotalDays } catch { return $null }
}

function Get-MessageField {
    # Pull "Label: value" out of an event message, bounded to the rest of that
    # LINE. A greedy \S+ instead walks past an empty field and captures the
    # next label's text -- measured on VPU2, where every Defender 2001 event
    # has empty version fields and reported engineVersion = "Previous".
    param([string]$Message, [string]$Label)
    if (-not $Message) { return $null }
    $pattern = '(?m)^\s*' + [regex]::Escape($Label) + '\s*:[ \t]*(.*)$'
    $m = [regex]::Match($Message, $pattern)
    if (-not $m.Success) { return $null }
    $v = $m.Groups[1].Value.Trim()
    if ($v -eq '') { return $null }
    return $v
}

function Test-IsDriverPackage {
    # Driver packages are explicitly out of scope for this lane. They show up
    # in the servicing timeline with a driver marker in the package identity;
    # Get-HotFix labels them 'Driver' in Description when it lists them at all.
    param([string]$Text)
    if (-not $Text) { return $false }
    return ($Text -match '(?i)driver')
}

try {
    $isAdmin = $false
    try {
        $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
                   ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch { }

    # ---------------------------------------------------------- 1. OS level
    $cv = $null
    try { $cv = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction Stop } catch { }
    $ubr = if ($cv) { $cv.UBR } else { $null }
    $build = if ($cv) { $cv.CurrentBuild } else { $null }
    $fullBuild = $null
    if ($cv -and $build) {
        $maj = if ($null -ne $cv.CurrentMajorVersionNumber) { $cv.CurrentMajorVersionNumber } else { 10 }
        $min = if ($null -ne $cv.CurrentMinorVersionNumber) { $cv.CurrentMinorVersionNumber } else { 0 }
        $fullBuild = "$maj.$min.$build.$ubr"
    }
    $osInstall = $null
    try {
        if ($cv -and $cv.InstallDate) {
            $osInstall = ([DateTime]'1970-01-01').AddSeconds($cv.InstallDate).ToLocalTime().ToString('o')
        }
    } catch { }

    $osBlock = [ordered]@{
        productName    = if ($cv) { $cv.ProductName } else { $null }
        edition        = if ($cv) { $cv.EditionID } else { $null }
        featureRelease = if ($cv) { if ($cv.DisplayVersion) { $cv.DisplayVersion } else { $cv.ReleaseId } } else { $null }
        build          = $build
        ubr            = $ubr
        fullBuild      = $fullBuild
        imageInstalled = $osInstall
    }

    # ------------------------------------------- 2. Delivery path (the "why")
    $svcState = @()
    foreach ($n in @('wuauserv', 'UsoSvc', 'TrustedInstaller', 'WinDefend')) {
        $s = $null
        try { $s = Get-Service -Name $n -ErrorAction Stop } catch { }
        # pscustomobject, not a hashtable: 5.1 can't treat hashtable keys as
        # properties, so a hashtable here breaks any downstream sort/select.
        $svcState += [pscustomobject]@{
            name      = $n
            status    = if ($s) { $s.Status.ToString() } else { 'absent' }
            startType = if ($s) { $s.StartType.ToString() } else { $null }
        }
    }

    $wuServer     = Get-RegValue 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate' 'WUServer'
    $targetGroup  = Get-RegValue 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate' 'TargetGroup'
    $noAutoUpdate = Get-RegValue 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU' 'NoAutoUpdate'
    $useWuServer  = Get-RegValue 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU' 'UseWUServer'
    $auOptions    = Get-RegValue 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU' 'AUOptions'

    $agentResults = @()
    foreach ($phase in @('Detect', 'Download', 'Install')) {
        $v = Get-RegValue "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\Results\$phase" 'LastSuccessTime'
        $agentResults += [pscustomobject]@{ phase = $phase; lastSuccessUtc = $v }
    }

    $mode = 'offline'
    if ($wuServer -and $useWuServer -eq 1) { $mode = 'wsus' }
    elseif ($noAutoUpdate -eq 1) { $mode = 'offline' }
    elseif (-not $wuServer -and $noAutoUpdate -ne 1) { $mode = 'windows-update' }

    # Do NOT assert that someone else is patching this box. The original wording
    # here said "Pixellot applies patches offline (wusa/DISM)" -- an assumption
    # inherited from the field explanation, not a measurement. Two units in
    # different states (Rochelle TX, Richland PA) both sit at build 17763.253
    # with no monthly cumulative ever applied after imaging, so Pulse vouching
    # for an offline patch process it cannot observe was actively misleading.
    # State what is configured, and let the servicing record speak.
    $modeExplanation = switch ($mode) {
        'wsus'   { 'Updates are delivered from a managed WSUS server, not the public Windows Update service. The Windows Update UI reports against that server, so check there as well as the record below.' }
        'offline' { 'Automatic Windows Update is disabled by policy on this VPU, which is why the Windows Update UI shows no history. Pulse cannot see whether any other mechanism is patching this unit - the servicing record below is the only evidence either way, and it lists every install regardless of how it was delivered.' }
        default  { 'Windows Update is not policy-restricted on this host.' }
    }

    $deliveryBlock = [ordered]@{
        mode           = $mode
        explanation    = $modeExplanation
        services       = @($svcState)
        wsusServer     = $wuServer
        wsusTargetGroup = $targetGroup
        noAutoUpdate   = $noAutoUpdate
        useWuServer    = $useWuServer
        auOptions      = $auOptions
        agentResults   = @($agentResults)
    }

    # ------------------------------------------------------- 3. Defender defs
    $sigPath = 'HKLM:\SOFTWARE\Microsoft\Windows Defender\Signature Updates'
    $sigRoot = $null
    try { $sigRoot = Get-ItemProperty -Path $sigPath -ErrorAction Stop } catch { }

    $defenderSvc = $svcState | Where-Object { $_.name -eq 'WinDefend' } | Select-Object -First 1
    $defPresent = $defenderSvc -and $defenderSvc.status -ne 'absent'

    $defs = @()
    if ($sigRoot) {
        $defSpecs = @(
            [pscustomobject]@{ key = 'AV';  label = 'Antivirus';        ver = 'AVSignatureVersion';  applied = 'AVSignatureApplied' }
            [pscustomobject]@{ key = 'AS';  label = 'Antispyware';      ver = 'ASSignatureVersion';  applied = 'ASSignatureApplied' }
            [pscustomobject]@{ key = 'NIS'; label = 'Network Inspection'; ver = 'NISSignatureVersion'; applied = 'NISSignatureApplied' }
        )
        foreach ($spec in $defSpecs) {
            $ver = $sigRoot.($spec.ver)
            if (-not $ver) { continue }
            $applied = ConvertFrom-FileTimeBytes $sigRoot.($spec.applied)
            $defs += [pscustomobject]@{
                type       = $spec.key
                label      = $spec.label
                version    = $ver
                appliedOn  = if ($applied) { $applied.ToString('o') } else { $null }
                ageDays    = Get-AgeDays $applied
            }
        }
    }

    $lastUpdated = if ($sigRoot) { ConvertFrom-FileTimeBytes $sigRoot.SignaturesLastUpdated } else { $null }

    # Get-MpComputerStatus is the nicer source but throws an opaque "extrinsic
    # Method could not be executed" whenever WinDefend isn't running (common on
    # VPU images) -- so it is strictly a bonus on top of the registry read.
    $mp = $null
    try { $mp = Get-MpComputerStatus -ErrorAction Stop } catch { }

    # Dated definition-update history. This is the list a school's IT wants:
    # every definition version that landed, with the date it was applied.
    $defHistory = @()
    $defLogNote = $null
    try {
        $defEvents = Get-WinEvent -FilterHashtable @{
            LogName = 'Microsoft-Windows-Windows Defender/Operational'; Id = 2000, 2001, 2002
        } -MaxEvents $MaxDefenderEvents -ErrorAction Stop
        foreach ($e in $defEvents) {
            $msg = if ($e.Message) { $e.Message } else { '' }
            $cur = Get-MessageField $msg 'Current Signature Version'
            $prev = Get-MessageField $msg 'Previous Signature Version'
            $sigType = Get-MessageField $msg 'Signature Type'
            $updType = Get-MessageField $msg 'Update Type'
            $curEng = Get-MessageField $msg 'Current Engine Version'
            $outcome = switch ($e.Id) {
                2000 { 'applied' }
                2001 { 'failed' }
                2002 { 'engine-updated' }
                default { 'unknown' }
            }
            $defHistory += [pscustomobject]@{
                appliedOn       = $e.TimeCreated.ToString('o')
                eventId         = $e.Id
                outcome         = $outcome
                signatureType   = $sigType
                version         = $cur
                previousVersion = $prev
                updateType      = $updType
                engineVersion   = $curEng
            }
        }
    } catch {
        # An empty/absent Defender log is the norm on an image where Defender
        # was disabled at deployment -- say so instead of reporting an error.
        $defLogNote = 'No Microsoft Defender Operational log entries are available on this host.'
    }

    $defHistory = @($defHistory | Sort-Object -Property @{ Expression = { [DateTime]$_.appliedOn } } -Descending)

    $sigAge = Get-AgeDays $lastUpdated
    $defStatus = 'unknown'
    if (-not $defPresent) { $defStatus = 'absent' }
    elseif ($defenderSvc.status -ne 'Running') { $defStatus = 'disabled' }
    elseif ($null -eq $sigAge) { $defStatus = 'unknown' }
    elseif ($sigAge -le 7) { $defStatus = 'current' }
    elseif ($sigAge -le 30) { $defStatus = 'aging' }
    else { $defStatus = 'stale' }

    $defenderBlock = [ordered]@{
        status             = $defStatus
        present            = $defPresent
        serviceStatus      = if ($defenderSvc) { $defenderSvc.status } else { 'absent' }
        serviceStartType   = if ($defenderSvc) { $defenderSvc.startType } else { $null }
        engineVersion      = if ($sigRoot -and $sigRoot.EngineVersion) { $sigRoot.EngineVersion } elseif ($mp) { $mp.AMEngineVersion } else { $null }
        platformVersion    = if ($mp) { $mp.AMProductVersion } else { $null }
        lastUpdated        = if ($lastUpdated) { $lastUpdated.ToString('o') } else { $null }
        lastUpdatedAgeDays = $sigAge
        realTimeProtection = if ($mp) { [bool]$mp.RealTimeProtectionEnabled } else { $null }
        definitions        = @($defs)
        history            = @($defHistory)
        historyNote        = $defLogNote
    }

    # -------------------------------------------------------- 4. OS updates
    $driversExcluded = 0
    $rows = @()

    # 4a. QFE inventory (Get-HotFix). Description carries the class:
    # Security Update / Update / Hotfix / Service Pack.
    try {
        $hotfixes = Get-HotFix -ErrorAction Stop
        foreach ($h in $hotfixes) {
            $desc = if ($h.Description) { [string]$h.Description } else { '' }
            if (Test-IsDriverPackage $desc) { $driversExcluded++; continue }
            $installed = $null
            try { if ($h.InstalledOn) { $installed = ([DateTime]$h.InstalledOn).ToString('o') } } catch { }
            $rows += [pscustomobject]@{
                kb          = [string]$h.HotFixID
                title       = $null   # Description is the class; it lands in `kind`
                kind        = if ($desc) { $desc } else { 'Update' }
                installedOn = $installed
                installedBy = [string]$h.InstalledBy
                source      = 'QFE inventory'
                package     = $null
            }
        }
    } catch { }

    # 4b. Servicing timeline (Setup log, Microsoft-Windows-Servicing id 2).
    # This is what catches an offline wusa/DISM install the WU agent never saw
    # -- the evidence that matters on a WU-disabled VPU.
    $servicingNote = $null
    try {
        $servicing = Get-WinEvent -FilterHashtable @{
            LogName = 'Setup'; ProviderName = 'Microsoft-Windows-Servicing'; Id = 2
        } -MaxEvents 400 -ErrorAction Stop
        foreach ($e in $servicing) {
            $msg = if ($e.Message) { $e.Message } else { '' }
            $pkg = if ($msg -match 'Package\s+(\S+?)\s+was') { $Matches[1] } else { $null }
            $probe = if ($pkg) { $pkg } else { $msg }
            if (Test-IsDriverPackage $probe) { $driversExcluded++; continue }
            $kb = if ($probe -match '(KB\d{6,7})') { $Matches[1] } else { $null }
            $title = if ($pkg) { $pkg } else { $msg.Substring(0, [Math]::Min(90, $msg.Length)) }
            if ($kb -and $title -eq $kb) { $title = $null }
            $rows += [pscustomobject]@{
                kb          = $kb
                title       = $title
                kind        = 'Servicing package'
                installedOn = $e.TimeCreated.ToString('o')
                installedBy = $null
                source      = 'Setup log (servicing)'
                package     = $pkg
            }
        }
    } catch {
        $servicingNote = 'The Setup event log holds no servicing records on this host (it may have rolled over).'
    }

    # Failed install attempts -- the other half of the story. Setup log id 3
    # is a CBS package change that FAILED; System log WindowsUpdateClient id 20
    # is a WU-agent install failure. Zero failures alongside a sparse success
    # record means updates were never attempted, not attempted and blocked --
    # the distinction the whole vendor conversation turns on.
    $failRows = @()
    $svcFailCount = 0
    try {
        $svcFails = Get-WinEvent -FilterHashtable @{
            LogName = 'Setup'; ProviderName = 'Microsoft-Windows-Servicing'; Id = 3
        } -MaxEvents 50 -ErrorAction Stop
        $svcFailCount = @($svcFails).Count
        foreach ($e in $svcFails | Select-Object -First 10) {
            $msg = if ($e.Message) { $e.Message } else { '' }
            $kb = if ($msg -match '(KB\d{6,7})') { $Matches[1] } else { $null }
            $failRows += [pscustomobject]@{
                when   = $e.TimeCreated.ToString('o')
                kb     = $kb
                source = 'Setup log (servicing failure)'
                detail = $msg.Substring(0, [Math]::Min(120, $msg.Length))
            }
        }
    } catch { }
    $wuFailCount = 0
    try {
        $wuFails = Get-WinEvent -FilterHashtable @{
            LogName = 'System'; ProviderName = 'Microsoft-Windows-WindowsUpdateClient'; Id = 20
        } -MaxEvents 50 -ErrorAction Stop
        $wuFailCount = @($wuFails).Count
        foreach ($e in $wuFails | Select-Object -First 10) {
            $msg = if ($e.Message) { $e.Message } else { '' }
            $kb = if ($msg -match '(KB\d{6,7})') { $Matches[1] } else { $null }
            $failRows += [pscustomobject]@{
                when   = $e.TimeCreated.ToString('o')
                kb     = $kb
                source = 'WU agent (install failure)'
                detail = ($msg -split "`r?`n")[0].Trim()
            }
        }
    } catch { }
    $failuresBlock = [ordered]@{
        servicingFailures = $svcFailCount
        wuFailures        = $wuFailCount
        recent            = @($failRows | Sort-Object -Property @{ Expression = { [DateTime]$_.when } } -Descending)
    }

    # Merge: one row per KB, keeping the earliest recorded install date (the
    # servicing event is the actual install; QFE re-dates on some images) and
    # the richer title. Rows with no KB (unnamed servicing packages) stay as-is.
    $keyed = @{}
    $unkeyed = @()
    foreach ($r in $rows) {
        if (-not $r.kb) { $unkeyed += $r; continue }
        $k = $r.kb.ToUpper()
        if (-not $keyed.ContainsKey($k)) {
            $keyed[$k] = $r
        } else {
            $existing = $keyed[$k]
            $merged = [pscustomobject]@{
                kb          = $k
                title       = if ($existing.title) { $existing.title } else { $r.title }
                kind        = if ($existing.kind -and $existing.kind -ne 'Servicing package') { $existing.kind } else { $r.kind }
                installedOn = if ($existing.source -like 'Setup log*' -and $existing.installedOn) { $existing.installedOn }
                              elseif ($r.source -like 'Setup log*' -and $r.installedOn) { $r.installedOn }
                              elseif ($existing.installedOn) { $existing.installedOn }
                              else { $r.installedOn }
                installedBy = if ($existing.installedBy) { $existing.installedBy } else { $r.installedBy }
                source      = if ($existing.source -eq $r.source) { $existing.source } else { 'QFE inventory + Setup log' }
                package     = if ($existing.package) { $existing.package } else { $r.package }
            }
            $keyed[$k] = $merged
        }
    }

    # $keyed.Values are pscustomobjects, so Sort-Object can see the properties.
    $allRows = @()
    $allRows += $keyed.Values
    $allRows += $unkeyed
    $sorted = @($allRows | Sort-Object -Property @{ Expression = { if ($_.installedOn) { [DateTime]$_.installedOn } else { [DateTime]'1601-01-01' } } } -Descending)
    $capped = @($sorted | Select-Object -First $MaxUpdates)

    $securityRows = @($sorted | Where-Object { $_.kind -match '(?i)security' })
    $securityCount = $securityRows.Count
    $lastSecurity = $securityRows | Where-Object { $_.installedOn } | Select-Object -First 1
    $lastSecurityOn = if ($lastSecurity) { $lastSecurity.installedOn } else { $null }
    $lastSecurityAge = if ($lastSecurityOn) { Get-AgeDays ([DateTime]$lastSecurityOn) } else { $null }
    $newest = $sorted | Where-Object { $_.installedOn } | Select-Object -First 1
    $lastUpdateOn = if ($newest) { $newest.installedOn } else { $null }
    $lastUpdateAge = $null
    if ($lastUpdateOn) { $lastUpdateAge = Get-AgeDays ([DateTime]$lastUpdateOn) }

    $updatesBlock = [ordered]@{
        count             = $sorted.Count
        returned          = $capped.Count
        securityCount     = $securityCount
        driversExcluded   = $driversExcluded
        lastInstalledOn   = $lastUpdateOn
        lastInstalledAgeDays = $lastUpdateAge
        lastSecurityInstalledOn = $lastSecurityOn
        lastSecurityAgeDays = $lastSecurityAge
        servicingNote     = $servicingNote
        failures          = $failuresBlock
        items             = @($capped)
    }

    # ------------------------------------------------------ 5. Pending reboot
    $pendingReasons = @()
    if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') {
        $pendingReasons += 'Component Based Servicing has a reboot pending'
    }
    if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired') {
        $pendingReasons += 'Windows Update flagged a required reboot'
    }
    $pfro = Get-RegValue 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' 'PendingFileRenameOperations'
    if ($pfro) { $pendingReasons += 'Files are queued to be replaced on next boot' }

    $pendingBlock = [ordered]@{
        isPending = ($pendingReasons.Count -gt 0)
        reasons   = @($pendingReasons)
    }

    # Score the posture on the newest SECURITY update, not on any servicing
    # activity. Measured on the disputed unit (Rochelle TX): its newest install
    # was KB4486153 -- the .NET Framework 4.8 runtime, installed by the Pixellot
    # account in 2023 because their own software needed it. Scoring off that
    # reported "3.2 years" for a box whose last actual security content was the
    # January 2019 cumulative. A runtime install is not a patch.
    $postureBasis = 'none'
    $postureAge = $null
    if ($null -ne $lastSecurityAge) {
        $postureBasis = 'security-update'
        $postureAge = $lastSecurityAge
    } elseif ($null -ne $lastUpdateAge) {
        $postureBasis = 'any-update'
        $postureAge = $lastUpdateAge
    }

    $postureLevel = 'unknown'
    if ($null -ne $postureAge) {
        if ($postureAge -le 120) { $postureLevel = 'current' }
        elseif ($postureAge -le 400) { $postureLevel = 'aging' }
        else { $postureLevel = 'stale' }
    } elseif ($sorted.Count -eq 0) {
        $postureLevel = 'stale'
    }
    # -- Other security controls. The report asserts "no control in force";
    # that claim is only defensible if we actually looked for controls beyond
    # Defender. SecurityCenter2 lists every REGISTERED antivirus product
    # (third-party AV included); the firewall profiles are a real host control
    # a district reviewer will ask about either way.
    $scProducts = @()
    $scAvailable = $false
    try {
        $avs = Get-CimInstance -Namespace 'root/SecurityCenter2' -ClassName AntiVirusProduct -ErrorAction Stop
        $scAvailable = $true
        foreach ($av in $avs) {
            # productState middle byte: 0x10 bit set = product enabled. The
            # widely used SecurityCenter2 decode; kept alongside the raw value
            # so a wrong guess is auditable.
            $state = [uint32]$av.productState
            $mid = ($state -shr 8) -band 0xFF
            $scProducts += [pscustomobject]@{
                displayName  = [string]$av.displayName
                productState = $state
                enabled      = (($mid -band 0x10) -ne 0)
                isDefender   = ([string]$av.displayName -match '(?i)defender')
            }
        }
    } catch { }

    $fwProfiles = @()
    try {
        foreach ($fp in (Get-NetFirewallProfile -ErrorAction Stop)) {
            $fwProfiles += [pscustomobject]@{
                name    = [string]$fp.Name
                enabled = ($fp.Enabled.ToString() -eq 'True')
            }
        }
    } catch { }

    # Was Defender switched off ON PURPOSE? The policy key proves image-level
    # intent; without it "disabled" could be read as breakage.
    $disableAsPolicy = Get-RegValue 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender' 'DisableAntiSpyware'
    $disableAsLocal  = Get-RegValue 'HKLM:\SOFTWARE\Microsoft\Windows Defender' 'DisableAntiSpyware'
    $defenderBlock['disabledByPolicy'] = (($disableAsPolicy -eq 1) -or ($disableAsLocal -eq 1))

    $controlsBlock = [ordered]@{
        firewallProfiles      = @($fwProfiles)
        securityCenterChecked = $scAvailable
        antivirusProducts     = @($scProducts)
    }

    $defenderActive = ($defStatus -eq 'current' -or $defStatus -eq 'aging')
    $thirdPartyAv = @($scProducts | Where-Object { (-not $_.isDefender) -and $_.enabled })
    $avActive = $defenderActive -or ($thirdPartyAv.Count -gt 0)
    $osPatched = ($postureLevel -eq 'current')
    $securityControl =
        if ($osPatched -and $avActive) { 'os-patching+av' }
        elseif ($osPatched) { 'os-patching' }
        elseif ($avActive) { 'av' }
        else { 'none' }

    $postureBlock = [ordered]@{
        level                   = $postureLevel
        basis                   = $postureBasis
        ageDays                 = $postureAge
        securityControl         = $securityControl
        lastUpdateAgeDays       = $lastUpdateAge
        lastSecurityInstalledOn = $lastSecurityOn
        lastSecurityAgeDays     = $lastSecurityAge
        defenderActive          = $defenderActive
        thirdPartyAvActive      = ($thirdPartyAv.Count -gt 0)
    }

    $dotNetRelease = Get-RegValue 'HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full' 'Release'
    $dotNetVersion = if ($null -eq $dotNetRelease) { $null }
        elseif ($dotNetRelease -ge 533320) { '4.8.1' }
        elseif ($dotNetRelease -ge 528040) { '4.8' }
        elseif ($dotNetRelease -ge 461808) { '4.7.2' }
        elseif ($dotNetRelease -ge 461308) { '4.7.1' }
        elseif ($dotNetRelease -ge 460798) { '4.7' }
        elseif ($dotNetRelease -ge 394802) { '4.6.2' }
        else { "release $dotNetRelease" }

    [ordered]@{
        collectedAt   = (Get-Date).ToString('o')
        elevated      = $isAdmin
        os            = $osBlock
        dotNet        = [ordered]@{ version = $dotNetVersion; release = $dotNetRelease }
        controls      = $controlsBlock
        posture       = $postureBlock
        delivery      = $deliveryBlock
        defender      = $defenderBlock
        updates       = $updatesBlock
        pendingReboot = $pendingBlock
    } | ConvertTo-Json -Depth 6 -Compress
}
catch {
    [ordered]@{
        error   = $true
        message = $_.Exception.Message
        script  = 'Get-PatchCompliance.ps1'
    } | ConvertTo-Json -Compress
}
