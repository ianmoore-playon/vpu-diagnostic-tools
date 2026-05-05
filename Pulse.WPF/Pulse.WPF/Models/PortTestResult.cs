namespace Pulse.WPF.Models
{
    /// <summary>One row in the Connectivity Tests table.</summary>
    public class PortTestResult
    {
        public string Protocol { get; set; }   // "TCP" / "UDP"
        public int Port { get; set; }
        public string Host { get; set; }
        public string Purpose { get; set; }
        public string Status { get; set; }     // "Pass" / "Fail" / "Info"
    }
}
