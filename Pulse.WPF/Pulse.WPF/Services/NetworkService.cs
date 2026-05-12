using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Linq;
using System.Net;
using System.Net.NetworkInformation;
using System.Net.Sockets;
using System.Text;
using System.Threading.Tasks;
using Microsoft.Win32;
using Pulse.WPF.Models;

namespace Pulse.WPF.Services
{
    /// <summary>
    /// Pure-C# port of NetworkDiagnostics.psm1 logic. Uses
    /// System.Net.NetworkInformation for adapter enumeration, TcpClient /
    /// UdpClient for the port probes, and System.Net.Dns for domain resolution.
    /// All probes carry a 2 s timeout matching $NetTimeoutMs.
    /// </summary>
    public class NetworkService : INetworkService
    {
        private const int TimeoutMs = 2000;

        /// <summary>
        /// Optional error reporter — when set, every formerly-silent catch in
        /// this service is rerouted here so the Network panel's Live Log can
        /// surface collection failures. NetworkViewModel hooks this in its
        /// constructor (v0.6.4). Mirrors DashboardService.OnSilentError.
        /// </summary>
        public event Action<string, Exception> OnSilentError;

        private void Report(string section, Exception ex) => OnSilentError?.Invoke(section, ex);

        // ---- Canonical probe set ----
        // Reviewed 2026-05-07 against two pcapng captures of a known-working
        // Windows VPU during a live stream:
        //   * TCP/443 to lmi-app26-05.logmein.com dominated outbound TCP
        //     (~1,200 packets across both captures).
        //   * UDP/2088 to a Pixellot Zixi endpoint dominated outbound UDP
        //     (~17,600 packets — this is the live stream itself).
        //   * No traffic to TCP/5672 or UDP/5672 — Pixellot moved away from
        //     Singular AMQP for graphics, so those probes were dropped.
        //   * No traffic to TCP/1402, TCP/1935 (SportzCast) or UDP/443 (Zixi
        //     fallback) — kept but flagged Optional so a failure surfaces as
        //     "venue may not use this" rather than a blocking firewall issue.
        private class PortTestSpec
        {
            public string Protocol;
            public int Port;
            public string Host;
            public bool Reliable;
            // Optional ports are not required for a working stream on every
            // venue. SportzCast (1402/1935) is only used at venues with
            // SportzCast hardware; Zixi UDP/443 is a fallback path for the
            // primary UDP/2088 stream. The recommendations engine softens the
            // language for failures on these so users don't get pointed at a
            // firewall change they don't actually need.
            public bool Optional;
            public string Purpose;
            public string Note;
        }

        private static readonly PortTestSpec[] PortTests =
        {
            new PortTestSpec { Protocol="UDP", Port=53,   Host="8.8.8.8",                Reliable=true,  Purpose="DNS",                                                Note="Real DNS query for pixellot.tv. PASS confirms UDP DNS is working." },
            new PortTestSpec { Protocol="TCP", Port=53,   Host="8.8.8.8",                Reliable=true,  Purpose="DNS",                                                Note="" },
            new PortTestSpec { Protocol="UDP", Port=123,  Host="0.us.pool.ntp.org",       Reliable=true,  Purpose="Clock sync (NTP) — configured peer",                Note="Real NTP request. PASS confirms clock sync is working." },
            new PortTestSpec { Protocol="TCP", Port=443,  Host="pixellot.tv",             Reliable=true,  Purpose="Pixellot management, software updates, video stream", Note="" },
            new PortTestSpec { Protocol="TCP", Port=443,  Host="logmein.com",             Reliable=true,  Purpose="LogMeIn — Windows remote support",                  Note="Heaviest TCP peer in pcapng captures of a working VPU." },
            new PortTestSpec { Protocol="UDP", Port=2088, Host="prod-echo.pixellot.tv",   Reliable=true,  Purpose="Video streaming (Zixi primary)",                    Note="Firewall must allow outbound UDP 2088 to Pixellot servers. Dominant UDP path on a streaming VPU." },
            new PortTestSpec { Protocol="UDP", Port=443,  Host="prod-echo.pixellot.tv",   Reliable=true,  Optional=true,  Purpose="Video streaming (Zixi fallback)",   Note="Optional — fallback path for UDP 2088. Not seen in working-VPU captures." },
            new PortTestSpec { Protocol="TCP", Port=1402, Host="scorebot.sportzcast.net", Reliable=true,  Optional=true,  Purpose="SportzCast scoreboard data (1400-1405)", Note="Optional — venue-specific. Only required at venues with SportzCast hardware." },
        };

