# =============================================================================
#  HelpAbout.psm1  -  About / Help panel
# =============================================================================

# ---- Help Panel (shown via About nav) --------------------------------------
$pnlHelp = New-Object System.Windows.Forms.Panel
$pnlHelp.Size     = New-Object System.Drawing.Size($WideW, $ContentH)
$pnlHelp.Location = New-Object System.Drawing.Point($SideW, $ContentY)
$pnlHelp.BackColor = $ColBg; $pnlHelp.Visible = $false
$pnlHelp.Anchor = $AnchorTLRB
$form.Controls.Add($pnlHelp)

$lblHelpTitle = New-Object System.Windows.Forms.Label
$lblHelpTitle.Text = "How to Use This Tool"
$lblHelpTitle.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 12)
$lblHelpTitle.ForeColor = $ColText
$lblHelpTitle.Location = New-Object System.Drawing.Point(10, 16); $lblHelpTitle.AutoSize = $true
$pnlHelp.Controls.Add($lblHelpTitle)

# Help content — anchored top only so feedback section can sit at the bottom
$rtbHelp = New-Object System.Windows.Forms.RichTextBox
$rtbHelp.Size = New-Object System.Drawing.Size(1240, ($ContentH - 240))
$rtbHelp.Location = New-Object System.Drawing.Point(24, 46)
$rtbHelp.Anchor = $AnchorTLR
$rtbHelp.BackColor = $ColBg; $rtbHelp.ForeColor = $ColText
$rtbHelp.Font = New-Object System.Drawing.Font("Segoe UI", 9); $rtbHelp.ReadOnly = $true
$rtbHelp.BorderStyle = [System.Windows.Forms.BorderStyle]::None
$rtbHelp.ScrollBars = [System.Windows.Forms.RichTextBoxScrollBars]::Vertical
$pnlHelp.Controls.Add($rtbHelp)

