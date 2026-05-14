using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;
using System.Threading;
using System.Threading.Tasks;

namespace Pulse.WPF.Helpers
{
    /// <summary>
    /// Tails GraphicsManager logs for the Sportzcast data that GraphicsManager
    /// has already parsed from the decoder. This is the most reliable live
    /// feed on the VPU because it is the same data GraphicsManager sends into
    /// Pixellot's graphics pipeline.
    /// </summary>
    public sealed class GraphicsManagerSportzcastLogFeed : IDisposable
    {
        public const string DefaultLogDirectory = @"C:\Pixellot\Data\Log";

        private const int InitialTailBytes = 512 * 1024;
        private static readonly TimeSpan PollInterval = TimeSpan.FromSeconds(1);
        private static readonly TimeSpan StaleAfter = TimeSpan.FromSeconds(15);

        private readonly string _logDirectory;
        private readonly object _gate = new object();
        private readonly GraphicsManagerSportzcastLogParser _parser =
            new GraphicsManagerSportzcastLogParser();

        private CancellationTokenSource _cts;
        private Task _runTask;
        private string _currentLogPath = "";
        private long _position;
        private bool _discardFirstLine;
        private bool _isConnected;
        private DateTime? _lastFrameUtc;
        private string _lastStatus = "";

        public string CurrentLogPath
        {
            get { lock (_gate) return _currentLogPath; }
        }

        public bool IsConnected
        {
            get { lock (_gate) return _isConnected; }
        }

        public event Action<string, Dictionary<string, object>> MessageReceived;
        public event Action<bool> ConnectionStateChanged;
        public event Action<string, string> StatusChanged;

        public GraphicsManagerSportzcastLogFeed(string logDirectory = null)
        {
            _logDirectory = string.IsNullOrWhiteSpace(logDirectory)
                ? DefaultLogDirectory
                : logDirectory;
        }

        public Task StartAsync()
        {
            lock (_gate)
            {
                if (_runTask != null && !_runTask.IsCompleted) return Task.CompletedTask;
                _cts = new CancellationTokenSource();
                _runTask = Task.Run(() => RunLoopAsync(_cts.Token));
            }
            return Task.CompletedTask;
        }

        public async Task StopAsync()
        {
            CancellationTokenSource cts;
            Task task;
            lock (_gate)
            {
                cts = _cts;
                task = _runTask;
                _cts = null;
                _runTask = null;
            }

            try { cts?.Cancel(); } catch { }
            try { if (task != null) await task.ConfigureAwait(false); } catch { }
            SetConnected(false);
        }

        private async Task RunLoopAsync(CancellationToken ct)
        {
            while (!ct.IsCancellationRequested)
            {
                try
                {
                    PollOnce();
                }
                catch (Exception ex)
                {
                    PublishStatus($"GraphicsManager log read failed: {ex.Message}", CurrentLogPath);
                    SetConnected(false);
                }

                try { await Task.Delay(PollInterval, ct).ConfigureAwait(false); }
                catch (OperationCanceledException) { return; }
            }
        }

        private void PollOnce()
        {
            var latest = ResolveLatestLogPath();
            if (string.IsNullOrWhiteSpace(latest))
            {
                PublishStatus($"Waiting for {_logDirectory}\\GraphicsManager*.log", "");
                SetConnected(false);
                return;
            }

            var changed = !string.Equals(latest, CurrentLogPath, StringComparison.OrdinalIgnoreCase);
            if (changed)
            {
                SwitchToLog(latest);
                ReadAvailableLines(emitLatestOnly: true);
            }
            else
            {
                ReadAvailableLines(emitLatestOnly: false);
            }

            UpdateFreshness();
        }