        private class DomainTestSpec
        {
            public string Domain;
            public string Purpose;
            public string Note;
            public bool DnsNotExpected;
        }

        private static readonly DomainTestSpec[] DomainTests =
        {
            new DomainTestSpec { Domain="nfhsnetwork.com",                Purpose="Scheduling, events, watermark images" },
            new DomainTestSpec { Domain="pixellot.stream",                Purpose="Broadcast stream to Pixellot servers (Zixi)", DnsNotExpected=true, Note="Stream-only destination - DNS not expected to resolve." },
            new DomainTestSpec { Domain="pixellot.tv",                    Purpose="Pixellot system management and software downloads" },
            new DomainTestSpec { Domain="software.pixellot.tv",           Purpose="Software package downloads and updates" },
            new DomainTestSpec { Domain="sportzcast.net",                 Purpose="SportzCast remote management and updates" },
            new DomainTestSpec { Domain="app.singular.live",              Purpose="Broadcast scoreboard graphics (port 5672 indicator)" },
            new DomainTestSpec { Domain="balena-cloud.com",               Purpose="Linux OS management",                    Note="Required for Linux-based Pixellots." },
            new DomainTestSpec { Domain="logmein.com",                    Purpose="Windows remote control",                 Note="Required for Windows-based Pixellots." },
            new DomainTestSpec { Domain="s3.amazonaws.com",               Purpose="Canopy remote monitoring (leaf-swu)" },
            new DomainTestSpec { Domain="leaf-uploads.s3.amazonaws.com",  Purpose="Canopy uploads" },
            new DomainTestSpec { Domain="leaf-downloads.s3.amazonaws.com",Purpose="Canopy downloads" },
        };

        // ----- Adapters -----

        /// <summary>
        /// Returns the single primary internet-bound NIC (the one with a
        /// non-zero default gateway). Mirrors the logic in
        /// <see cref="TryFindInternetInterfaceIndex"/> but produces a fully
        /// populated <see cref="NetworkAdapterRow"/>. Returns null on failure.
        /// </summary>
        public NetworkAdapterRow GetPrimaryInternetAdapter()
        {
            try
            {
                int internetIfIndex = TryFindInternetInterfaceIndex();
                if (internetIfIndex == 0) return null;

                foreach (var nic in NetworkInterface.GetAllNetworkInterfaces())
                {
                    if (nic.OperationalStatus != OperationalStatus.Up) continue;
                    if (nic.NetworkInterfaceType == NetworkInterfaceType.Loopback ||
                        nic.NetworkInterfaceType == NetworkInterfaceType.Tunnel) continue;

                    IPInterfaceProperties props;
                    // Per-NIC GetIPProperties() can throw "The network location
                    // cannot be reached" on transient NICs (VPN tunnels mid-
                    // teardown, Hyper-V virtual switches). Skipping the NIC is
                    // correct; logging every per-NIC failure would flood the
                    // panel — kept defensive.
                    try { props = nic.GetIPProperties(); }
                    catch { continue; }

                    int ifIdx;
                    try { ifIdx = props.GetIPv4Properties()?.Index ?? 0; }
                    catch { ifIdx = 0; }
                    if (ifIdx != internetIfIndex) continue;

                    string ip = "—";
                    var v4 = props.UnicastAddresses
                        .FirstOrDefault(a => a.Address.AddressFamily == AddressFamily.InterNetwork);
                    if (v4 != null) ip = v4.Address.ToString();

                    bool up = nic.OperationalStatus == OperationalStatus.Up;
                    return new NetworkAdapterRow
                    {
                        Name = nic.Name,
                        Description = nic.Description ?? "",
                        Ip = ip,
                        Speed = FormatSpeed(nic.Speed),
                        LinkState = up ? "Up" : "Down",
                        Purpose = "Internet",
                    };
                }
            }
            catch (Exception _ex) { Report("Adapter enum", _ex); }
            return null;
        }

