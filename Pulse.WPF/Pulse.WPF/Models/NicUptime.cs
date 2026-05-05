namespace Pulse.WPF.Models
{
    /// <summary>NIC link uptime row on the Hardware panel — coarse buckets,
    /// not precise wall-clock minutes. ">48h" is the "stable" threshold.</summary>
    public class NicUptime
    {
        public string Name { get; set; }
        public string Uptime { get; set; }  // ">48h" or "2h 15m"
    }
}
