using System.Collections.Generic;

namespace Pulse.WPF.Services
{
    /// <summary>
    /// Reads C:\Pixellot\Data\configuration\cameras.cfg + pip.cfg and
    /// returns an IP → role mapping. Mirrors the Get-PixellotCameraRoles
    /// PowerShell helper in Pulse.ps1; same file format, same semantics.
    /// </summary>
    public interface IPixellotConfigService
    {
        /// <summary>
        /// Returns a fresh role map. Empty dictionary if the config dir
        /// doesn't exist (caller should fall back to OUI / speed heuristics).
        /// </summary>
        Dictionary<string, string> GetRoles();
    }
}