        public List<NetworkAdapterRow> GetAdapters()
        {
            var rows = new List<NetworkAdapterRow>();
            int internetIfIndex = TryFindInternetInterfaceIndex();

            try
            {
                var ifs = NetworkInterface.GetAllNetworkInterfaces()
                    .Where(n => n.OperationalStatus == OperationalStatus.Up)
                    .Where(n => n.NetworkInterfaceType != NetworkInterfaceType.Loopback &&
                                n.NetworkInterfaceType != NetworkInterfaceType.Tunnel)
                    .OrderBy(n => n.Name)
                    .Take(8); // mirror "Select-Object -First 6" + a little headroom

                foreach (var nic in ifs)
                {
                    string ip = "—";
                    int ifIdx = 0;
                    // Per-NIC properties read can throw on transient interfaces;
                    // skip the row's IP/index rather than aborting the whole
                    // adapter list. Kept defensive — same reasoning as the
                    // GetPrimaryInternetAdapter inner catch.
                    try
                    {
                        var props = nic.GetIPProperties();
                        ifIdx = props.GetIPv4Properties()?.Index ?? 0;
                        var v4 = props.UnicastAddresses
                            .FirstOrDefault(a => a.Address.AddressFamily == AddressFamily.InterNetwork);
                        if (v4 != null) ip = v4.Address.ToString();
                    }
                    catch { }

                    rows.Add(new NetworkAdapterRow
                    {
                        Name = nic.Name,
                        Ip = ip,
                        Speed = FormatSpeed(nic.Speed),
                        Purpose = AdapterPurpose(nic.Description, ip, ifIdx, internetIfIndex),
                    });
                }
            }
            catch (Exception _ex)
            {
                // Diagnostic services must not throw on a misconfigured machine.
                Report("Adapter enum", _ex);
            }

            return rows;
        }

        // Mirrors Get-AdapterPurpose in NetworkDiagnostics.psm1.
        private static string AdapterPurpose(string desc, string ip, int ifIndex, int internetIfIndex)
        {
            bool isCameraNic = !string.IsNullOrEmpty(desc) &&
                (desc.IndexOf("I210", StringComparison.OrdinalIgnoreCase) >= 0 ||
                 desc.IndexOf("I350", StringComparison.OrdinalIgnoreCase) >= 0 ||
                 desc.IndexOf("82574L", StringComparison.OrdinalIgnoreCase) >= 0 ||
                 desc.IndexOf("I211", StringComparison.OrdinalIgnoreCase) >= 0 ||
                 desc.IndexOf("GIE7", StringComparison.OrdinalIgnoreCase) >= 0);

            if (!string.IsNullOrEmpty(ip) && ip.StartsWith("169.254.", StringComparison.Ordinal))
                return isCameraNic ? "Camera (link-local)" : "Link-local (no DHCP)";
            if (internetIfIndex != 0 && ifIndex == internetIfIndex)
                return "Internet";
            if (isCameraNic) return "Camera NIC port";
            return "Auxiliary";
        }

        // Pure static helper — returns 0 on any failure. Kept defensive so it
        // can be safely called from anywhere (including ctor / hot paths)
        // without an OnSilentError handler in scope. The outer callers that
        // depend on its value already log meaningfully when they get 0.
        private static int TryFindInternetInterfaceIndex()
        {
            try
            {
                foreach (var nic in NetworkInterface.GetAllNetworkInterfaces())
                {
                    if (nic.OperationalStatus != OperationalStatus.Up) continue;
                    var props = nic.GetIPProperties();
                    var hasGw = props.GatewayAddresses
                        .Any(g => g.Address != null &&
                                  g.Address.AddressFamily == AddressFamily.InterNetwork &&
                                  !g.Address.ToString().StartsWith("0."));
                    if (hasGw)
                    {
                        try { return props.GetIPv4Properties()?.Index ?? 0; }
                        catch { return 0; }
                    }
                }
            }
            catch { }
            return 0;
        }

