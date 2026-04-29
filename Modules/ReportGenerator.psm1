# =============================================================================
#  ReportGenerator.psm1  —  Run History panel + Update-HistoryList helper
# =============================================================================

function Update-HistoryList {
    $lvHistory.Items.Clear()
    $files = @(Get-ChildItem -Path $OutputDir -Filter "CameraLink_Results_*.txt" -ErrorAction SilentlyContinue |
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
            $lines = Get-Content -Path $f.FullName -ErrorAction Stop
            $statusLine = $lines | Where-Object { $_ -match '^STATUS:' } | Select-Object -Last 1
            if ($statusLine -match 'ALL_CLEAR') {
                $resultText = "All Clear"; $resultColor = $ColGreen; $summary = "All ports healthy"
            } elseif ($statusLine -match 'ISSUES_FOUND') {
                $resultText = "Issues Found"; $resultColor = $ColRed
                $failLines = @($lines | Where-Object { $_ -match 'DEGRADED' })
                $ports = $failLines | ForEach-Object {
                    if ($_ -match '^\s+(.+?)\s{2,}DEGRADED') { $Matches[1].Trim() }
                } | Where-Object { $_ }
                $summary = "$($failLines.Count) fault(s)" + $(if ($ports) { " — " + ($ports -join ", ") } else { "" })
            } else {
                $failLines = @($lines | Where-Object { $_ -match 'DEGRADED' })
                if ($failLines.Count -gt 0) {
                    $resultText = "Issues Found"; $resultColor = $ColRed
                    $ports = $failLines | ForEach-Object {
                        if ($_ -match '^\s+(.+?)\s{2,}DEGRADED') { $Matches[1].Trim() }
                    } | Where-Object { $_ }
                    $summary = "$($failLines.Count) fault(s)" + $(if ($ports) { " — " + ($ports -join ", ") } else { "" })
                } elseif (@($lines | Where-Object { $_ -match 'Complete' }).Count -gt 0) {
                    $resultText = "All Clear"; $resultColor = $ColGreen; $summary = "All ports healthy"
                }
            }
        } catch { }
        $sizeKb = [math]::Round($f.Length / 1KB, 1)
        $item = New-Object System.Windows.Forms.ListViewItem($dt.ToString("yyyy-MM-dd  HH:mm"))
        $item.SubItems.Add($resultText) | Out-Null
        $item.SubItems.Add($summary)    | Out-Null
        $item.SubItems.Add("$sizeKb KB") | Out-Null
        $item.ForeColor = $resultColor
        $item.BackColor = [System.Drawing.Color]::White
        $item.Tag       = $f.FullName
        $lvHistory.Items.Add($item) | Out-Null
    }
}

function Build-HistoryPanel {
    $script:pnlHistory = New-Object System.Windows.Forms.Panel
    $script:pnlHistory.Size      = New-Object System.Drawing.Size($WideW, $ContentH)
    $script:pnlHistory.Location  = New-Object System.Drawing.Point($SideW, $HdrH)
    $script:pnlHistory.BackColor = $ColBg
    $script:pnlHistory.Visible   = $false
    $script:pnlHistory.Anchor    = $AnchorTLRB
    $form.Controls.Add($script:pnlHistory)

    $lblHistTitle = New-Object System.Windows.Forms.Label
    $lblHistTitle.Text = "Run History"
    $lblHistTitle.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 12)
    $lblHistTitle.ForeColor = $ColText
    $lblHistTitle.Location = New-Object System.Drawing.Point(10, 16); $lblHistTitle.AutoSize = $true
    $script:pnlHistory.Controls.Add($lblHistTitle)

    $lblHistSub = New-Object System.Windows.Forms.Label
    $lblHistSub.Text = "Past diagnostic runs — double-click a row to open the full report."
    $lblHistSub.Font = New-Object System.Drawing.Font("Segoe UI", 8.5); $lblHistSub.ForeColor = $ColMuted
    $lblHistSub.Location = New-Object System.Drawing.Point(10, 42); $lblHistSub.Size = New-Object System.Drawing.Size(540, 18)
    $script:pnlHistory.Controls.Add($lblHistSub)

    $lnkHistRefresh = New-Object System.Windows.Forms.LinkLabel
    $lnkHistRefresh.Text = "Refresh"
    $lnkHistRefresh.Font = New-Object System.Drawing.Font("Segoe UI", 8.5); $lnkHistRefresh.LinkColor = $ColMuted
    $lnkHistRefresh.Location = New-Object System.Drawing.Point(544, 44); $lnkHistRefresh.AutoSize = $true
    $script:pnlHistory.Controls.Add($lnkHistRefresh)
    $lnkHistRefresh.Add_LinkClicked({ Update-HistoryList })

    $script:lvHistory = New-Object System.Windows.Forms.ListView
    $script:lvHistory.Size = New-Object System.Drawing.Size(1012, 560)
    $script:lvHistory.Location = New-Object System.Drawing.Point(10, 68)
    $script:lvHistory.Anchor = $AnchorTLRB
    $script:lvHistory.View = [System.Windows.Forms.View]::Details
    $script:lvHistory.FullRowSelect = $true
    $script:lvHistory.GridLines = $false
    $script:lvHistory.BorderStyle = [System.Windows.Forms.BorderStyle]::None
    $script:lvHistory.BackColor = [System.Drawing.Color]::White
    $script:lvHistory.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $script:lvHistory.HeaderStyle = [System.Windows.Forms.ColumnHeaderStyle]::Nonclickable
    $script:lvHistory.UseCompatibleStateImageBehavior = $false
    $script:pnlHistory.Controls.Add($script:lvHistory)
    $script:lvHistory.Columns.Add("Date / Time",   142) | Out-Null
    $script:lvHistory.Columns.Add("Result",         92) | Out-Null
    $script:lvHistory.Columns.Add("Summary",       700) | Out-Null
    $script:lvHistory.Columns.Add("Size",           58) | Out-Null

    $script:lvHistory.Add_DoubleClick({
        if ($script:lvHistory.SelectedItems.Count -gt 0) {
            $path = $script:lvHistory.SelectedItems[0].Tag
            if ($path -and (Test-Path $path)) { Start-Process notepad.exe $path }
        }
    })
}
