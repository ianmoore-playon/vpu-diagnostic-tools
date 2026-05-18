# =============================================================================
#  EventLogs.psm1  -  Event Logs panel
# =============================================================================

# ---------- Event Viewer background script -----------------------------------
$EvtScript = {
    param($sync, [int]$EvtHours=24)
    $sync.EvtRunning = $true; $sync.EvtComplete = $false; $sync.EvtCancelled = $false
    $item = $null; while ($sync.EvtQueue.TryDequeue([ref]$item)) { }
    function Evt-Log { param([string]$Label,[string]$Result,[string]$Level="Info")
        $sync.EvtQueue.Enqueue(@{ Label=$Label; Result=$Result; L=$Level }) }
    function Evt-Section { param([string]$Title)
        $sync.EvtQueue.Enqueue(@{ Label=""; Result=$Title; L="Section" }) }

    # Provider-name → category map. Used to classify event sources into actionable
    # buckets so agents can tell at a glance whether errors are hardware (Disk/Driver)
    # vs software (Service/App). The wildcard match is on the ProviderName from the
    # Windows event log (e.g. "Microsoft-Windows-DistributedCOM", "disk", "Service Control Manager").
    function Get-EvtCategory {
        param([string]$ProviderName)
        $p = $ProviderName.ToLower()
        if ($p -match '^(disk|ntfs|volsnap|volmgr|partmgr|storahci|storport|storvsc|fvevol|hidserv|usbstor)') { return "Disk" }
        if ($p -match '(driver|wudfrd|cdrom|usb|hid|netbt|tcpip|bowser|netio|smb|kernel)') { return "Driver" }
        if ($p -match '(service control manager|wininit|usermodepowerservice|securitycenter|workstation|server|browser|w32time|spooler)') { return "Service" }
        if ($p -match '(application|application error|\.net|wer|sidebyside|esent|user profile|appx|search|setup|distributedcom|wmi)') { return "App" }
        if ($p -match '(network|tcpip|netbt|dhcp|dnsapi|netio|nlasvc|wlan|wifi)') { return "Network" }
        return "Other"
    }

    $since = (Get-Date).AddHours(-$EvtHours)
    $totalErrors = 0; $totalWarns = 0
    # Per-category error/warn tallies for the card label
    $catTotals = @{ Disk = 0; Driver = 0; Service = 0; App = 0; Network = 0; Other = 0 }
    # D15 fix: track whether any log read actually failed, so the card surfaces
    # "Log unreadable" instead of falsely-clean.
    $evtReadFailed = $false
    $evtReadErr    = ""

    foreach ($logName in @("System","Application")) {
        if ($sync.EvtCancelled) { break }
        $sync.EvtStep = "Reading $logName events..."
        Evt-Section $logName
        try {
            $evts = @(Get-WinEvent -FilterHashtable @{ LogName=$logName; Level=@(1,2,3); StartTime=$since } -MaxEvents 100 -ErrorAction Stop)
            $errs = @($evts | Where-Object { $_.Level -in @(1,2) })
            $wrns = @($evts | Where-Object { $_.Level -eq 3 })
            $totalErrors += $errs.Count; $totalWarns += $wrns.Count

            # Tally by category for the summary card
            foreach ($e in $errs) {
                $cat = Get-EvtCategory -ProviderName $e.ProviderName
                $catTotals[$cat] = $catTotals[$cat] + 1
            }

            if ($evts.Count -eq 0) {
                Evt-Log "Last ${EvtHours}h" "No errors or warnings" "Pass"
            } else {
                Evt-Log "Errors (last ${EvtHours}h)"   "$($errs.Count)" $(if($errs.Count -gt 0){"Fail"}else{"Pass"})
                Evt-Log "Warnings (last ${EvtHours}h)" "$($wrns.Count)" $(if($wrns.Count -gt 0){"Warn"}else{"Info"})
                foreach ($ev in ($errs | Select-Object -First 20)) {
                    if ($sync.EvtCancelled) { break }
                    $msg = (($ev.Message -split "`n")[0] -replace '\s+',' ').Trim()
                    if ($msg.Length -gt 64) { $msg = $msg.Substring(0,61)+"..." }
                    $cat = Get-EvtCategory -ProviderName $ev.ProviderName
                    Evt-Log "$($ev.TimeCreated.ToString('MM/dd HH:mm'))  [$cat] $($ev.ProviderName)" $msg "Fail"
                }
                foreach ($ev in ($wrns | Select-Object -First 10)) {
                    if ($sync.EvtCancelled) { break }
                    $msg = (($ev.Message -split "`n")[0] -replace '\s+',' ').Trim()
                    if ($msg.Length -gt 64) { $msg = $msg.Substring(0,61)+"..." }
                    $cat = Get-EvtCategory -ProviderName $ev.ProviderName
                    Evt-Log "$($ev.TimeCreated.ToString('MM/dd HH:mm'))  [$cat] $($ev.ProviderName)" $msg "Warn"
                }
            }
        } catch {
            $evtReadFailed = $true
            $evtReadErr    = $_.Exception.Message -replace "[\r\n]+"," "
            Evt-Log $logName "Error reading event log: $evtReadErr" "Warn"
        }
    }

    # D14 fix: severity should weight by event category, not raw count.
    # A single benign DistributedCOM 10016 used to flag the whole module Critical.
    # New rules:
    #   - Disk / Driver errors are hardware-relevant → Critical (fail)
    #   - Service / Network errors → Warning
    #   - App / Other errors alone → Warning (not Critical)
    #   - Read-failure on any log → Warning, with explicit message
    $hardwareErrCount = $catTotals["Disk"] + $catTotals["Driver"]
    $servicishCount   = $catTotals["Service"] + $catTotals["Network"]
    $appishCount      = $catTotals["App"] + $catTotals["Other"]

    # Build a category breakdown for the card label — only show non-zero categories,
    # ordered by severity-of-implication (Disk → Driver → Service → Network → App → Other)
    $catOrder = @("Disk","Driver","Service","Network","App","Other")
    $catParts = @()
    foreach ($c in $catOrder) {
        if ($catTotals[$c] -gt 0) { $catParts += "$($catTotals[$c]) $($c.ToLower())" }
    }
    if ($evtReadFailed -and $totalErrors -eq 0 -and $totalWarns -eq 0) {
        $cardValue  = "Log unreadable"
        $cardStatus = "warn"
    } elseif ($hardwareErrCount -gt 0) {
        $cardValue  = if ($catParts.Count -gt 0) { ($catParts -join " / ") } else { "$totalErrors errors" }
        $cardStatus = "fail"
    } elseif ($servicishCount -gt 0 -or $appishCount -gt 0 -or $totalWarns -gt 0) {
        $cardValue  = if ($catParts.Count -gt 0) { ($catParts -join " / ") }
                      elseif ($totalErrors -gt 0) { "$totalErrors errors" }
                      else { "$totalWarns warns" }
        $cardStatus = "warn"
    } else {
        $cardValue  = "Clean"
        $cardStatus = "ok"
    }
    $sync.Cards["EvtStatus"] = @{ Value = $cardValue; Status = $cardStatus }
    $sync.EvtStep = "Complete"; $sync.EvtRunning=$false; $sync.EvtComplete=$true
}