        // ----- IP configuration -----

        public IpConfigurationViewModel GetIpConfiguration()
        {
            var cfg = new IpConfigurationViewModel
            {
                IpAddress = "—",
                SubnetMask = "—",
                Gateway = "—",
                DnsServers = "—",
                Dhcp = "Unknown",
                NtpServer = "—",
                NtpSource = "Not queried",
            };

            try
            {
                var primary = NetworkInterface.GetAllNetworkInterfaces()
                    .Where(n => n.OperationalStatus == OperationalStatus.Up)
                    .Select(n => new { Nic = n, Props = SafeGetProps(n) })
                    .FirstOrDefault(x => x.Props != null && x.Props.GatewayAddresses
                        .Any(g => g.Address != null &&
                                  g.Address.AddressFamily == AddressFamily.InterNetwork &&
                                  !g.Address.ToString().StartsWith("0.")));

                if (primary != null && primary.Props != null)
                {
                    // v0.6.5: populate AdapterName so the Dashboard's
                    // "Uplink Adapter" row renders the NIC description
                    // (e.g. "Intel I210 Gigabit") instead of a blank/em-dash.
                    // Description is the human-readable form; fall back to
                    // Name (e.g. "Ethernet 2") when Description is empty.
                    cfg.AdapterName = !string.IsNullOrWhiteSpace(primary.Nic.Description)
                        ? primary.Nic.Description
                        : primary.Nic.Name ?? "";

                    var v4 = primary.Props.UnicastAddresses
                        .FirstOrDefault(a => a.Address.AddressFamily == AddressFamily.InterNetwork);
                    if (v4 != null)
                    {
                        cfg.IpAddress = v4.Address.ToString();
                        cfg.SubnetMask = v4.IPv4Mask?.ToString() ?? PrefixToMask(v4.PrefixLength);
                    }

                    var gw = primary.Props.GatewayAddresses
                        .FirstOrDefault(g => g.Address != null &&
                                             g.Address.AddressFamily == AddressFamily.InterNetwork);
                    if (gw != null) cfg.Gateway = gw.Address.ToString();

                    var dns = primary.Props.DnsAddresses
                        .Where(d => d.AddressFamily == AddressFamily.InterNetwork)
                        .Select(d => d.ToString())
                        .ToArray();
                    if (dns.Length > 0) cfg.DnsServers = string.Join(", ", dns);

                    try
                    {
                        var v4Props = primary.Props.GetIPv4Properties();
                        cfg.Dhcp = v4Props != null && v4Props.IsDhcpEnabled ? "Enabled" : "Disabled";
                    }
                    catch (Exception _ex) { Report("IP config", _ex); }
                }
            }
            catch (Exception _ex) { Report("IP config", _ex); }

            // Configured NTP peer — registry. Live source — w32tm /query /source.
            try
            {
                using (var key = Registry.LocalMachine.OpenSubKey(
                    @"SYSTEM\CurrentControlSet\Services\W32Time\Parameters"))
                {
                    var ns = key?.GetValue("NtpServer") as string;
                    if (!string.IsNullOrEmpty(ns))
                    {
                        var first = ns.Split(',')[0].Trim();
                        // Strip the ",0x9" flag suffix if present.
                        var sp = first.IndexOf(' ');
                        if (sp > 0) first = first.Substring(0, sp);
                        cfg.NtpServer = first;
                    }
                }
            }
            catch (Exception _ex) { Report("NTP read", _ex); }

            try
            {
                var psi = new ProcessStartInfo("w32tm", "/query /source")
                {
                    UseShellExecute = false,
                    RedirectStandardOutput = true,
                    RedirectStandardError = true,
                    CreateNoWindow = true,
                };
                using (var p = Process.Start(psi))
                {
                    if (p != null && p.WaitForExit(1500))
                    {
                        var src = (p.StandardOutput.ReadToEnd() ?? "").Trim();
                        if (!string.IsNullOrEmpty(src)) cfg.NtpSource = src;
                    }
                }
            }
            catch (Exception _ex) { Report("NTP source", _ex); }

            return cfg;
        }

