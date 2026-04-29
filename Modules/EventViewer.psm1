# =============================================================================
#  EventViewer.psm1  —  Event Viewer panel
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

    $since = (Get-Date).AddHours(-$EvtHours)
    $totalErrors = 0; $totalWarns = 0

    foreach ($logName in @("System","Application")) {
        if ($sync.EvtCancelled) { break }
        $sync.EvtStep = "Reading $logName events..."
        Evt-Section $logName
        try {
            $evts = @(Get-EventLog -LogName $logName -EntryType Error,Warning -After $since -Newest 100 -ErrorAction Stop)
            $errs = @($evts | Where-Object { $_.EntryType -eq "Error" })
            $wrns = @($evts | Where-Object { $_.EntryType -eq "Warning" })
            $totalErrors += $errs.Count; $totalWarns += $wrns.Count
            if ($evts.Count -eq 0) {
                Evt-Log "Last ${EvtHours}h" "No errors or warnings" "Pass"
            } else {
                Evt-Log "Errors (last ${EvtHours}h)"   "$($errs.Count)" $(if($errs.Count-gt0){"Fail"}else{"Pass"})
                Evt-Log "Warnings (last ${EvtHours}h)" "$($wrns.Count)" $(if($wrns.Count-gt20){"Warn"}else{"Info"})
                foreach ($ev in ($errs | Select-Object -First 10)) {
                    if ($sync.EvtCancelled) { break }
                    $msg = (($ev.Message -split "`n")[0] -replace '\s+',' ').Trim()
                    if ($msg.Length -gt 72) { $msg = $msg.Substring(0,69)+"..." }
                    Evt-Log "$($ev.TimeGenerated.ToString('MM/dd HH:mm'))  $($ev.Source)" $msg "Fail"
                }
                foreach ($ev in ($wrns | Select-Object -First 5)) {
                    if ($sync.EvtCancelled) { break }
                    $msg = (($ev.Message -split "`n")[0] -replace '\s+',' ').Trim()
                    if ($msg.Length -gt 72) { $msg = $msg.Substring(0,69)+"..." }
                    Evt-Log "$($ev.TimeGenerated.ToString('MM/dd HH:mm'))  $($ev.Source)" $msg "Warn"
                }
            }
        } catch { Evt-Log $logName "Error reading event log" "Warn" }
    }

    $sync.Cards["EvtStatus"] = @{
        Value  = if($totalErrors-gt0){"$totalErrors errors"}elseif($totalWarns-gt0){"$totalWarns warns"}else{"Clean"}
        Status = if($totalErrors-gt0){"fail"}elseif($totalWarns-gt20){"warn"}else{"ok"}
    }
    $sync.EvtStep = "Complete"; $sync.EvtRunning=$false; $sync.EvtComplete=$true
}


# ---------- Event Viewer timer -----------------------------------------------
$evtTimer = New-Object System.Windows.Forms.Timer; $evtTimer.Interval = 300
$evtTimer.Add_Tick({
    $evtItem = $null
    while ($sync.EvtQueue.TryDequeue([ref]$evtItem)) {
        if ($evtItem.L -eq "Section") {
            $rtbEvtLog.SelectionStart=$rtbEvtLog.TextLength;$rtbEvtLog.SelectionLength=0
            $rtbEvtLog.SelectionFont=New-Object System.Drawing.Font("Consolas",7.5,[System.Drawing.FontStyle]::Bold)
            $rtbEvtLog.SelectionColor=[System.Drawing.Color]::FromArgb(100,116,139)
            $rtbEvtLog.AppendText("`n  $($evtItem.Result.ToUpper())`n")
        } else {
            $rtbEvtLog.SelectionStart=$rtbEvtLog.TextLength;$rtbEvtLog.SelectionLength=0
            $rtbEvtLog.SelectionColor=[System.Drawing.Color]::FromArgb(100,116,139)
            $rtbEvtLog.SelectionFont=New-Object System.Drawing.Font("Consolas",8)
            $rtbEvtLog.AppendText(("{0,-26}" -f $evtItem.Label))
            $col = switch ($evtItem.L) { "Pass"{[System.Drawing.Color]::FromArgb(74,222,128)} "Fail"{[System.Drawing.Color]::FromArgb(252,165,165)} "Warn"{[System.Drawing.Color]::FromArgb(253,224,71)} "Gray"{[System.Drawing.Color]::FromArgb(100,116,139)} default{[System.Drawing.Color]::FromArgb(203,213,225)} }
            $rtbEvtLog.SelectionStart=$rtbEvtLog.TextLength;$rtbEvtLog.SelectionLength=0
            $rtbEvtLog.SelectionColor=$col; $rtbEvtLog.SelectionFont=New-Object System.Drawing.Font("Consolas",8)
            $rtbEvtLog.AppendText("$($evtItem.Result)`n")
        }
        $rtbEvtLog.ScrollToCaret()
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
        $btnEvtRun.Enabled=$true; $btnEvtRun.Text=[char]0x25B6+"  Check Event Log"
        $lblEvtStatus.ForeColor=$ColMuted; $lblEvtStatus.Text="  $($sync.EvtStep)"
    }
})


