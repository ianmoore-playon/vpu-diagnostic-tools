namespace Pulse.WPF.Models
{
    /// <summary>One row in the Domain Tests table.</summary>
    public class DomainTestResult
    {
        public string Domain { get; set; }
        public string ResolvedTo { get; set; } // first IP returned by DNS
        public string Status { get; set; }     // "Pass" / "Fail" / "Info"
    }
}
