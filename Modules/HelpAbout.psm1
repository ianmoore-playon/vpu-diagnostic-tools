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

# v1.0.43 redesign — section header + guide content
# v1.0.53 — feedback form removed; user feedback goes through Slack / email.
$helpHeader = New-SectionHeader -Parent $pnlHelp `
    -Title    "About & Help" `
    -Subtitle "How to use Pulse and answers to common questions."
Set-SectionPill $helpHeader "ok" "Pulse $ScriptVersion"

# Help content — fills the panel below the section header.
$rtbHelp = New-Object System.Windows.Forms.RichTextBox
$rtbHelp.Size = New-Object System.Drawing.Size(($pnlHelp.Width - 56), ($ContentH - 130))
$rtbHelp.Location = New-Object System.Drawing.Point(28, 110)
$rtbHelp.Anchor = $AnchorTLRB
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
    @{ H="Camera Fault Isolator"; B="The Camera tab includes a guided fault-isolation wizard accessible via the Open Fault Isolator button. The wizard walks through a four-phase swap test to identify whether a degraded port is caused by the NIC, the cable, or the camera itself.`n`nPhase 1 captures the baseline link speed for the suspect port. Phase 2 swaps the cable to a known-good port to test if the fault follows the NIC port. Phase 3 swaps the cable to test if the fault follows the cable. Phase 4 swaps the camera to test if the fault follows the camera.`n`nEach phase produces a plain-language verdict, and the wizard concludes with a Run Full Diagnostic action to confirm the fix." }
    @{ H="System Information sections"; B="The System Information tab surfaces hardware specs and configuration details:`n`n- Pixellot Software: registry-derived App Version, System Image Version, and Package Dependencies.`n- Operating System / System: edition, build, manufacturer, model, BIOS, serial number.`n- Time & Locale: timezone, NTP server, W32Time service status. Flags UTC default as a likely misconfiguration.`n- Pixellot Calibrations: scans known calibration paths and lists files with last-modified times.`n- Installed Software: counts installed apps and flags known-conflicting software (other AV, OBS, BitTorrent, etc.)." }
    @{ H="Frequently asked questions"; B="Q: VPU.exe shows Not streaming - is that a problem?`nA: No. VPU.exe only runs when cameras are actively streaming. It is normal for it to be absent between games.`n`nQ: A NIC port shows No link - is that a fault?`nA: No link is normal for ports that do not have a camera connected. Only ports with a camera attached that show 100 Mbps are faults.`n`nQ: Network tests fail for pixellot.stream - is that a problem?`nA: pixellot.stream is no longer probed directly. Reliable port tests now hit Pixellot's prod-echo.pixellot.tv echo server, and the pixellot.stream domain shows an INFO row in the domain test (it is a stream-only destination).`n`nQ: The tool says it cannot read the event log - what does that mean?`nA: This can happen if the Windows Event Log service is stopped or the account running the tool lacks permission. Restart the service via services.msc." }
    @{ H="About Pulse"; B="Pulse — Pixellot Unified Live System Evaluator`nVersion: see the header bar`nRepository: https://github.com/ianmoore-playon/vpu-diagnostic-tools`nLicense: Internal use within PlayOn Sports / NFHS Network. Not for external distribution.`n`nFeedback and bug reports: please share directly with the tools team over Slack or email." }
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
