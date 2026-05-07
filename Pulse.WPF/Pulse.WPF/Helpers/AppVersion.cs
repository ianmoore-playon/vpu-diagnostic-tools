using System;
using System.Reflection;

namespace Pulse.WPF.Helpers
{
    /// <summary>
    /// Centralised app-version surface. Read once from the assembly metadata
    /// and exposed to MainWindow chrome (lower-left of the sidebar).
    ///
    /// Resolution order:
    ///   1. <see cref="AssemblyInformationalVersionAttribute"/> if set —
    ///      this is what `<InformationalVersion>` in the csproj writes to,
    ///      and is the cleanest place for "0.4.5+696b2fa" style strings.
    ///   2. <see cref="AssemblyName.Version"/> from the loaded assembly,
    ///      formatted as "Major.Minor.Build" so we don't print the
    ///      meaningless trailing revision number.
    ///   3. A "dev" fallback if neither is set (won't happen in a release
    ///      build because the csproj &lt;Version&gt; tag forces #2 to fire).
    /// </summary>
    public static class AppVersion
    {
        // Lazy-evaluated so design-time XAML doesn't fault on Application.Current.
        private static readonly Lazy<(string Display, string Tooltip)> _value =
            new Lazy<(string, string)>(Resolve);

        /// <summary>Short label rendered next to the brand block, e.g. "v0.4.5".</summary>
        public static string Display => _value.Value.Display;

        /// <summary>Long tooltip — full version string + commit SHA when available.</summary>
        public static string Tooltip => _value.Value.Tooltip;

        private static (string Display, string Tooltip) Resolve()
        {
            try
            {
                var asm = typeof(AppVersion).Assembly;

                // 1) AssemblyInformationalVersion — preferred.
                var info = asm.GetCustomAttribute<AssemblyInformationalVersionAttribute>();
                if (info != null && !string.IsNullOrWhiteSpace(info.InformationalVersion))
                {
                    var v = info.InformationalVersion.Trim();
                    // Strip any "+commit" suffix from the short label but keep
                    // it on the tooltip so the SHA is one click away.
                    var plus = v.IndexOf('+');
                    var displayCore = plus > 0 ? v.Substring(0, plus) : v;
                    var display = "v" + displayCore;
                    var tooltip = "Pulse " + display +
                                  (plus > 0 ? "  ·  " + v.Substring(plus + 1) : "");
                    return (display, tooltip);
                }

                // 2) AssemblyVersion — Major.Minor.Build only.
                var av = asm.GetName().Version;
                if (av != null)
                {
                    var display = $"v{av.Major}.{av.Minor}.{av.Build}";
                    var tooltip = $"Pulse {display}  ·  build {av}";
                    return (display, tooltip);
                }
            }
            catch
            {
                // Reflection on the assembly should never fail in a normal run,
                // but if it does we don't want to take the whole UI down.
            }
            return ("v0.0.0-dev", "Pulse (dev build)");
        }
    }
}
