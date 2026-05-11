using System;
using System.IO;

namespace Pulse.WPF.Models
{
    /// <summary>
    /// One saved diagnostic-run snapshot, listed in the Reports panel.
    /// Bundles are plain .txt files in %LOCALAPPDATA%\Pulse.WPF\Reports —
    /// produced today by the System Overview "Copy as text" path and the
    /// per-panel Live Log "Copy" actions; later by the real diagnostic
    /// engine.
    ///
    /// Pre-computes TimestampLabel + SizeLabel so the ListBox's DataTemplate
    /// can bind without converters.
    /// </summary>
    public class Report
    {
        public string FileName  { get; set; }
        public long   SizeBytes { get; set; }
        public DateTime Timestamp { get; set; }

        /// <summary>First ~200 chars of the file body — shown as the preview
        /// line under the timestamp in the report list.</summary>
        public string Notes { get; set; }

        public string TimestampLabel => Timestamp.ToString("yyyy-MM-dd HH:mm");

        public string SizeLabel
        {
            get
            {
                if (SizeBytes < 1024) return $"{SizeBytes} B";
                if (SizeBytes < 1024 * 1024) return $"{SizeBytes / 1024.0:F1} KB";
                return $"{SizeBytes / (1024.0 * 1024.0):F1} MB";
            }
        }
    }
}