# ---- Event Viewer Panel ----------------------------------------------------
$pnlEvents = New-Object System.Windows.Forms.Panel
$pnlEvents.Size = New-Object System.Drawing.Size($WideW,$ContentH)
$pnlEvents.Location = New-Object System.Drawing.Point($SideW,$HdrH)
$pnlEvents.BackColor = $ColBg; $pnlEvents.Visible = $false; $pnlEvents.Anchor = $AnchorTLRB
$form.Controls.Add($pnlEvents)
$lblEvtTitle = New-Object System.Windows.Forms.Label; $lblEvtTitle.Text = "Event Viewer"
$lblEvtTitle.Font = New-Object System.Drawing.Font("Segoe UI Semibold",12); $lblEvtTitle.ForeColor = $ColText
$lblEvtTitle.Location = New-Object System.Drawing.Point(10,16); $lblEvtTitle.AutoSize = $true
$pnlEvents.Controls.Add($lblEvtTitle)
$lblEvtSub = New-Object System.Windows.Forms.Label
$lblEvtSub.Text = "Recent errors and warnings from the System and Application Windows event logs (last 24 hours)."
$lblEvtSub.Font = New-Object System.Drawing.Font("Segoe UI",8.5); $lblEvtSub.ForeColor = $ColMuted
$lblEvtSub.Location = New-Object System.Drawing.Point(10,42); $lblEvtSub.Size = New-Object System.Drawing.Size(762,18)
$pnlEvents.Controls.Add($lblEvtSub)
$evtCardDefs = @(
    @{ Key="EvtStatus"; Title="Event Status"; Sub="Errors / warnings (24h)"; X=10; Icon=[char]0xE7BA; W=280 }
)
$evtCards = @{}
foreach ($cd in $evtCardDefs) {
    $c = New-StatusCard -Title $cd.Title -X $cd.X -Y 68 -Icon $cd.Icon -Sub $cd.Sub -CardW $cd.W -CardH 90
    $evtCards[$cd.Key] = $c; $pnlEvents.Controls.Add($c.Panel)
}
$btnEvtRun = New-Object System.Windows.Forms.Button; $btnEvtRun.Text = [char]0x25B6 + "  Check Event Log"
$btnEvtRun.Size = New-Object System.Drawing.Size(220,40); $btnEvtRun.Location = New-Object System.Drawing.Point(10,170)
$btnEvtRun.BackColor = $ColAccent; $btnEvtRun.ForeColor = [System.Drawing.Color]::White
$btnEvtRun.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat; $btnEvtRun.FlatAppearance.BorderSize = 0
$btnEvtRun.Font = New-Object System.Drawing.Font("Segoe UI Semibold",10)
$btnEvtRun.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft; $btnEvtRun.Cursor = [System.Windows.Forms.Cursors]::Hand
$pnlEvents.Controls.Add($btnEvtRun)
$btnEvtRun.Region = New-Object System.Drawing.Region([GfxHelper]::RoundedRect((New-Object System.Drawing.Rectangle(0,0,220,40)),6))
$btnEvtCancel = New-Object System.Windows.Forms.Button; $btnEvtCancel.Text = "Cancel"
$btnEvtCancel.Size = New-Object System.Drawing.Size(100,40); $btnEvtCancel.Location = New-Object System.Drawing.Point(238,170)
$btnEvtCancel.BackColor = $ColRed; $btnEvtCancel.ForeColor = [System.Drawing.Color]::White
$btnEvtCancel.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat; $btnEvtCancel.FlatAppearance.BorderSize = 0
$btnEvtCancel.Font = New-Object System.Drawing.Font("Segoe UI",10); $btnEvtCancel.Cursor = [System.Windows.Forms.Cursors]::Hand; $btnEvtCancel.Visible = $false
$pnlEvents.Controls.Add($btnEvtCancel)
$btnEvtCancel.Region = New-Object System.Drawing.Region([GfxHelper]::RoundedRect((New-Object System.Drawing.Rectangle(0,0,100,40)),6))
$lblEvtStatus = New-Object System.Windows.Forms.Label; $lblEvtStatus.Text = ""
$lblEvtStatus.Font = New-Object System.Drawing.Font("Consolas",8); $lblEvtStatus.ForeColor = $ColMuted
$lblEvtStatus.Location = New-Object System.Drawing.Point(10,218); $lblEvtStatus.Size = New-Object System.Drawing.Size(762,18)
$pnlEvents.Controls.Add($lblEvtStatus)
$lblEvtLogHdr = New-Object System.Windows.Forms.Label; $lblEvtLogHdr.Text = "Event Log"
$lblEvtLogHdr.Font = New-Object System.Drawing.Font("Segoe UI Semibold",10); $lblEvtLogHdr.ForeColor = $ColText
$lblEvtLogHdr.Location = New-Object System.Drawing.Point(10,242); $lblEvtLogHdr.AutoSize = $true
$pnlEvents.Controls.Add($lblEvtLogHdr)
$rtbEvtLog = New-Object System.Windows.Forms.RichTextBox
$rtbEvtLog.Size = New-Object System.Drawing.Size(762,422); $rtbEvtLog.Location = New-Object System.Drawing.Point(10,266)
$rtbEvtLog.BackColor = $ColLogBg; $rtbEvtLog.ForeColor = [System.Drawing.Color]::FromArgb(203,213,225)
$rtbEvtLog.Font = New-Object System.Drawing.Font("Consolas",8); $rtbEvtLog.ReadOnly = $true
$rtbEvtLog.BorderStyle = [System.Windows.Forms.BorderStyle]::None
$rtbEvtLog.ScrollBars = [System.Windows.Forms.RichTextBoxScrollBars]::Vertical; $rtbEvtLog.Anchor = $AnchorTLRB
$rtbEvtLog.Text = "Click 'Check Event Log' to begin."
$pnlEvents.Controls.Add($rtbEvtLog)
$script:evtRunspace = $null; $script:evtSpinIdx = 0