        private string ResolveLatestLogPath()
        {
            try
            {
                if (!Directory.Exists(_logDirectory)) return "";
                var files = new List<string>();
                files.AddRange(Directory.EnumerateFiles(
                    _logDirectory, "GraphicsManager*.log", SearchOption.TopDirectoryOnly));

                foreach (var dir in Directory.EnumerateDirectories(
                    _logDirectory, "GraphicsManager*", SearchOption.TopDirectoryOnly))
                {
                    try
                    {
                        files.AddRange(Directory.EnumerateFiles(
                            dir, "*.log", SearchOption.TopDirectoryOnly));
                    }
                    catch { }
                }

                return files
                    .OrderByDescending(SafeLastWriteUtc)
                    .FirstOrDefault() ?? "";
            }
            catch
            {
                return "";
            }
        }

        private static DateTime SafeLastWriteUtc(string path)
        {
            try { return File.GetLastWriteTimeUtc(path); }
            catch { return DateTime.MinValue; }
        }

        private void SwitchToLog(string path)
        {
            long length = 0;
            try { length = new FileInfo(path).Length; } catch { }

            lock (_gate)
            {
                _currentLogPath = path;
                _position = Math.Max(0, length - InitialTailBytes);
                _discardFirstLine = _position > 0;
                _lastFrameUtc = null;
            }

            _parser.Reset();
            PublishStatus($"Watching {Path.GetFileName(path)}; waiting for Sportzcast frames", path);
        }

        private void ReadAvailableLines(bool emitLatestOnly)
        {
            var path = CurrentLogPath;
            if (string.IsNullOrWhiteSpace(path) || !File.Exists(path)) return;

            long start;
            bool discard;
            lock (_gate)
            {
                start = _position;
                discard = _discardFirstLine;
                _discardFirstLine = false;
            }

            using (var fs = new FileStream(path, FileMode.Open, FileAccess.Read,
                       FileShare.ReadWrite | FileShare.Delete))
            {
                if (start > fs.Length) start = 0;
                fs.Seek(start, SeekOrigin.Begin);

                using (var reader = new StreamReader(fs, Encoding.UTF8, true, 4096, leaveOpen: true))
                {
                    if (discard) reader.ReadLine();

                    string latestRaw = null;
                    Dictionary<string, object> latestParsed = null;
                    string line;
                    while ((line = reader.ReadLine()) != null)
                    {
                        if (_parser.TryApplyLine(path, line, out var raw, out var parsed))
                        {
                            latestRaw = raw;
                            latestParsed = parsed;
                            if (!emitLatestOnly) PublishFrame(raw, parsed);
                        }
                    }

                    lock (_gate) _position = fs.Position;

                    if (emitLatestOnly && latestParsed != null)
                        PublishFrame(latestRaw, latestParsed);
                }
            }
        }

        private void PublishFrame(string raw, Dictionary<string, object> parsed)
        {
            if (parsed == null) return;
            var frameUtc = FrameTimestampUtc(parsed) ?? DateTime.UtcNow;
            lock (_gate) _lastFrameUtc = frameUtc;
            SetConnected(DateTime.UtcNow - frameUtc <= StaleAfter);
            PublishStatus($"Live Sportzcast data from {Path.GetFileName(CurrentLogPath)}", CurrentLogPath);

            try { MessageReceived?.Invoke(raw ?? "", parsed); }
            catch (Exception ex)
            {
                AppLogFile.Instance.WriteLine("ScoreConnect", "Warn",
                    $"GraphicsManager log subscriber threw: {ex.Message}");
            }
        }

        private static DateTime? FrameTimestampUtc(Dictionary<string, object> parsed)
        {
            try
            {
                if (parsed == null || !parsed.TryGetValue("logTimestampUtc", out var value) || value == null)
                    return null;
                if (DateTimeOffset.TryParse(Convert.ToString(value), CultureInfo.InvariantCulture,
                    DateTimeStyles.AssumeUniversal | DateTimeStyles.AdjustToUniversal,
                    out var dto))
                {
                    return dto.UtcDateTime;
                }
            }
            catch { }
            return null;
        }