$helpSections = @(
    @{ H="What this tool does"; B="Pulse (Pixellot Unified Live System Evaluator) is an all-in-one diagnostic tool for Pixellot VPU systems. It checks camera NIC link speeds and SmartSpeed events, pings cameras, analyses the Pixellot application log, verifies network connectivity, inspects running services, reads disk health, and scans the OS event log. Run it on-site or remotely to quickly identify what is causing a problem on a VPU." }
    @{ H="Home - running a full diagnostic"; B="From the Home screen, click the Run Full Diagnostic button (top-right of the header) and wait about 60-90 seconds. Each module row updates live as checks complete. When all seven modules finish, a banner shows either all clear or a count of issues with module names.`n`nUse the View button on any highlighted row to jump directly to that module's detail panel. Use Re-run Failed Only to quickly re-check only the modules that had issues." }
    @{ H="Camera tab"; B="Shows link speed for each Intel camera NIC port (P1, P2, ...). Green = 1 Gbps healthy. Red = 100 Mbps degraded (physical fault). Grey = no cable connected.`n`nThe SmartSpeed card counts Intel Event ID 40 - these events fire only when the NIC tried gigabit but the physical medium could not sustain it. A non-zero SmartSpeed count is definitive evidence of a cable or NIC fault, not a camera issue. Zero events on a 100 Mbps port means the device is 100-Mbps-only (OCR camera - no action needed).`n`nThe Ping and CHU Detection cards tell you whether the camera is reachable on the network and responding to RTSP." }
    @{ H="Network tab"; B="Tests ports and domains required by Pixellot using real protocol probes (DNS, NTP, TCP). Reliable tests show PASS or FAIL. Unreliable tests (dynamic stream servers) show INFO - these servers do not respond to raw probes and should be verified via the domain test instead.`n`nIf any test fails, check the uplink adapter, router, and firewall. Ensure Pixellot ports are not blocked." }
    @{ H="Services tab"; B="Shows whether core Pixellot processes are running: Agent, KeepAgentUp, Coordinator, LogMeIn, VPU, and Scoreconnect. VPU.exe not running is normal when no cameras are actively streaming - this is not a fault.`n`nIf Agent, KeepAgentUp, or Coordinator are missing, reboot the VPU or manually restart the processes. Check Windows Services (services.msc) if they do not come back." }
    @{ H="Hardware tab"; B="Shows GPU model, monitor connection, keyboard and mouse status, NIC link uptime, and PoE power budget. NIC uptime and PoE data are populated by the Camera tab - run Camera first to see these values.`n`nIf PoE budget shows LOW, check the Molex power connector on the PoE NIC card inside the VPU." }
    @{ H="Disks tab"; B="Checks physical drive health (SMART status), free space on each volume, Pixellot storage path sizes, largest top-level folders per drive, and disk-related event log errors from the last 48 hours.`n`nRed = critical (less than 5 GB free or over 97% used). Yellow = warning (less than 15 GB free or over 90% used). Clear old recordings from C:\Pixellot\recordings if space is low." }
    @{ H="Event Logs tab"; B="Reads System and Application event logs and displays errors and warnings from the last 24 hours. A high error count (especially disk, NTFS, or driver errors) often correlates with hardware problems seen in other tabs.`n`nUp to 20 errors and 10 warnings are shown per log. Use Event Viewer (eventvwr.msc) to see the full list with all details." }
    @{ H="Reports tab"; B="Lists all past Full Diagnostic runs stored in the Pulse_Results folder. Double-click any row to open the full report in Notepad. Green rows are all-clear; red rows show which ports had faults.`n`nReports are saved automatically after each Camera diagnostic run." }
    @{ H="What is a SmartSpeed event?"; B="Intel SmartSpeed Event ID 40 fires when the NIC tried to establish a gigabit link but the physical medium could not sustain it. It only fires on physical-layer failures - it never fires when a device (like an OCR camera) simply does not support gigabit.`n`nAny non-zero SmartSpeed count on a camera NIC is definitive evidence of a cable, connector, or NIC fault. Zero events on a 100 Mbps port means the device is 100-Mbps-only and gigabit was never attempted." }
    @{ H="Frequently asked questions"; B="Q: VPU.exe shows Not running - is that a problem?`nA: No. VPU.exe only runs when cameras are actively streaming. It is normal for it to be absent between games.`n`nQ: A NIC port shows No link - is that a fault?`nA: No link is normal for ports that do not have a camera connected. Only ports with a camera attached that show 100 Mbps are faults.`n`nQ: Network tests fail for pixellot.stream - is that a problem?`nA: pixellot.stream is marked INFO because it is a dynamic streaming server that does not respond to raw probes. Check the domain test result for pixellot.stream instead.`n`nQ: The tool says it cannot read the event log - what does that mean?`nA: This can happen if the Windows Event Log service is stopped or the account running the tool lacks permission. Restart the service via services.msc." }
)
$firstHelp = $true
foreach ($s in $helpSections) {
    if (-not $firstHelp) {
        $rtbHelp.SelectionStart = $rtbHelp.TextLength; $rtbHelp.SelectionLength = 0
        $rtbHelp.SelectionFont = New-Object System.Drawing.Font("Segoe UI",5); $rtbHelp.SelectionColor = $ColBg; $rtbHelp.AppendText("`n")
    }
    $rtbHelp.SelectionStart = $rtbHelp.TextLength; $rtbHelp.SelectionLength = 0
    $rtbHelp.SelectionFont = New-Object System.Drawing.Font("Segoe UI Semibold", 9.5); $rtbHelp.SelectionColor = $ColText; $rtbHelp.AppendText("$($s.H)`n")
    $rtbHelp.SelectionStart = $rtbHelp.TextLength; $rtbHelp.SelectionLength = 0
    $rtbHelp.SelectionFont = New-Object System.Drawing.Font("Segoe UI", 9); $rtbHelp.SelectionColor = $ColMuted; $rtbHelp.AppendText("$($s.B)`n")
    $firstHelp = $false
}

# ---- Feedback Section -------------------------------------------------------
$sepFb = New-Object System.Windows.Forms.Panel
$sepFb.Size     = New-Object System.Drawing.Size($WideW, 1)
$sepFb.Location = New-Object System.Drawing.Point(0, ($ContentH - 189))
$sepFb.BackColor = $ColCard
$sepFb.Anchor   = $AnchorBLR
$pnlHelp.Controls.Add($sepFb)

