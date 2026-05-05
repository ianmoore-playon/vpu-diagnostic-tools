namespace Pulse.WPF.Models
{
    /// <summary>
    /// One actionable diagnostic finding shown in the Findings list at the top
    /// of each panel. Severity drives the icon/color; Title is plain language;
    /// Recommendation is the single next step a tech can take.
    /// Mirrors the UX_REVIEW.md Section 4 wording rules.
    /// </summary>
    public class Finding
    {
        public string Severity { get; set; }       // "Critical" | "Warning" | "Info"
        public string Title { get; set; }          // "Port 2 — Main Camera negotiated 100 Mbps"
        public string Recommendation { get; set; } // "Reseat the cable on Port 2 or replace it."
    }
}
