namespace Pulse.WPF.Models
{
    /// <summary>One row in the Services panel table.</summary>
    public class ServiceStatusRow
    {
        public string Name { get; set; }      // "Agent.exe"
        public string Status { get; set; }    // "Running" / "Stopped" / "Not detected"
        public string Detail { get; set; }    // "PID 4128" / "Service registered, process not found"
        public string Severity { get; set; }  // "Pass" / "Warn" / "Fail" / "Gray"
    }
}
