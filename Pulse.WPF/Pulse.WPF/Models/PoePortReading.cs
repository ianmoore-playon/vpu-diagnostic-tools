namespace Pulse.WPF.Models
{
    /// <summary>One PoE port reading (P1..P4). Populated from the camera-side
    /// PoE service when available; on machines without a PoE NIC this is empty.</summary>
    public class PoePortReading
    {
        public string Port { get; set; }    // "P1"
        public double Voltage { get; set; }
        public double Current { get; set; }
        public double Watts { get; set; }
        public bool PoeOn { get; set; }
    }
}
