using System;
using System.Collections.Generic;
using System.IO;
using Microsoft.Win32;

namespace Pulse.WPF.Helpers
{
    /// <summary>
    /// Single source of truth for the Pixellot install root.
    /// R13 fix from the four-agent review: services and helpers were
    /// hardcoding @"C:\Pixellot\..." across the codebase. On a VPU where
    /// Pixellot was installed on D:\, every one of those paths silently
    /// returned empty data — disk-health bytes, camera config, log feed,
    /// recordings, etc. — and the panels read as healthy/empty rather than
    /// surfacing a real install-path mismatch.
    ///
    /// Discovery order (first match wins):
    ///   1. Registry: HKLM\SOFTWARE\Pixellot.InstallPath (REG_SZ)
    ///   2. Registry: HKLM\SOFTWARE\WOW6432Node\Pixellot.InstallPath (REG_SZ)
    ///   3. Environment variable PULSE_PIXELLOT_ROOT (escape hatch for QA)
    ///   4. Candidate drive scan: C:\Pixellot, D:\Pixellot, E:\Pixellot
    ///   5. Fallback: C:\Pixellot (keeps old behaviour even when nothing's
    ///      installed, so callers that build a path string don't get null)
    ///
    /// Resolution is cached for the lifetime of the process. Pulse can be
    /// restarted on the rare case the install location changes mid-session.
    /// </summary>
    public static class PixellotInstallPath
    {
        private static readonly object _gate = new object();
        private static string _cachedRoot;

        /// <summary>
        /// Returns the Pixellot install root (e.g. "C:\Pixellot" or
        /// "D:\Pixellot"). Always non-null; falls back to "C:\Pixellot"
        /// when nothing can be discovered so callers can safely concatenate.
        /// Use <see cref="IsDiscovered"/> to distinguish a real discovery
        /// from the fallback.
        /// </summary>
        public static string Root
        {
            get
            {
                lock (_gate)
                {
                    if (_cachedRoot != null) return _cachedRoot;
                    _cachedRoot = Discover();
                    return _cachedRoot;
                }
            }
        }

        /// <summary>
        /// True when Discover() actually located the Pixellot install
        /// (registry or filesystem). False if Root is returning the
        /// fallback "C:\Pixellot".
        /// </summary>
        public static bool IsDiscovered { get; private set; }

        /// <summary>
        /// Combine a sub-path beneath the install root. Same semantics as
        /// Path.Combine(Root, sub).
        /// </summary>
        public static string Combine(params string[] subPaths)
        {
            var all = new List<string> { Root };
            all.AddRange(subPaths ?? Array.Empty<string>());
            return Path.Combine(all.ToArray());
        }

        /// <summary>
        /// For tests only — force the cache to a known value. Pass null to
        /// clear (next access will re-discover).
        /// </summary>
        public static void Override(string root)
        {
            lock (_gate)
            {
                _cachedRoot = root;
                IsDiscovered = !string.IsNullOrEmpty(root);
            }
        }

        private static string Discover()
        {
            IsDiscovered = false;

            // 1+2. Registry keys.
            foreach (var hive in new[] { @"SOFTWARE\Pixellot", @"SOFTWARE\WOW6432Node\Pixellot" })
            {
                try
                {
                    using (var k = Registry.LocalMachine.OpenSubKey(hive))
                    {
                        var ip = k?.GetValue("InstallPath") as string;
                        if (!string.IsNullOrEmpty(ip) && Directory.Exists(ip))
                        {
                            IsDiscovered = true;
                            return ip.TrimEnd('\\');
                        }
                    }
                }
                catch { }
            }

            // 3. Environment escape hatch (lets QA point Pulse at a fake tree).
            try
            {
                var env = Environment.GetEnvironmentVariable("PULSE_PIXELLOT_ROOT");
                if (!string.IsNullOrEmpty(env) && Directory.Exists(env))
                {
                    IsDiscovered = true;
                    return env.TrimEnd('\\');
                }
            }
            catch { }

            // 4. Candidate drive scan.
            foreach (var drive in new[] { "C", "D", "E", "F" })
            {
                try
                {
                    var path = drive + @":\Pixellot";
                    if (Directory.Exists(path))
                    {
                        IsDiscovered = true;
                        return path;
                    }
                }
                catch { }
            }

            // 5. Fallback. Don't return null/empty so callers that build a
            // path string aren't penalised on a non-VPU machine.
            return @"C:\Pixellot";
        }
    }
}