        // Pure static helper used by the GetIpConfiguration LINQ filter. Kept
        // defensive — the null return is the signal to skip the NIC; logging
        // every per-NIC props read on a 12-NIC machine would be noise.
        private static IPInterfaceProperties SafeGetProps(NetworkInterface n)
        {
            try { return n.GetIPProperties(); } catch { return null; }
        }

        // ConvertTo-DottedMask in NetworkDiagnostics.psm1
        private static string PrefixToMask(int prefix)
        {
            if (prefix < 0 || prefix > 32) return "/" + prefix;
            if (prefix == 0) return "0.0.0.0";
            uint mask = uint.MaxValue << (32 - prefix);
            return $"{(mask >> 24) & 0xFF}.{(mask >> 16) & 0xFF}.{(mask >> 8) & 0xFF}.{mask & 0xFF}";
        }

        private static string FormatSpeed(long bps)
        {
            if (bps <= 0) return "—";
            if (bps >= 1_000_000_000L) return $"{bps / 1_000_000_000L} Gbps";
            if (bps >= 1_000_000L) return $"{bps / 1_000_000L} Mbps";
            return $"{bps} bps";
        }

        // ----- Connectivity probes -----

        public async Task<bool> CheckInternetAsync()
        {
            // Two-target ping, mirrors the 8.8.8.8 / 1.1.1.1 fallback.
            if (await PingAsync("8.8.8.8")) return true;
            return await PingAsync("1.1.1.1");
        }

        // Converted to instance method (v0.6.4) so it can route ping failures
        // through Report instead of swallowing them. Behaviour-preserving:
        // still returns false on any exception.
        private async Task<bool> PingAsync(string host)
        {
            try
            {
                using (var ping = new Ping())
                {
                    var r = await Task.Run(() => ping.Send(host, TimeoutMs)).ConfigureAwait(false);
                    return r != null && r.Status == IPStatus.Success;
                }
            }
            catch (Exception _ex) { Report("Ping", _ex); return false; }
        }

        public async Task<List<PortTestResult>> RunPortTestsAsync()
        {
            // Snapshot the static spec list so we can override individual spec
            // fields per-run without mutating the canonical array. The NTP
            // probe substitutes its Host with the box's actual configured
            // W32Time peer (Pixellot's own NTP server on a real VPU) instead
            // of the public ntp.org pool — that way we're testing the path
            // the box actually uses, not a path we picked.
            var specs = PortTests.Select(CloneSpec).ToList();
            var configuredNtp = TryGetConfiguredNtpServer();
            if (!string.IsNullOrEmpty(configuredNtp))
            {
                foreach (var s in specs)
                {
                    if (s.Protocol == "UDP" && s.Port == 123)
                    {
                        s.Host = configuredNtp;
                        s.Purpose = $"Clock sync (NTP) — configured peer";
                    }
                }
            }

            var tasks = specs.Select(RunOnePortTestAsync).ToArray();
            var results = await Task.WhenAll(tasks).ConfigureAwait(false);
            return results.ToList();
        }

        private static PortTestSpec CloneSpec(PortTestSpec s)
        {
            return new PortTestSpec
            {
                Protocol = s.Protocol,
                Port = s.Port,
                Host = s.Host,
                Reliable = s.Reliable,
                Purpose = s.Purpose,
                Note = s.Note,
            };
        }

        // Reads the configured NTP peer out of the W32Time registry — same
        // value GetIpConfiguration() surfaces for the IP card. Strips the
        // ",0x9" flag suffix Windows appends. Returns null if the key is
        // missing or empty so the NTP probe falls back to the static spec
        // host (the public ntp.org pool). Pure static helper, kept defensive.
        private static string TryGetConfiguredNtpServer()
        {
            try
            {
                using (var key = Registry.LocalMachine.OpenSubKey(
                    @"SYSTEM\CurrentControlSet\Services\W32Time\Parameters"))
                {
                    var ns = key?.GetValue("NtpServer") as string;
                    if (string.IsNullOrEmpty(ns)) return null;
                    var first = ns.Split(',')[0].Trim();
                    var sp = first.IndexOf(' ');
                    if (sp > 0) first = first.Substring(0, sp);
                    return string.IsNullOrEmpty(first) ? null : first;
                }
            }
            catch { return null; }
        }

