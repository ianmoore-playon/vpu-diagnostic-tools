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
        /// Returns a fresh role map keyed by camera IP. Empty dictionary if the
        /// config dir doesn't exist (caller should fall back to OUI / speed
        /// heuristics).
        /// </summary>
        Dictionary<string, string> GetRoles();

        /// <summary>
        /// Returns a fresh role map keyed by camera MAC, uppercased and
        /// dash-separated (e.g. "00-30-6C-AB-CD-EF"). Empty dictionary when no
        /// cfg sections contain a MAC field. Used by RemoteDeviceResolver so
        /// role attribution survives an IP being recycled by DHCP.
        /// </summary>
        Dictionary<string, string> GetRolesByMac();

        /// <summary>Absolute path to cameras.cfg (may not exist on disk).</summary>
        string CamerasCfgPath { get; }

        /// <summary>True if the cameras.cfg file is readable from disk right now.</summary>
        bool CamerasCfgExists { get; }
    }
}
