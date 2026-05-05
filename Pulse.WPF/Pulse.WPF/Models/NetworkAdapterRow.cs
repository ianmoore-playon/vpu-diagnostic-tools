namespace Pulse.WPF.Models
{
    /// <summary>One row in the Network Adapters table on the Network panel.</summary>
    public class NetworkAdapterRow
    {
        public string Name { get; set; }       // "Ethernet 13"
        public string Ip { get; set; }
        public string Speed { get; set; }      // "1 Gbps"
        public string Purpose { get; set; }    // "Internet" | "Camera (link-local)" | "Aux"
    }
}