$btnEvtRun.Add_Click({
    if ($sync.EvtRunning) { return }
    $sync.EvtCancelled = $false
    $sync.Cards["EvtStatus"] = @{ Value="--"; Status="neutral" }
    foreach ($key in $evtCards.Keys) { Update-CardStatus -Card $evtCards[$key] -Value "--" -Status "neutral" }
    $rtbEvtLog.Clear(); $btnEvtRun.Enabled=$false; $btnEvtRun.Text="  Running..."
    $btnEvtCancel.Visible=$true; $script:evtSpinIdx=0
    $lblEvtStatus.ForeColor=$ColAccent; $lblEvtStatus.Text=" |  Starting..."
    if ($script:evtRunspace) { try { $script:evtRunspace.Close() } catch { } }
    $script:evtRunspace = [runspacefactory]::CreateRunspace()
    $script:evtRunspace.ApartmentState="STA"; $script:evtRunspace.ThreadOptions="ReuseThread"; $script:evtRunspace.Open()
    $ps = [powershell]::Create(); $ps.Runspace=$script:evtRunspace
    $ps.AddScript($EvtScript) | Out-Null
    $ps.AddParameters(@{ sync=$sync; EvtHours=24 }) | Out-Null
    $ps.BeginInvoke() | Out-Null; $evtTimer.Start()
})
$btnEvtCancel.Add_Click({ $sync.EvtCancelled=$true; $btnEvtCancel.Visible=$false })

