using System.Windows.Media;
using Pulse.WPF.Helpers;

namespace Pulse.WPF.Models
{
    /// <summary>
    /// One volume row in the Disk &amp; System Health "Volumes" list.
    /// Two field families coexist: aggregate strings used by the XAML
    /// (Drive/Free/Total/PercentUsed/Status) plus raw numeric/alias fields
    /// produced by DiskHealthService (DeviceId/FreeGb/TotalGb/Severity/Label).
    /// </summary>
    public class VolumeRow : ObservableObject
    {
        public string Drive            { get; set; } = "";   // "C:"
        public string Role             { get; set; } = "";   // "OS", "Pixellot Data", "Recovery"
        public string Free             { get; set; } = "";   // "220 GB"
        public string Total            { get; set; } = "";   // "500 GB"
        public string PercentUsed      { get; set; } = "";   // "56%"
        public double PercentUsedValue { get; set; }         // 0..100, drives the bar
        public string Status           { get; set; } = "";   // "Healthy", "Low free space"
        public Brush  StatusColor      { get; set; }
        public Brush  BarColor         { get; set; }

        // Aliases / additional fields for DiskHealthService.
        public string DeviceId { get => Drive;  set => Drive = value; }
        public string Severity { get => Status; set => Status = value; }
        public string Label    { get; set; } = "";
        public double FreeGb   { get; set; }
        public double TotalGb  { get; set; }
    }

    /// <summary>
    /// One Pixellot-specific path row (C:\Pixellot\Data\Log etc.) with a size
    /// and a threshold-based status. Aliases support DiskHealthService.
    /// </summary>
    public class PixellotPathRow : ObservableObject
    {
        public string Path         { get; set; } = "";
        public string Description  { get; set; } = "";   // "Recording buffer", "Log archive"
        public string Size         { get; set; } = "";   // "12.4 GB"
        public string Threshold    { get; set; } = "";   // "Warn at 50 GB"
        public string Status       { get; set; } = "";   // "OK", "Approaching limit"
        public Brush  StatusColor  { get; set; }

        // Aliases for DiskHealthService.
        public string Severity      { get => Status;      set => Status = value; }
        public string Label         { get => Description; set => Description = value; }
        public string SizeFormatted { get => Size;        set => Size = value; }
    }
}
