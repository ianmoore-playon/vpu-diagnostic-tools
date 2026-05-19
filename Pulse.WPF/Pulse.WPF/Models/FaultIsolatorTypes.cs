using System;

namespace Pulse.WPF.Models
{
    /// <summary>
    /// State machine for the Camera Fault Isolator wizard.
    ///
    /// Phase naming reflects what the wizard is *waiting for the tech to do*,
    /// not what it last computed:
    ///
    ///   * PickPort              — tech is selecting the suspect port.
    ///                              Action button: "Start Baseline" / "Recheck Port"
    ///   * AwaitingNicPortTest   — baseline done, tech is moving the same
    ///                              cable+camera to the test port.
    ///                              Action button: "Check Now"
    ///   * AwaitingCableTest     — NIC port test done, tech is swapping the
    ///                              cable for a known-good one.
    ///                              Action button: "Check Now"
    ///   * AwaitingCameraTest    — cable test done, tech is swapping the
    ///                              camera for a known-good one.
    ///                              Action button: "Check Now"
    ///   * Concluded             — a verdict reached. Action button:
    ///                              "Run Full Diagnostic"
    /// </summary>
    public enum FaultIsolatorPhase
    {
        PickPort            = 0,
        AwaitingNicPortTest = 1,
        AwaitingCableTest   = 2,
        AwaitingCameraTest  = 3,
        Concluded           = 4,
    }

    /// <summary>
    /// The diagnosis reached at the end of the wizard. NicHardware fires when
    /// Phase 4 still shows degraded with known-good cable AND known-good
    /// camera. None means the wizard hasn't concluded (either still running
    /// or the tech bailed via Cancel / Start Over).
    /// </summary>
    public enum FaultConclusion
    {
        None         = 0,
        NicPort      = 1,   // Phase 2: fault followed the original NIC port
        Cable        = 2,   // Phase 3: fault followed the original cable
        Camera       = 3,   // Phase 4: fault followed the original camera (CHU)
        NicHardware  = 4,   // Phase 4: known-good cable + camera still fails
    }

    /// <summary>One row in the wizard's per-run history list / report file.</summary>
    public class FaultIsolatorHistoryRow
    {
        public DateTime TimestampLocal { get; set; }
        public string   PhaseName      { get; set; } = "";
        public string   Configuration  { get; set; } = "";
        public string   SpeedReading   { get; set; } = "";
        public string   Verdict        { get; set; } = "";
        /// <summary>"Pass" | "Info" | "Fail". Mirrors legacy Add-GuideHistory severity vocabulary.</summary>
        public string   Severity       { get; set; } = "Info";

        public string TimestampLabel => TimestampLocal.ToString("HH:mm:ss");

        /// <summary>Uppercase form for the chip text ("PASS" / "INFO" / "FAIL").</summary>
        public string SeverityLabel => (Severity ?? "Info").ToUpperInvariant();
    }

    /// <summary>
    /// Display row for the wizard's port-selection dropdowns. LocalMac is
    /// the stable key the wizard uses for all per-port reads; AdapterName +
    /// DisplayLabel are display-only.
    /// </summary>
    public class PortChoice
    {
        public string LocalMac      { get; set; } = "";
        public string AdapterName   { get; set; } = "";
        public string DisplayLabel  { get; set; } = "";
        public ulong  LinkSpeedBps  { get; set; }
        public bool   IsUp          { get; set; }
        public bool   IsOcr         { get; set; }
        public bool   IsDegraded    { get; set; }
    }
}
