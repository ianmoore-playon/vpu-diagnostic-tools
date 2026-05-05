namespace Pulse.WPF.Models
{
    /// <summary>One row in the Pixellot Storage Paths table.</summary>
    public class PixellotPathRow
    {
        public string Path { get; set; }
        public string Label { get; set; }
        public string SizeFormatted { get; set; }
        public string Severity { get; set; }   // "Pass" / "Warn" / "Fail" / "Gray"
    }
}