# ---------- Event Viewer timer -----------------------------------------------
$evtTimer = New-Object System.Windows.Forms.Timer; $evtTimer.Interval = 300
$evtTimer.Add_Tick({
    $evtItem = $null
    while ($sync.EvtQueue.TryDequeue([ref]$evtItem)) {
        Add-LogRow $dgvEvtLog $evtItem.Label $evtItem.Result $evtItem.L
    }
    foreach ($key in $evtCards.Keys) {
        $sc = $sync.Cards[$key]
        if ($sc -and $evtCards[$key].ValueLabel.Text -ne $sc.Value) { Update-CardStatus -Card $evtCards[$key] -Value $sc.Value -Status $sc.Status }
    }
    if ($sync.EvtRunning) {
        $script:evtSpinIdx=($script:evtSpinIdx+1)%4
        $lblEvtStatus.ForeColor=$ColAccent
        $lblEvtStatus.Text=" $(@('|','/','-','\')[$script:evtSpinIdx])  $($sync.EvtStep)"
    }
    if ($sync.EvtComplete -and -not $sync.EvtRunning) {
        $evtTimer.Stop(); $btnEvtCancel.Visible=$false
        $btnEvtRun.Enabled=$true; $btnEvtRun.Text=[char]0x25B6+"  Run Test"
        $lblEvtStatus.ForeColor=$ColMuted; $lblEvtStatus.Text="Last run: $(Get-Date -Format 'h:mm tt')"

        # R2: surface any runspace errors.
        $evtErrs = Get-DiagRunspaceErrors $script:evtState
        foreach ($em in $evtErrs) { Add-LogRow $dgvEvtLog "Runspace error" $em "Fail" }

        $evtC = $sync.Cards["EvtStatus"]
        $evtSt = if ($evtC) { $evtC.Status } else { "neutral" }
        Set-SectionPill $evtHeader $evtSt
        $sumItems = @()
        if ($evtC -and $evtC.Value -ne "--") {
            if ($evtSt -eq "ok") { $sumItems += @{ Status="ok"; Text="No critical errors found in recent logs" } }
            else { $sumItems += @{ Status=$evtSt; Text="Event log: $($evtC.Value)" } }
        }
        if ($sumItems.Count -eq 0) { $sumItems = @(@{ Status="neutral"; Text="No event log data collected" }) }
        Set-SummaryItems $evtSummary $sumItems
    }
})