        // Converted to instance method (v0.6.4) so probe dispatch failures
        // (DNS resolution mid-probe, unexpected exceptions) can be reported
        // through the new OnSilentError surface instead of being silently
        // converted to Fail rows.
        private async Task<PortTestResult> RunOnePortTestAsync(PortTestSpec spec)
        {
            var row = new PortTestResult
            {
                Protocol = spec.Protocol,
                Port = spec.Port,
                Host = spec.Host,
                Purpose = spec.Purpose,
                Optional = spec.Optional,
                Status = "Info",
            };
            if (!spec.Reliable) return row;

            bool ok = false;
            try
            {
                if (spec.Protocol == "TCP")
                    ok = await TestTcpAsync(spec.Host, spec.Port).ConfigureAwait(false);
                else if (spec.Port == 53)
                    ok = await TestUdpDnsAsync(spec.Host).ConfigureAwait(false);
                else if (spec.Port == 123)
                    ok = await TestUdpNtpAsync(spec.Host).ConfigureAwait(false);
                else
                    ok = await TestUdpEchoAsync(spec.Host, spec.Port).ConfigureAwait(false);
            }
            catch (Exception _ex)
            {
                Report($"Port probe {spec.Protocol}/{spec.Port}", _ex);
                ok = false;
            }

            row.Status = ok ? "Pass" : "Fail";
            return row;
        }

        // Converted to instance method (v0.6.4) — surfaces TCP connect
        // exceptions ("No such host is known", "actively refused") through
        // OnSilentError so the live log can show the underlying error
        // alongside the Fail row.
        private async Task<bool> TestTcpAsync(string host, int port)
        {
            try
            {
                using (var tcp = new TcpClient())
                {
                    var connect = tcp.ConnectAsync(host, port);
                    var done = await Task.WhenAny(connect, Task.Delay(TimeoutMs)).ConfigureAwait(false);
                    return done == connect && tcp.Connected;
                }
            }
            catch (Exception _ex) { Report($"TCP probe {host}:{port}", _ex); return false; }
        }

        // Real DNS A-record query for pixellot.tv. Mirrors Test-UdpDns.
        // Instance method (v0.6.4) so probe failures route through Report.
        private Task<bool> TestUdpDnsAsync(string server)
        {
            return Task.Run(() =>
            {
                UdpClient udp = null;
                try
                {
                    udp = new UdpClient();
                    udp.Client.ReceiveTimeout = TimeoutMs;
                    udp.Client.SendTimeout = TimeoutMs;
                    var q = new byte[]
                    {
                        0xAB,0x01,0x01,0x00,0x00,0x01,0x00,0x00,0x00,0x00,0x00,0x00,
                        0x08,(byte)'p',(byte)'i',(byte)'x',(byte)'e',
                        (byte)'l',(byte)'l',(byte)'o',(byte)'t',
                        0x02,(byte)'t',(byte)'v',
                        0x00,0x00,0x01,0x00,0x01
                    };
                    var ep = new IPEndPoint(IPAddress.Parse(server), 53);
                    udp.Send(q, q.Length, ep);
                    IPEndPoint from = null;
                    var r = udp.Receive(ref from);
                    return r != null && r.Length > 6 && (r[3] & 0x0F) == 0;
                }
                catch (Exception _ex) { Report("DNS probe", _ex); return false; }
                // udp?.Close() in finally — defensive cleanup, swallow per
                // .NET idiom; logging a dispose failure adds no value.
                finally { try { udp?.Close(); } catch { } }
            });
        }

