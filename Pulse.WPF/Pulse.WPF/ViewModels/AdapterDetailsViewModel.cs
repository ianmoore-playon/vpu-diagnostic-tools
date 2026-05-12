using System;
using System.Collections.ObjectModel;
using System.Diagnostics;
using System.Text;
using System.Windows;
using System.Windows.Input;
using Pulse.WPF.Helpers;
using Pulse.WPF.Services;

namespace Pulse.WPF.ViewModels
{
    /// <summary>
    /// VM for the Adapter Details dialog (v0.5.2 §6). Wraps an
    /// <see cref="AdapterDetails"/> POCO + a snapshot of the originating
    /// port's recent activity, and exposes the dialog footer commands.
    ///
    /// Naming: <c>AdapterDetailsViewModel</c> chosen to be unique across the
    /// codebase and not collide with any BCL type — the System.Net types
    /// don't define an "AdapterDetails" class.
    /// </summary>
    public class AdapterDetailsViewModel : ObservableObject
    {
        // ----- Identity -----
        public string Title    { get; }
        public string PortName { get; }

        // ----- Adapter -----
        public string Name        { get; }
        public string Description { get; }
        public string Status      { get; }
        public string LinkSpeed   { get; }
        public string Duplex      { get; }
        public string LocalMac    { get; }

        // ----- IPv4 -----
        public string IPv4Address       { get; }
        public string SubnetMask        { get; }
        public string DefaultGateway    { get; }
        public string DhcpEnabledText   { get; }
        public string DnsServers        { get; }
        public string DhcpServer        { get; }
        public string DhcpLeaseObtained { get; }
        public string DhcpLeaseExpires  { get; }

        // ----- IPv6 -----
        public string IPv6Addresses { get; }
        public string IPv6Gateways  { get; }

        // ----- Driver -----
        public string DriverName    { get; }
        public string DriverVersion { get; }
        public string DriverDate    { get; }

        // ----- Counters -----
        public string IncomingErrors    { get; }
        public string OutgoingErrors    { get; }
        public string IncomingDiscards  { get; }
        public string OutgoingDiscards  { get; }

        // ----- Remote info -----
        public string RemoteIp     { get; }
        public string RemoteMac    { get; }
        public string RemoteVendor { get; }
        public string RemoteRole   { get; }
        public bool   HasRemote    { get; }

        // ----- Recent activity (last ~10) -----
        public ObservableCollection<PortHistoryEntry> RecentHistory { get; } = new ObservableCollection<PortHistoryEntry>();

        // ----- Footer commands -----
        public ICommand OpenNcpaCommand            { get; }
        public ICommand OpenNetworkAndSharingCommand { get; }
        public ICommand CopyAsTextCommand          { get; }
        public ICommand CloseCommand               { get; }

        // Set by the View at construction so CloseCommand can dismiss the
        // dialog without the VM having to know about Window.
        public Action CloseAction { get; set; }

        public AdapterDetailsViewModel(AdapterDetails d, PortViewModel sourcePort)
        {
            if (d == null) d = new AdapterDetails();

            PortName = sourcePort?.Name ?? "";
            Title    = $"{PortName} · Adapter details";

            Name        = Dash(d.Name);
            Description = Dash(d.Description);
            Status      = Dash(d.Status);
            LinkSpeed   = Dash(d.LinkSpeed);
            Duplex      = d.Duplex ?? "";
            LocalMac    = Dash(d.LocalMac);

            IPv4Address       = Dash(d.IPv4Address);
            SubnetMask        = Dash(d.SubnetMask);
            DefaultGateway    = Dash(d.DefaultGateway);
            DhcpEnabledText   = Dash(d.DhcpEnabledText);
            DnsServers        = Dash(d.DnsServers);
            DhcpServer        = Dash(d.DhcpServer);
            DhcpLeaseObtained = Dash(d.DhcpLeaseObtained);
            DhcpLeaseExpires  = Dash(d.DhcpLeaseExpires);

            IPv6Addresses = Dash(d.IPv6Addresses);
            IPv6Gateways  = Dash(d.IPv6Gateways);

            DriverName    = Dash(d.DriverName);
            DriverVersion = Dash(d.DriverVersion);
            DriverDate    = Dash(d.DriverDate);

            IncomingErrors   = d.IncomingPacketsWithErrors.ToString();
            OutgoingErrors   = d.OutgoingPacketsWithErrors.ToString();
            IncomingDiscards = d.IncomingPacketsDiscarded.ToString();
            OutgoingDiscards = d.OutgoingPacketsDiscarded.ToString();

            RemoteIp     = d.RemoteIp;
            RemoteMac    = d.RemoteMac;
            RemoteVendor = d.RemoteVendor;
            RemoteRole   = d.RemoteRole;
            HasRemote    = !string.IsNullOrEmpty(RemoteIp) || !string.IsNullOrEmpty(RemoteMac);

            // Snapshot the last ~10 entries from the live history. We
            // capture rather than bind so the dialog doesn't keep ticking
            // while the user reads it.
            if (sourcePort?.History != null)
            {
                int start = Math.Max(0, sourcePort.History.Count - 10);
                for (int i = start; i < sourcePort.History.Count; i++)
                    RecentHistory.Add(sourcePort.History[i]);
            }

            OpenNcpaCommand              = new RelayCommand(() => SafeStart("ncpa.cpl"));
            OpenNetworkAndSharingCommand = new RelayCommand(OpenNetworkAndSharing);
            CopyAsTextCommand            = new RelayCommand(CopyAsText);
            CloseCommand                 = new RelayCommand(() => CloseAction?.Invoke());
        }