# ---- Event Viewer Panel ----------------------------------------------------
$pnlEvents = New-Object System.Windows.Forms.Panel
$pnlEvents.Size = New-Object System.Drawing.Size($WideW,$ContentH)
$pnlEvents.Location = New-Object System.Drawing.Point($SideW,$ContentY)
$pnlEvents.BackColor = $ColBg; $pnlEvents.Visible = $false; $pnlEvents.Anchor = $AnchorTLRB
$form.Controls.Add($pnlEvents)
# v1.0.43 redesign — section header + status card + log/summary split + action bar
$evtHeader = New-SectionHeader -Parent $pnlEvents `
    -Title    "Event Viewer" `
    -Subtitle "Recent errors and warnings from the System and Application logs, categorised by source type."

$evtCardDefs = @(
    @{ Key="EvtStatus"; Title="Event Status"; Sub="Errors / warnings (24h)"; Icon=[char]0xE7BA }
)
$evtCards = @{}
$evtCardX = 28
foreach ($cd in $evtCardDefs) {
    $c = New-StatusCard -Title $cd.Title -X $evtCardX -Y 110 -Icon $cd.Icon -Sub $cd.Sub -CardW 320 -CardH 90
    $evtCards[$cd.Key] = $c
    $pnlEvents.Controls.Add($c.Panel)
    $evtCardX += 332
}

$evtLogCard = New-Object System.Windows.Forms.Panel
$evtLogCard.Size      = New-Object System.Drawing.Size(800, 460)
$evtLogCard.Location  = New-Object System.Drawing.Point(28, 220)
$evtLogCard.BackColor = $ColCard
$evtLogCard.Region    = New-Object System.Drawing.Region([GfxHelper]::RoundedRect((New-Object System.Drawing.Rectangle(0, 0, 800, 460)), 8))
$pnlEvents.Controls.Add($evtLogCard)

$lblEvtLogHdr = New-Object System.Windows.Forms.Label
$lblEvtLogHdr.Text      = "Event Log"
$lblEvtLogHdr.Font      = New-Object System.Drawing.Font("Segoe UI Semibold", 10)
$lblEvtLogHdr.ForeColor = $ColText
$lblEvtLogHdr.Location  = New-Object System.Drawing.Point(16, 12)
$lblEvtLogHdr.AutoSize  = $true
$evtLogCard.Controls.Add($lblEvtLogHdr)