        // NTP probe — two-tier with a w32tm fallback to avoid the same false-
        // negative class of bug we found in the Pixellot Network Check. Their
        // tool ships a malformed 65-byte packet that strict NTP servers silently
        // drop, producing a false ❌ even when w32tm syncs cleanly against the
        // same host. Our defence:
        //   1. Send a fully-formed RFC 5905 NTPv4 client request (48 bytes,
        //      version 4, mode 3, real Transmit Timestamp).
        //   2. Validate the response is mode 4 (server) and >= 48 bytes — not
        //      just "any UDP packet came back".
        //   3. If the direct probe fails, run `w32tm /stripchart /computer:<host>
        //      /samples:1 /dataonly` and report success when Windows itself
        //      can complete a sample. This mirrors the manual cross-check
        //      Support uses to rule out a Pixellot-style false negative.
        private async Task<bool> TestUdpNtpAsync(string server)
        {
            if (await DirectNtpProbeAsync(server).ConfigureAwait(false)) return true;
            return await TestNtpViaW32tmAsync(server).ConfigureAwait(false);
        }

        // Properly-formed NTPv4 client request. Populates the Transmit Timestamp
        // and validates the server's response. RFC 5905 §7.3.
        // Instance method (v0.6.4) so probe failures route through Report.
        private Task<bool> DirectNtpProbeAsync(string server)
        {
            return Task.Run(() =>
            {
                UdpClient udp = null;
                try
                {
                    var addrs = ResolveAddrs(server);
                    if (addrs == null || addrs.Length == 0) return false;

                    var pkt = new byte[48];
                    // First byte: LI=0, VN=4 (NTPv4), Mode=3 (client) -> 0x23.
                    pkt[0] = 0x23;
                    // Transmit Timestamp (bytes 40-47), seconds + fraction
                    // since the NTP epoch, big-endian. Servers echo this value
                    // back as the Originate Timestamp; populating it makes the
                    // request indistinguishable from a real ntpd / w32tm client.
                    var ntpEpoch = new DateTime(1900, 1, 1, 0, 0, 0, DateTimeKind.Utc);
                    var elapsed = DateTime.UtcNow - ntpEpoch;
                    double secs = elapsed.TotalSeconds;
                    uint seconds = (uint)secs;
                    uint fraction = (uint)((secs - seconds) * 4294967296.0); // 2^32
                    pkt[40] = (byte)((seconds >> 24) & 0xFF);
                    pkt[41] = (byte)((seconds >> 16) & 0xFF);
                    pkt[42] = (byte)((seconds >> 8) & 0xFF);
                    pkt[43] = (byte)(seconds & 0xFF);
                    pkt[44] = (byte)((fraction >> 24) & 0xFF);
                    pkt[45] = (byte)((fraction >> 16) & 0xFF);
                    pkt[46] = (byte)((fraction >> 8) & 0xFF);
                    pkt[47] = (byte)(fraction & 0xFF);

                    udp = new UdpClient();
                    udp.Client.ReceiveTimeout = TimeoutMs;
                    udp.Client.SendTimeout = TimeoutMs;
                    var ep = new IPEndPoint(addrs[0], 123);
                    udp.Send(pkt, 48, ep);
                    IPEndPoint from = null;
                    var r = udp.Receive(ref from);
                    if (r == null || r.Length < 48) return false;

                    // Validate the response is an NTP server response.
                    int mode = r[0] & 0x07;          // bits 5-7 of byte 0
                    if (mode != 4) return false;     // 4 = server
                    return true;
                }
                catch (Exception _ex) { Report("NTP probe", _ex); return false; }
                // udp?.Close() in finally — defensive cleanup, swallow per
                // .NET idiom; logging a dispose failure adds no value.
                finally { try { udp?.Close(); } catch { } }
            });
        }