        private static string Dash(string s) => string.IsNullOrEmpty(s) ? "—" : s;

        private static void OpenNetworkAndSharing()
        {
            try
            {
                var psi = new ProcessStartInfo("control")
                {
                    Arguments = "/name Microsoft.NetworkAndSharingCenter",
                    UseShellExecute = true,
                };
                Process.Start(psi);
            }
            catch { /* swallow — same as the action-bar handler. */ }
        }

        private static void SafeStart(string target)
        {
            try
            {
                var psi = new ProcessStartInfo(target) { UseShellExecute = true };
                Process.Start(psi);
            }
            catch { }
        }

        private void CopyAsText()
        {
            // Plain-text snapshot suitable for pasting into a support ticket.
            // Order mirrors the dialog layout.
            var sb = new StringBuilder();
            sb.AppendLine($"=== {Title} ===");
            sb.AppendLine();
            sb.AppendLine("Adapter");
            sb.AppendLine($"  Name        : {Name}");
            sb.AppendLine($"  Description : {Description}");
            sb.AppendLine($"  Status      : {Status}");
            sb.AppendLine($"  Link speed  : {LinkSpeed}");
            if (!string.IsNullOrEmpty(Duplex)) sb.AppendLine($"  Duplex      : {Duplex}");
            sb.AppendLine($"  MAC         : {LocalMac}");
            sb.AppendLine();
            sb.AppendLine("IPv4");
            sb.AppendLine($"  Address     : {IPv4Address}");
            sb.AppendLine($"  Subnet mask : {SubnetMask}");
            sb.AppendLine($"  Gateway     : {DefaultGateway}");
            sb.AppendLine($"  DHCP        : {DhcpEnabledText}");
            sb.AppendLine($"  DNS         : {DnsServers}");
            sb.AppendLine($"  DHCP server : {DhcpServer}");
            sb.AppendLine($"  Lease obtained : {DhcpLeaseObtained}");
            sb.AppendLine($"  Lease expires  : {DhcpLeaseExpires}");
            sb.AppendLine();
            sb.AppendLine("IPv6");
            sb.AppendLine($"  Addresses : {IPv6Addresses}");
            sb.AppendLine($"  Gateways  : {IPv6Gateways}");
            sb.AppendLine();
            sb.AppendLine("Driver");
            sb.AppendLine($"  Name    : {DriverName}");
            sb.AppendLine($"  Version : {DriverVersion}");
            sb.AppendLine($"  Date    : {DriverDate}");
            sb.AppendLine();
            sb.AppendLine("Counters");
            sb.AppendLine($"  In errors    : {IncomingErrors}");
            sb.AppendLine($"  Out errors   : {OutgoingErrors}");
            sb.AppendLine($"  In discards  : {IncomingDiscards}");
            sb.AppendLine($"  Out discards : {OutgoingDiscards}");
            if (HasRemote)
            {
                sb.AppendLine();
                sb.AppendLine("Remote");
                if (!string.IsNullOrEmpty(RemoteIp))     sb.AppendLine($"  IP     : {RemoteIp}");
                if (!string.IsNullOrEmpty(RemoteMac))    sb.AppendLine($"  MAC    : {RemoteMac}");
                if (!string.IsNullOrEmpty(RemoteVendor)) sb.AppendLine($"  Vendor : {RemoteVendor}");
                if (!string.IsNullOrEmpty(RemoteRole))   sb.AppendLine($"  Role   : {RemoteRole}");
            }
            if (RecentHistory.Count > 0)
            {
                sb.AppendLine();
                sb.AppendLine("Recent activity");
                foreach (var h in RecentHistory)
                    sb.AppendLine($"  {h.TimestampLabel}  {h.State,-10}  {h.Note}");
            }

            try { Clipboard.SetText(sb.ToString()); }
            catch { /* clipboard could be locked by another process — silently ignore. */ }
        }
    }
}