$dgvEvtLog = New-LogGrid -X 8 -Y 38 -W 784 -H 414
$evtLogCard.Controls.Add($dgvEvtLog)

$evtSummary = New-SummaryPanel -Parent $pnlEvents -X 844 -Y 220 -W 420 -H 460 -Title "Summary"
Set-SummaryItems $evtSummary @(@{ Status="neutral"; Text="Run Test to populate the summary" })

$evtActions = New-ActionBar -Parent $pnlEvents -Y 698 -ExportText "Export Report" -PrimaryText ([char]0x25B6 + "  Run Test")
$btnEvtRun    = $evtActions.PrimaryBtn
$btnEvtExport = $evtActions.ExportBtn

$btnEvtCancel = New-Object System.Windows.Forms.Button
$btnEvtCancel.Text      = "Cancel"
$btnEvtCancel.Size      = New-Object System.Drawing.Size(110, 36)
$btnEvtCancel.Location  = New-Object System.Drawing.Point(168, 10)
$btnEvtCancel.BackColor = $ColRed
$btnEvtCancel.ForeColor = [System.Drawing.Color]::White
$btnEvtCancel.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnEvtCancel.FlatAppearance.BorderSize = 0
$btnEvtCancel.Font      = New-Object System.Drawing.Font("Segoe UI", 9.5)
$btnEvtCancel.Cursor    = [System.Windows.Forms.Cursors]::Hand
$btnEvtCancel.Visible   = $false
$btnEvtCancel.Region    = New-Object System.Drawing.Region([GfxHelper]::RoundedRect((New-Object System.Drawing.Rectangle(0, 0, 110, 36)), 6))
$evtActions.Bar.Controls.Add($btnEvtCancel)

$lblEvtStatus = New-Object System.Windows.Forms.Label
$lblEvtStatus.Text      = ""
$lblEvtStatus.Font      = New-Object System.Drawing.Font("Consolas", 8)
$lblEvtStatus.ForeColor = $ColMuted
$lblEvtStatus.Location  = New-Object System.Drawing.Point(28, 686)
$lblEvtStatus.Size      = New-Object System.Drawing.Size(($pnlEvents.Width - 56), 16)
$lblEvtStatus.Anchor    = $AnchorBLR
$pnlEvents.Controls.Add($lblEvtStatus)

$lblEvtEta = New-Object System.Windows.Forms.Label
$lblEvtEta.Visible = $false
$pnlEvents.Controls.Add($lblEvtEta)
$script:evtRunspace = $null; $script:evtPs = $null; $script:evtSpinIdx = 0


function Start-EvtDiagnostic {
    if ($sync.EvtRunning) { return }
    $sync.EvtCancelled = $false
    $sync.Cards["EvtStatus"] = @{ Value="--"; Status="neutral" }
    foreach ($key in $evtCards.Keys) { Update-CardStatus -Card $evtCards[$key] -Value "--" -Status "neutral" }
    $dgvEvtLog.Rows.Clear(); $btnEvtRun.Enabled=$false; $btnEvtRun.Text="  Running..."
    $btnEvtCancel.Visible=$true; $script:evtSpinIdx=0
    $lblEvtStatus.ForeColor=$ColAccent; $lblEvtStatus.Text=" |  Starting..."
    # R2/R13: see DiskHealth.psm1 for rationale.
    $script:evtState = Start-DiagRunspace `
        -Script    $EvtScript `
        -Parameters @{ sync = $sync; EvtHours = 24 } `
        -Previous   $script:evtState
    $script:evtRunspace = $script:evtState.Runspace
    $script:evtPs       = $script:evtState.Ps
    $evtTimer.Start()
}

$btnEvtRun.Add_Click({ Start-EvtDiagnostic })
$btnEvtCancel.Add_Click({ $sync.EvtCancelled=$true; $btnEvtCancel.Visible=$false })