        // w32tm fallback — runs `w32tm /stripchart /computer:<host> /samples:1
        // /dataonly` and returns true when Windows successfully samples the
        // remote clock. Output we treat as success looks like:
        //   "16:42:30, +00.0001234s"
        // Output we treat as failure looks like:
        //   "16:42:30, error: 0x800705B4 (timeout)"
        // Instance method (v0.6.4) so probe failures route through Report.
        private Task<bool> TestNtpViaW32tmAsync(string server)
        {
            return Task.Run(() =>
            {
                try
                {
                    var psi = new ProcessStartInfo("w32tm",
                        $"/stripchart /computer:{server} /samples:1 /dataonly")
                    {
                        UseShellExecute = false,
                        RedirectStandardOutput = true,
                        RedirectStandardError = true,
                        CreateNoWindow = true,
                    };
                    using (var p = Process.Start(psi))
                    {
                        if (p == null) return false;
                        // Stripchart resolves DNS + does one sample. 4 s is
                        // generous; default w32tm timeout is ~2 s.
                        if (!p.WaitForExit(4000))
                        {
                            // p.Kill() — best-effort cleanup of a hung
                            // w32tm.exe; if it throws (already exited), the
                            // result is still a Fail. Defensive, kept silent.
                            try { p.Kill(); } catch { }
                            return false;
                        }
                        var stdout = p.StandardOutput.ReadToEnd() ?? "";
                        if (stdout.IndexOf("error", StringComparison.OrdinalIgnoreCase) >= 0)
                            return false;
                        // Successful sample line: "HH:MM:SS, +00.0001234s"
                        return System.Text.RegularExpressions.Regex.IsMatch(
                            stdout, @",\s*[+-]\d");
                    }
                }
                catch (Exception _ex) { Report("NTP probe (w32tm)", _ex); return false; }
            });
        }

        // Instance method (v0.6.4) so probe failures route through Report.
        private Task<bool> TestUdpEchoAsync(string server, int port)
        {
            return Task.Run(() =>
            {
                UdpClient udp = null;
                try
                {
                    var addrs = ResolveAddrs(server);
                    if (addrs == null || addrs.Length == 0) return false;
                    var payload = Encoding.ASCII.GetBytes($"testing UDP on port {port}");
                    udp = new UdpClient();
                    udp.Client.ReceiveTimeout = TimeoutMs;
                    udp.Client.SendTimeout = TimeoutMs;
                    var ep = new IPEndPoint(addrs[0], port);
                    udp.Send(payload, payload.Length, ep);
                    IPEndPoint from = null;
                    var r = udp.Receive(ref from);
                    return Encoding.ASCII.GetString(r) == $"testing UDP on port {port}";
                }
                catch (Exception _ex) { Report($"UDP probe :{port}", _ex); return false; }
                // udp?.Close() in finally — defensive cleanup, swallow per
                // .NET idiom; logging a dispose failure adds no value.
                finally { try { udp?.Close(); } catch { } }
            });
        }

        // Pure static helper — Dns.GetHostAddressesAsync wrapper with a
        // hard timeout. Returns null on failure; callers already treat null
        // as "no probe target" and surface their own Fail row. Kept defensive.
        private static IPAddress[] ResolveAddrs(string host)
        {
            try
            {
                var task = Dns.GetHostAddressesAsync(host);
                if (!task.Wait(TimeoutMs)) return null;
                return task.Result;
            }
            catch { return null; }
        }

        // ----- Domain tests -----

        public async Task<List<DomainTestResult>> RunDomainTestsAsync()
        {
            var tasks = DomainTests.Select(RunOneDomainTestAsync).ToArray();
            var results = await Task.WhenAll(tasks).ConfigureAwait(false);
            return results.ToList();
        }

        // Instance method (v0.6.4) so DNS resolve failures route through
        // Report. Behaviour preserved: on exception the row's Status stays
        // "Fail" and the original ResolvedTo placeholder ("—") is retained.
        private async Task<DomainTestResult> RunOneDomainTestAsync(DomainTestSpec spec)
        {
            var row = new DomainTestResult { Domain = spec.Domain, ResolvedTo = "—", Status = "Info" };
            if (spec.DnsNotExpected)
            {
                // v0.6.5: render a friendlier label than the bare "Info"
                // status word. pixellot.stream is a Zixi broadcast target —
                // it never resolves via DNS by design.
                row.Status = "Stream-only (DNS not expected)";
                return row;
            }

            try
            {
                var t = Dns.GetHostAddressesAsync(spec.Domain);
                var done = await Task.WhenAny(t, Task.Delay(TimeoutMs)).ConfigureAwait(false);
                if (done != t || t.Result == null || t.Result.Length == 0)
                {
                    row.Status = "Fail";
                    return row;
                }
                row.ResolvedTo = t.Result[0].ToString();
                row.Status = "Pass";
            }
            catch (Exception _ex) { Report($"DNS resolve {spec.Domain}", _ex); row.Status = "Fail"; }
            return row;
        }
    }
}