$lblFbTitle = New-Object System.Windows.Forms.Label
$lblFbTitle.Text      = "Submit Feedback"
$lblFbTitle.Font      = New-Object System.Drawing.Font("Segoe UI Semibold", 9.5)
$lblFbTitle.ForeColor = $ColText
$lblFbTitle.Location  = New-Object System.Drawing.Point(24, ($ContentH - 183))
$lblFbTitle.AutoSize  = $true
$lblFbTitle.Anchor    = $AnchorBL
$pnlHelp.Controls.Add($lblFbTitle)

$lblFbSub = New-Object System.Windows.Forms.Label
$lblFbSub.Text      = "Report a bug or suggest an improvement — submitted directly as a GitHub issue."
$lblFbSub.Font      = New-Object System.Drawing.Font("Segoe UI", 8.5)
$lblFbSub.ForeColor = $ColMuted
$lblFbSub.Location  = New-Object System.Drawing.Point(24, ($ContentH - 163))
$lblFbSub.Size      = New-Object System.Drawing.Size(900, 18)
$lblFbSub.Anchor    = $AnchorBL
$pnlHelp.Controls.Add($lblFbSub)

$lblFbType = New-Object System.Windows.Forms.Label
$lblFbType.Text      = "Type:"
$lblFbType.Font      = New-Object System.Drawing.Font("Segoe UI", 9)
$lblFbType.ForeColor = $ColText
$lblFbType.Location  = New-Object System.Drawing.Point(24, ($ContentH - 137))
$lblFbType.AutoSize  = $true
$lblFbType.Anchor    = $AnchorBL
$pnlHelp.Controls.Add($lblFbType)

$cboFbType = New-Object System.Windows.Forms.ComboBox
$cboFbType.Items.AddRange(@("Bug Report", "Suggestion")) | Out-Null
$cboFbType.SelectedIndex = 0
$cboFbType.Size          = New-Object System.Drawing.Size(180, 24)
$cboFbType.Location      = New-Object System.Drawing.Point(70, ($ContentH - 140))
$cboFbType.BackColor     = $ColCard
$cboFbType.ForeColor     = $ColText
$cboFbType.Font          = New-Object System.Drawing.Font("Segoe UI", 9)
$cboFbType.FlatStyle     = [System.Windows.Forms.FlatStyle]::Flat
$cboFbType.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
$cboFbType.Anchor        = $AnchorBL
$pnlHelp.Controls.Add($cboFbType)

$chkFbSysInfo = New-Object System.Windows.Forms.CheckBox
$chkFbSysInfo.Text      = "Include system info (hostname, OS, Pulse version)"
$chkFbSysInfo.Font      = New-Object System.Drawing.Font("Segoe UI", 8.5)
$chkFbSysInfo.ForeColor = $ColMuted
$chkFbSysInfo.Location  = New-Object System.Drawing.Point(270, ($ContentH - 138))
$chkFbSysInfo.Size      = New-Object System.Drawing.Size(380, 20)
$chkFbSysInfo.Checked   = $true
$chkFbSysInfo.Anchor    = $AnchorBL
$pnlHelp.Controls.Add($chkFbSysInfo)

$lblFbDetails = New-Object System.Windows.Forms.Label
$lblFbDetails.Text      = "Details:"
$lblFbDetails.Font      = New-Object System.Drawing.Font("Segoe UI", 9)
$lblFbDetails.ForeColor = $ColText
$lblFbDetails.Location  = New-Object System.Drawing.Point(24, ($ContentH - 107))
$lblFbDetails.AutoSize  = $true
$lblFbDetails.Anchor    = $AnchorBL
$pnlHelp.Controls.Add($lblFbDetails)

$txtFbDetails = New-Object System.Windows.Forms.TextBox
$txtFbDetails.Multiline    = $true
$txtFbDetails.Size         = New-Object System.Drawing.Size(1148, 52)
$txtFbDetails.Location     = New-Object System.Drawing.Point(70, ($ContentH - 110))
$txtFbDetails.BackColor    = $ColCard
$txtFbDetails.ForeColor    = $ColText
$txtFbDetails.Font         = New-Object System.Drawing.Font("Segoe UI", 9)
$txtFbDetails.BorderStyle  = [System.Windows.Forms.BorderStyle]::FixedSingle
$txtFbDetails.ScrollBars   = [System.Windows.Forms.ScrollBars]::Vertical
$txtFbDetails.Anchor       = $AnchorBLR
$pnlHelp.Controls.Add($txtFbDetails)

