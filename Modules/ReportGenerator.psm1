# =============================================================================
#  ReportGenerator.psm1  -  Run History panel
# =============================================================================

function Update-HistoryList {
    $lvHistory.Items.Clear()
    $files = @(Get-ChildItem -Path $OutputDir -Filter "Pulse_Results_*.txt" -ErrorAction SilentlyContinue |
               Sort-Object LastWriteTime -Descending)
    if ($files.Count -eq 0) {
        $empty = New-Object System.Windows.Forms.ListViewItem("No history yet")
        $empty.ForeColor = $ColMuted
        $empty.SubItems.Add("") | Out-Null
        $empty.SubItems.Add("Run a diagnostic from the Overview tab to generate history.") | Out-Null
        $empty.SubItems.Add("") | Out-Null
        $lvHistory.Items.Add($empty) | Out-Null
        return
    }
    foreach ($f in $files) {
        $dt = $f.LastWriteTime
        if ($f.Name -match '_(\d{8})_(\d{6})\.txt$') {
            try { $dt = [datetime]::ParseExact("$($Matches[1])$($Matches[2])", "yyyyMMddHHmmss", $null) } catch { }
        }
        $resultText = "Unknown"; $resultColor = $ColMuted; $summary = ""
        try {
            $lines = Get-Content -Path $f.FullName -Tail 100 -ErrorAction Stop
            $statusLine = $lines | Where-Object { $_ -match '^STATUS:' } | Select-Object -Last 1
            $failLines  = @($lines | Where-Object { $_ -match 'DEGRADED' })
            if ($statusLine -match 'ALL_CLEAR') {
                $resultText = "All Clear"; $resultColor = $ColGreen; $summary = "All ports healthy"
            } elseif ($statusLine -match 'ISSUES_FOUND' -or $failLines.Count -gt 0) {
                $resultText = "Issues Found"; $resultColor = $ColRed
                $ports = $failLines | ForEach-Object {
                    if ($_ -match '^\s+(.+?)\s{2,}DEGRADED') { $Matches[1].Trim() }
                } | Where-Object { $_ }
                $summary = "$($failLines.Count) fault(s)" + $(if ($ports) { " - " + ($ports -join ", ") } else { "" })
            } elseif (@($lines | Where-Object { $_ -match 'Complete' }).Count -gt 0) {
                $resultText = "All Clear"; $resultColor = $ColGreen; $summary = "All ports healthy"
            }
        } catch { }
        $sizeKb = [math]::Round($f.Length / 1KB, 1)
        $item = New-Object System.Windows.Forms.ListViewItem($dt.ToString("yyyy-MM-dd  HH:mm"))
        $item.SubItems.Add($resultText) | Out-Null
        $item.SubItems.Add($summary)    | Out-Null
        $item.SubItems.Add("$sizeKb KB") | Out-Null
        $item.ForeColor = $resultColor
        $item.BackColor = $ColCard
        $item.Tag       = $f.FullName
        $lvHistory.Items.Add($item) | Out-Null
    }
}


# ---- History Panel (embedded in Reports) -----------------------------------
$pnlHistory = New-Object System.Windows.Forms.Panel
$pnlHistory.Size     = New-Object System.Drawing.Size($WideW, $ContentH)
$pnlHistory.Location = New-Object System.Drawing.Point($SideW, $ContentY)
$pnlHistory.BackColor = $ColBg; $pnlHistory.Visible = $false
$pnlHistory.Anchor = $AnchorTLRB
$form.Controls.Add($pnlHistory)

$lblHistTitle = New-Object System.Windows.Forms.Label
$lblHistTitle.Text = "Run History"
$lblHistTitle.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 12)
$lblHistTitle.ForeColor = $ColText
$lblHistTitle.Location = New-Object System.Drawing.Point(10, 16); $lblHistTitle.AutoSize = $true
$pnlHistory.Controls.Add($lblHistTitle)

$lblHistSub = New-Object System.Windows.Forms.Label
$lblHistSub.Text = "Past diagnostic runs - double-click a row to open the full report."
$lblHistSub.Font = New-Object System.Drawing.Font("Segoe UI", 8.5); $lblHistSub.ForeColor = $ColMuted
$lblHistSub.Location = New-Object System.Drawing.Point(10, 42); $lblHistSub.Size = New-Object System.Drawing.Size(1000, 18)
$pnlHistory.Controls.Add($lblHistSub)

$lnkHistRefresh = New-Object System.Windows.Forms.LinkLabel; $lnkHistRefresh.Text = "Refresh"
$lnkHistRefresh.Font = New-Object System.Drawing.Font("Segoe UI",8.5); $lnkHistRefresh.LinkColor = $ColMuted
$lnkHistRefresh.Location = New-Object System.Drawing.Point(1180, 44); $lnkHistRefresh.AutoSize = $true
$pnlHistory.Controls.Add($lnkHistRefresh)
$lnkHistRefresh.Add_LinkClicked({ Update-HistoryList })

$lvHistory = New-Object System.Windows.Forms.ListView
$lvHistory.Size = New-Object System.Drawing.Size(1240, 534)
$lvHistory.Location = New-Object System.Drawing.Point(10, 68); $lvHistory.Anchor = $AnchorTLRB
$lvHistory.View = [System.Windows.Forms.View]::Details
$lvHistory.FullRowSelect = $true
$lvHistory.GridLines = $false
$lvHistory.BorderStyle = [System.Windows.Forms.BorderStyle]::None
$lvHistory.BackColor = $ColCard
$lvHistory.ForeColor = $ColText
$lvHistory.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$lvHistory.HeaderStyle = [System.Windows.Forms.ColumnHeaderStyle]::Nonclickable
$lvHistory.UseCompatibleStateImageBehavior = $false
$pnlHistory.Controls.Add($lvHistory)
$lvHistory.Columns.Add("Date / Time",   142) | Out-Null
$lvHistory.Columns.Add("Result",         92) | Out-Null
$lvHistory.Columns.Add("Summary",       948) | Out-Null
$lvHistory.Columns.Add("Size",           58) | Out-Null

$lvHistory.Add_DoubleClick({
    if ($lvHistory.SelectedItems.Count -gt 0) {
        $path = $lvHistory.SelectedItems[0].Tag
        if ($path -and (Test-Path $path)) { Start-Process notepad.exe $path }
    }
})

