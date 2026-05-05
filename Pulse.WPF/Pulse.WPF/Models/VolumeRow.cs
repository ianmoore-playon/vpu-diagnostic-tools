namespace Pulse.WPF.Models
{
    /// <summary>One row in the Volumes table on the Disk Health panel.</summary>
    public class VolumeRow
    {
        public string DeviceId { get; set; }    // "C:"
        public string Label { get; set; }
        public string Role { get; set; }        // "OS Drive" / "Recording / Storage" / "Data"
        public double FreeGb { get; set; }
        public double TotalGb { get; set; }
        public int PercentUsed { get; set; }
        public string Severity { get; set; }    // "Pass" / "Warn" / "Fail"
    }
}
