using System.Windows.Media;
using Pulse.WPF.Helpers;

namespace Pulse.WPF.Models
{
    /// <summary>
    /// One PoE port reading on the ADLINK SmartPoE module. Voltage / current /
    /// wattage are formatted strings so the XAML doesn't need a converter for
    /// units (the WinForms version does the same).
    /// </summary>
    public class PoePortReading : ObservableObject
    {
        public string Port    { get; set; } = "";   // "Port 1"
        public string State   { get; set; } = "";   // "Powered", "Off", "Fault"
        public string Voltage { get; set; } = "";   // "53.8 V"
        public string Current { get; set; } = "";   // "180 mA"
        public string Wattage { get; set; } = "";   // "9.7 W"
        public Brush  StateColor { get; set; }
    }

    /// <summary>
    /// One row in the NIC link-uptime list. Tells the agent how long each
    /// adapter has been linked at its current speed (drives the "did this
    /// flap recently?" question).
    /// </summary>
    public class NicUptime : ObservableObject
    {
        public string Adapter { get; set; } = "";
        public string Speed   { get; set; } = "";   // "1 Gbps"
        public string Uptime  { get; set; } = "";   // "3d 14h", "12 min"
        public Brush  UptimeColor { get; set; }
    }
}
