using System;
using System.IO;
using System.Text;

namespace Pulse.WPF.Helpers
{
    /// <summary>
    /// Lightweight app-level settings. Persisted to
    /// <c>%LOCALAPPDATA%\Pulse.WPF\settings.json</c> next to the rolling log.
    /// Read once on construction (no hot-reload) and exposed as plain
    /// properties — Pulse doesn't have anything that needs runtime-tunable
    /// config beyond the ScoreConnect URL today, so a heavier IConfiguration
    /// pipeline would be overkill.
    ///
    /// JSON is parsed by the same forgiving micro-parser used by the
    /// ScoreConnect service (<see cref="JsonScrape"/>) — we explicitly don't
    /// pull in Newtonsoft or System.Text.Json just for one file. Format on
    /// disk is a flat object of string -> string values; unknown keys are
    /// ignored.
    /// </summary>
    public sealed class AppSettings
    {
        private static readonly Lazy<AppSettings> _instance =
            new Lazy<AppSettings>(() => new AppSettings());
        public static AppSettings Instance => _instance.Value;

        /// <summary>Default URL for the ScoreConnect III HTTP API. Matches the
        /// installed <c>ScoreConnectIII.url</c> shortcut on a stock VPU.</summary>
        public const string DefaultScoreConnectUrl = "http://localhost:5000";

        public string SettingsPath { get; }

        /// <summary>Base URL the ScoreConnect service should probe. Override
        /// via the <c>scoreConnectUrl</c> key in settings.json.</summary>
        public string ScoreConnectUrl { get; private set; } = DefaultScoreConnectUrl;

        private AppSettings()
        {
            try
            {
                var local = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
                var dir = Path.Combine(local, "Pulse.WPF");
                try { Directory.CreateDirectory(dir); } catch { }
                SettingsPath = Path.Combine(dir, "settings.json");
            }
            catch
            {
                SettingsPath = Path.Combine(Path.GetTempPath(), "Pulse.WPF.settings.json");
            }
            Load();
        }

        private void Load()
        {
            try
            {
                if (!File.Exists(SettingsPath)) return;
                var text = File.ReadAllText(SettingsPath, Encoding.UTF8);
                if (string.IsNullOrWhiteSpace(text)) return;
                var url = JsonScrape.String(text, "scoreConnectUrl");
                if (!string.IsNullOrWhiteSpace(url))
                {
                    ScoreConnectUrl = url.TrimEnd('/');
                }
            }
            catch
            {
                // A malformed settings file mustn't crash the diagnostic tool;
                // fall back to the compiled defaults silently.
            }
        }
    }
}
