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

$rtbHelp = New-Object System.Windows.Forms.RichTextBox
$rtbHelp.Size = New-Object System.Drawing.Size(1012, 600); $rtbHelp.Location = New-Object System.Drawing.Point(24, 46); $rtbHelp.Anchor = $AnchorTLRB
$rtbHelp.BackColor = $ColBg; $rtbHelp.ForeColor = $ColText
$rtbHelp.Font = New-Object System.Drawing.Font("Segoe UI", 9); $rtbHelp.ReadOnly = $true
$rtbHelp.BorderStyle = [System.Windows.Forms.BorderStyle]::None
$rtbHelp.ScrollBars = [System.Windows.Forms.RichTextBoxScrollBars]::Vertical
$pnlHelp.Controls.Add($rtbHelp)

$helpSections = @(
    @{ H="What this tool does";           B="Diagnoses camera NIC link-speed problems on Pixellot VPUs. It measures link speed on each Intel NIC port, checks for Intel SmartSpeed downgrade events (physical-layer evidence), pings each camera, and analyses the Pixellot application log. Results appear in plain language with a recommended next action." }
    @{ H="Overview tab - running a diagnostic"; B="Click Run Full Diagnostic and wait about 60-90 seconds. The port cards (P1-P4) update live as each port is measured. When complete, the right panel shows numbered next steps.`n`nIf a port shows a degraded link, the SmartSpeed card tells you how many downgrade events occurred in the last 48 hours - that count is the key evidence to quote when escalating." }
    @{ H="Reading the port cards";        B="Green / 1 Gbps = healthy link.`nRed / 100 Mbps = degraded (physical fault, use Isolate to pinpoint the cause).`nGrey / No link = no cable connected or device off.`n100M OCR = expected for OCR scoreboard cameras (100 Mbps-only, no action needed).`n`nClicking a red port card takes you straight to Isolate with that port pre-selected." }
    @{ H="Isolate tab - fault isolation"; B="Use Isolate when Overview shows a degraded port and you need to know whether to replace the cable, the NIC port, or the camera. Do not replace anything until Isolate tells you what is at fault.`n`nIsolate uses the 'one change at a time' method:`n  Phase 1 - Baseline: confirm the fault exists.`n  Phase 2 - NIC Port: move cable+camera to another port.`n  Phase 3 - Cable: swap in a known-good cable.`n  Phase 4 - Camera: swap in a known-good camera.`n`nEach phase measures link speed and tells you whether the fault followed the changed component." }
    @{ H="History tab";                   B="Shows all past diagnostic runs from the CameraLink_Results folder. Green rows are All Clear; red rows show Issues Found with the affected port(s). Double-click any row to open the full report in Notepad.`n`nIf the same port appears as Issues Found across many runs, the trend line on the Overview summary card will note this - useful evidence when requesting a replacement." }
    @{ H="Escalating to support";         B="After a run, click Copy Summary in the Actions section. This generates a structured paragraph with port status, SmartSpeed count, camera results, and recommended next steps - paste it directly into your ticket or support chat.`n`nThe Run ID in the summary matches the filename in CameraLink_Results so the agent can ask you to email the full report if needed." }
    @{ H="What is a SmartSpeed event?";   B="Intel SmartSpeed Event ID 40 fires when the NIC tried to establish a gigabit link but the physical medium could not sustain it. It only fires on physical-layer failures - it never fires when a device (like an OCR camera) simply doesn't support gigabit.`n`nAny non-zero SmartSpeed count on a camera NIC is definitive evidence of a cable, termination, or NIC fault. Zero events on a 100 Mbps port means the device is 100-Mbps-only (OCR camera)." }
    @{ H="Frequently asked questions";    B="Q: The VPU Model shows 'Not detected' - is that a problem?`nA: No. The tool still runs a full diagnostic. VPU model detection requires the Pixellot agent log to be present and recently updated.`n`nQ: Ethernet 47 / 48 show No link - is that a fault?`nA: No link is normal for ports that don't have a camera connected. Only ports that should have a camera but show 100 Mbps are faults.`n`nQ: Isolate says 'NIC / hardware fault' - what now?`nA: Known-good cable and camera still fail on the test port. Run a full diagnostic, use Copy Summary, and escalate to L2 support for hardware replacement." }
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

