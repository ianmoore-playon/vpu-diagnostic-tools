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

        /// <summary>Raised when the ScoreConnect URL changes at runtime so
        /// the Score Connect panel can re-probe without requiring an app
        /// restart.</summary>
        public event Action<string> ScoreConnectUrlChanged;

        /// <summary>v0.6.7 — write-side mutator used by the Settings panel.
        /// Persists the new URL to settings.json. Returns true on a clean
        /// write, false on IO failure (the in-memory value is updated either
        /// way so the panel reflects the user's choice for the session even
        /// if the disk write fails on a locked-down box).</summary>
        public bool SetScoreConnectUrl(string url)
        {
            var next = NormaliseScoreConnectUrl(url);
            var changed = !string.Equals(ScoreConnectUrl, next, StringComparison.OrdinalIgnoreCase);
            ScoreConnectUrl = next;
            try
            {
                // Minimal hand-written JSON to match the existing flat-object
                // schema. Quote escaping limited to backslash + quote — the
                // ScoreConnect URL won't contain control characters.
                var escaped = ScoreConnectUrl.Replace("\\", "\\\\").Replace("\"", "\\\"");
                var payload = "{\n  \"scoreConnectUrl\": \"" + escaped + "\"\n}\n";
                File.WriteAllText(SettingsPath, payload, Encoding.UTF8);
                if (changed) RaiseScoreConnectUrlChanged();
                return true;
            }
            catch
            {
                if (changed) RaiseScoreConnectUrlChanged();
                return false;
            }
        }

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
                    ScoreConnectUrl = NormaliseScoreConnectUrl(url);
                }
            }
            catch
            {
                // A malformed settings file mustn't crash the diagnostic tool;
                // fall back to the compiled defaults silently.
            }
        }

        private static string NormaliseScoreConnectUrl(string url)
        {
            var s = (url ?? DefaultScoreConnectUrl).Trim().TrimEnd('/');
            return string.IsNullOrWhiteSpace(s) ? DefaultScoreConnectUrl : s;
        }

        private void RaiseScoreConnectUrlChanged()
        {
            try { ScoreConnectUrlChanged?.Invoke(ScoreConnectUrl); }
            catch { /* subscriber bugs must not block settings persistence */ }
        }
    }
}
