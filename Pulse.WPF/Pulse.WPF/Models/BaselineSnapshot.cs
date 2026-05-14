using System;
using System.Collections.Generic;

namespace Pulse.WPF.Models
{
    /// <summary>
    /// Serializable summary of the most recent full baseline run. Kept small
    /// on purpose so the Dashboard can restore a trustworthy "last baseline"
    /// state before the next startup pass finishes.
    /// </summary>
    public class BaselineSnapshot
    {
        public DateTime CompletedAtLocal { get; set; } = DateTime.Now;
        public string Hostname { get; set; } = "";
        public string PulseVersion { get; set; } = "";
        public int PanelsTotal { get; set; }
        public int CompletedCount { get; set; }
        public int FailedCount { get; set; }
        public bool Cancelled { get; set; }
        public double DurationSeconds { get; set; }
        public int FindingCount { get; set; }
        public int CriticalFindingCount { get; set; }
        public int WarningFindingCount { get; set; }
        public string SupportBundlePath { get; set; } = "";
        public List<string> FailedPanels { get; set; } = new List<string>();
        public List<BaselinePanelSnapshot> Panels { get; set; } = new List<BaselinePanelSnapshot>();
        public List<BaselineFindingSnapshot> Findings { get; set; } = new List<BaselineFindingSnapshot>();
    }

    public class BaselinePanelSnapshot
    {
        public string Name { get; set; } = "";
        public string NavKey { get; set; } = "";
        public string Status { get; set; } = "Pass";
        public int FindingCount { get; set; }
        public int CriticalCount { get; set; }
        public int WarningCount { get; set; }
        public string ReportPath { get; set; } = "";
    }

    public class BaselineFindingSnapshot
    {
        public string Panel { get; set; } = "";
        public string TargetNav { get; set; } = "";
        public string Severity { get; set; } = "Info";
        public string Category { get; set; } = "";
        public string Title { get; set; } = "";
        public string Recommendation { get; set; } = "";
    }
}
