using System.Windows.Media;

namespace Pulse.WPF.Models
{
    /// <summary>
    /// Six summary cards rendered above the inventory list — Model / OS /
    /// Uptime / CPU / RAM / Storage. Each value is paired with a status tier
    /// ("ok" / "warn" / "fail" / "neutral") so the card's status dot can
    /// colour-code the field (e.g. Storage = warn when free space is low).
    /// </summary>
    public class SystemOverviewCards
    {
        // Card 1 — Model
        public string ModelTitle        { get; set; } = "—";       // e.g. "ASUS  System Product Name"
        public string ModelStatus       { get; set; } = "neutral";

        // Card 2 — OS
        public string OsTitle           { get; set; } = "—";       // e.g. "Win 11 Pro  (26200)"
        public string OsStatus          { get; set; } = "neutral";

        // Card 3 — Uptime
        public string UptimeTitle       { get; set; } = "—";       // e.g. "1d 7h 13m"
        public string UptimeStatus      { get; set; } = "neutral";

        // Card 4 — CPU
        public string CpuTitle          { get; set; } = "—";       // e.g. "12th Gen Core i9-12900K"
        public string CpuStatus         { get; set; } = "neutral";

        // Card 5 — RAM
        public string RamTitle          { get; set; } = "—";       // e.g. "64 GB total / 41.7 GB free"
        public string RamStatus         { get; set; } = "neutral";

        // Card 6 — Storage
        public string StorageTitle      { get; set; } = "—";       // e.g. "656.6 GB free  (29% used)"
        public string StorageStatus     { get; set; } = "neutral";
    }

    /// <summary>
    /// One row in the System Inventory panel. Section rows use Level="Section"
    /// and put the heading in Result; data rows have a Label/Value pair.
    /// </summary>
    public class SystemOverviewRow
    {
        public string Section { get; set; }       // null for normal data rows; non-null = section heading
        public string Label   { get; set; } = "";
        public string Value   { get; set; } = "";
        public string Level   { get; set; } = "Info";   // Info / Pass / Warn / Gray / Section
        public Brush  ValueColor { get; set; }          // resolved by the VM at population time
    }

}