$lblFbStatus = New-Object System.Windows.Forms.Label
$lblFbStatus.Text      = ""
$lblFbStatus.Font      = New-Object System.Drawing.Font("Segoe UI", 8.5)
$lblFbStatus.ForeColor = $ColMuted
$lblFbStatus.Location  = New-Object System.Drawing.Point(24, ($ContentH - 50))
$lblFbStatus.Size      = New-Object System.Drawing.Size(900, 18)
$lblFbStatus.Anchor    = $AnchorBL
$pnlHelp.Controls.Add($lblFbStatus)

$btnFbSend = New-Object System.Windows.Forms.Button
$btnFbSend.Text      = "Send Feedback"
$btnFbSend.Size      = New-Object System.Drawing.Size(130, 28)
$btnFbSend.Location  = New-Object System.Drawing.Point(($WideW - 154), ($ContentH - 54))
$btnFbSend.BackColor = $ColAccent
$btnFbSend.ForeColor = [System.Drawing.Color]::White
$btnFbSend.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnFbSend.FlatAppearance.BorderSize = 0
$btnFbSend.Font      = New-Object System.Drawing.Font("Segoe UI Semibold", 9)
$btnFbSend.Cursor    = [System.Windows.Forms.Cursors]::Hand
$btnFbSend.Anchor    = [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Right
$pnlHelp.Controls.Add($btnFbSend)

$btnFbSend.Add_Click({
    $fbType = $cboFbType.SelectedItem
    $fbText = $txtFbDetails.Text.Trim()

    if (-not $script:FeedbackToken) {
        $lblFbStatus.ForeColor = $ColYellow
        $lblFbStatus.Text = "Feedback token not configured — contact your administrator."
        return
    }
    if (-not $fbText) {
        $lblFbStatus.ForeColor = $ColYellow
        $lblFbStatus.Text = "Please enter a description before sending."
        return
    }

    $firstLine  = ($fbText -split "`n")[0].Trim()
    $issueTitle = "[$fbType] " + $(if ($firstLine.Length -gt 100) { $firstLine.Substring(0,100) + "..." } else { $firstLine })

    $sysBlock = ""
    if ($chkFbSysInfo.Checked) {
        $vpuModel = if ($sync.VpuModel) { $sync.VpuModel } else { "Unknown" }
        $sysBlock  = "`n`n---`n**System Info**`n- Host: $($env:COMPUTERNAME)`n- OS: $([System.Environment]::OSVersion.VersionString)`n- Pulse: $ScriptVersion`n- VPU Model: $vpuModel"
    }

    $label     = if ($fbType -eq "Bug Report") { "bug" } else { "enhancement" }
    $issueBody = @{ title=$issueTitle; body="$fbText$sysBlock"; labels=@($label) } | ConvertTo-Json -Compress

    $btnFbSend.Enabled     = $false
    $lblFbStatus.ForeColor = $ColMuted
    $lblFbStatus.Text      = "Submitting..."

    try {
        $wc = New-Object System.Net.WebClient
        $wc.Headers.Add("Authorization",        "Bearer $script:FeedbackToken")
        $wc.Headers.Add("User-Agent",           "Pulse-VPU-Diagnostics/$ScriptVersion")
        $wc.Headers.Add("Content-Type",         "application/json")
        $wc.Headers.Add("Accept",               "application/vnd.github+json")
        $wc.Headers.Add("X-GitHub-Api-Version", "2022-11-28")
        $result = $wc.UploadString("https://api.github.com/repos/ianmoore-playon/vpu-diagnostic-tools/issues", "POST", $issueBody)
        $resp   = $result | ConvertFrom-Json
        $lblFbStatus.ForeColor = $ColGreen
        $lblFbStatus.Text      = "Submitted — Issue #$($resp.number). Thank you!"
        $txtFbDetails.Text     = ""
    } catch {
        $plain = "[$fbType]`n$fbText$sysBlock"
        try { [System.Windows.Forms.Clipboard]::SetText($plain) } catch { }
        $lblFbStatus.ForeColor = $ColYellow
        $lblFbStatus.Text      = "Could not reach GitHub. Feedback copied to clipboard."
    } finally {
        $btnFbSend.Enabled = $true
    }
})
