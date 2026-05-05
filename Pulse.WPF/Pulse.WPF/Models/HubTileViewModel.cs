namespace Pulse.WPF.Models
{
    /// <summary>One tile on the Home / System Overview panel. Despite the
    /// "ViewModel" suffix this is a plain DTO — Title/Description/IconKey/TargetNav
    /// are static once constructed; the panel ViewModel exposes a collection
    /// of these and binds the click to nav target switch.</summary>
    public class HubTileViewModel
    {
        public string Title { get; set; }
        public string Description { get; set; }
        public string IconKey { get; set; }    // Material Design icon key
        public string TargetNav { get; set; }  // "Network", "Camera", etc.
    }
}
