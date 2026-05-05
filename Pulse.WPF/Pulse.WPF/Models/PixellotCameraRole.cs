namespace Pulse.WPF.Models
{
    /// <summary>
    /// One IP → role mapping derived from cameras.cfg / pip.cfg.
    /// Returned by PixellotConfigService.GetRoles() as a dictionary keyed
    /// by IP. Both the live port-monitoring polling loop and the diagnostic
    /// engine consult this to label each port.
    /// </summary>
    public class PixellotCameraRole
    {
        public string Ip { get; set; }
        public string Role { get; set; }   // "Main Camera 1", "OCR / Scoreboard", "Additional Angle 1", etc.

        public override string ToString() => $"{Ip} -> {Role}";
    }
}