        private void UpdateFreshness()
        {
            DateTime? last;
            string path;
            lock (_gate)
            {
                last = _lastFrameUtc;
                path = _currentLogPath;
            }

            if (!last.HasValue)
            {
                SetConnected(false);
                return;
            }

            var age = DateTime.UtcNow - last.Value;
            if (age <= StaleAfter)
            {
                SetConnected(true);
                PublishStatus($"Live Sportzcast data ({FormatAge(age)} ago)", path);
            }
            else
            {
                SetConnected(false);
                PublishStatus($"Last Sportzcast frame {FormatAge(age)} ago", path);
            }
        }

        private void SetConnected(bool connected)
        {
            bool changed;
            lock (_gate)
            {
                changed = _isConnected != connected;
                _isConnected = connected;
            }
            if (changed)
            {
                try { ConnectionStateChanged?.Invoke(connected); } catch { }
            }
        }

        private void PublishStatus(string status, string path)
        {
            var text = status ?? "";
            var changed = false;
            lock (_gate)
            {
                if (!string.Equals(_lastStatus, text, StringComparison.Ordinal))
                {
                    _lastStatus = text;
                    changed = true;
                }
            }
            if (changed)
            {
                try { StatusChanged?.Invoke(text, path ?? ""); } catch { }
            }
        }

        private static string FormatAge(TimeSpan age)
        {
            if (age.TotalSeconds < 1) return "now";
            if (age.TotalMinutes < 1) return $"{(int)Math.Round(age.TotalSeconds)}s";
            if (age.TotalHours < 1) return $"{(int)Math.Round(age.TotalMinutes)}m";
            return $"{(int)Math.Round(age.TotalHours)}h";
        }

        public void Dispose()
        {
            try { _cts?.Cancel(); } catch { }
            try { _cts?.Dispose(); } catch { }
        }

        private sealed class GraphicsManagerSportzcastLogParser
        {
            private Dictionary<string, object> _current =
                new Dictionary<string, object>(StringComparer.OrdinalIgnoreCase);
            private string _rawFrame = "";
            private bool _hasFrame;
            private bool _hasDataField;

            public void Reset()
            {
                _current = new Dictionary<string, object>(StringComparer.OrdinalIgnoreCase);
                _rawFrame = "";
                _hasFrame = false;
                _hasDataField = false;
            }

            public bool TryApplyLine(
                string path,
                string line,
                out string raw,
                out Dictionary<string, object> parsed)
            {
                raw = null;
                parsed = null;
                if (string.IsNullOrWhiteSpace(line)) return false;

                var timestamp = ParseTimestampUtc(line);
                var message = ExtractMessage(line);
                if (string.IsNullOrWhiteSpace(message)) return false;

                if (TryExtractAfter(message, "Received sportzcast data:", out var frame))
                {
                    StartFrame(path, timestamp);
                    _rawFrame = SanitizeControlChars(frame.Trim());
                    _current["rawSportzcast"] = _rawFrame;
                    _hasDataField = true;
                    return false;
                }

                if (!_hasFrame && IsSportzcastParseLine(message))
                    StartFrame(path, timestamp);

                if (!_hasFrame) return false;

                if (TryExtractAfter(message, "Sport type from Sportzcast:", out var sport))
                    Set("sport", sport);
                else if (TryExtractQuotedAfter(message, "homeScore string received:", out var home))
                    Set("homeScore", home);
                else if (TryExtractQuotedAfter(message, "awayScore string received:", out var away))
                    Set("awayScore", away);
                else if (TryExtractAfter(message, "Time from Sportzcast:", out var clock))
                    Set("clock", clock);
                else if (TryExtractAfter(message, "Period from Sportzcast:", out var period))
                    Set("period", period);
                else if (TryExtractQuotedAfter(message, "period string received:", out var periodString))
                    Set("period", periodString);
                else if (message.IndexOf("Error processing Sportzcast period:", StringComparison.OrdinalIgnoreCase) >= 0)
                    Set("periodError", message);

                if (message.IndexOf("Finishing processing sportzcast data", StringComparison.OrdinalIgnoreCase) >= 0)
                {
                    if (!_hasDataField) return false;
                    parsed = new Dictionary<string, object>(_current, StringComparer.OrdinalIgnoreCase);
                    raw = string.IsNullOrWhiteSpace(_rawFrame) ? message : _rawFrame;
                    Reset();
                    return true;
                }

                return false;
            }

            private void StartFrame(string path, DateTime? timestampUtc)
            {
                _current = new Dictionary<string, object>(StringComparer.OrdinalIgnoreCase)
                {
                    ["source"] = "GraphicsManager log",
                    ["logFile"] = Path.GetFileName(path ?? ""),
                    ["logPath"] = path ?? "",
                };
                if (timestampUtc.HasValue)
                    _current["logTimestampUtc"] = timestampUtc.Value.ToString("o", CultureInfo.InvariantCulture);
                _rawFrame = "";
                _hasFrame = true;
            }

            private void Set(string key, string value)
            {
                var clean = (value ?? "").Trim();
                if (clean.Length > 0)
                {
                    _current[key] = clean;
                    _hasDataField = true;
                }
            }

            private static bool IsSportzcastParseLine(string message)
            {
                return message.IndexOf("Sportzcast", StringComparison.OrdinalIgnoreCase) >= 0 ||
                       message.IndexOf("homeScore string received", StringComparison.OrdinalIgnoreCase) >= 0 ||
                       message.IndexOf("awayScore string received", StringComparison.OrdinalIgnoreCase) >= 0;
            }

            private static string ExtractMessage(string line)
            {
                var pipes = 0;
                for (var i = 0; i < line.Length; i++)
                {
                    if (line[i] != '|') continue;
                    pipes++;
                    if (pipes == 5)
                    {
                        return i >= line.Length - 1 ? "" : line.Substring(i + 1).Trim();
                    }
                }
                var idx = line.LastIndexOf('|');
                if (idx < 0 || idx >= line.Length - 1) return line.Trim();
                return line.Substring(idx + 1).Trim();
            }

            private static bool TryExtractAfter(string message, string marker, out string value)
            {
                value = "";
                var idx = message.IndexOf(marker, StringComparison.OrdinalIgnoreCase);
                if (idx < 0) return false;
                value = message.Substring(idx + marker.Length).Trim();
                return true;
            }

            private static bool TryExtractQuotedAfter(string message, string marker, out string value)
            {
                value = "";
                if (!TryExtractAfter(message, marker, out var tail)) return false;
                var first = tail.IndexOf('"');
                if (first < 0)
                {
                    value = tail.Trim();
                    return true;
                }
                var second = tail.IndexOf('"', first + 1);
                value = second > first
                    ? tail.Substring(first + 1, second - first - 1)
                    : tail.Substring(first + 1);
                return true;
            }

            private static DateTime? ParseTimestampUtc(string line)
            {
                try
                {
                    var parts = line.Split('|');
                    if (parts.Length < 2) return null;
                    var raw = parts[1].Trim();
                    if (DateTimeOffset.TryParse(raw, CultureInfo.InvariantCulture,
                        DateTimeStyles.AssumeUniversal | DateTimeStyles.AdjustToUniversal,
                        out var dto))
                    {
                        return dto.UtcDateTime;
                    }
                }
                catch { }
                return null;
            }

            private static string SanitizeControlChars(string value)
            {
                if (string.IsNullOrEmpty(value)) return "";
                var sb = new StringBuilder(value.Length + 12);
                foreach (var c in value)
                {
                    if (c == '\u0002') sb.Append("<STX>");
                    else if (c == '\u0003') sb.Append("<ETX>");
                    else if (!char.IsControl(c)) sb.Append(c);
                }
                return sb.ToString();
            }
        }
    }
}
