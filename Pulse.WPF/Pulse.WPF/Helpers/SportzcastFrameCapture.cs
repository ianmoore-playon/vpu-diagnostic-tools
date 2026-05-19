using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text;
using Pulse.WPF.Models;

namespace Pulse.WPF.Helpers
{
    /// <summary>
    /// Always-on Sportzcast frame schema capture. Records, per sport, every
    /// unique field name that's appeared in a live frame, plus a small set
    /// of sample values per field so we can infer types later. Persists to
    /// a single small JSON file at:
    ///
    ///   %LOCALAPPDATA%\Pulse.WPF\State\sportzcast-frame-schema.json
    ///
    /// File is updated at most once per minute (debounced) so frame bursts
    /// during play don't generate disk traffic. The schema file grows by
    /// new-field-discovery only — same fields seen 10 000 times still
    /// produce one entry — so the file stays small (~tens of KB) for the
    /// lifetime of the install.
    ///
    /// This is the empirical foundation for the per-sport
    /// <see cref="SportzcastFrameMapper"/>: ship a snapshot of the captured
    /// schema in the source tree, evolve the mapper to cover whatever
    /// field names real venues are sending.
    ///
    /// No PII concerns: captured data is field names plus type-inference
    /// samples (e.g. "0", "7", "14" for a score field). Team names and
    /// any other identifying values are *redacted* (replaced with
    /// "&lt;redacted&gt;") for the universal HomeName / AwayName fields and
    /// for any field whose name contains "team" / "name" / "player".
    /// </summary>
    public sealed class SportzcastFrameCapture
    {
        private static readonly TimeSpan FlushInterval = TimeSpan.FromMinutes(1);
        private const int MaxSamplesPerField = 8;
        // Cap to prevent the file growing pathologically if a buggy decoder
        // ever invents new field names every frame.
        private const int MaxFieldsPerSport = 256;

        private readonly object _gate = new object();
        private readonly Dictionary<ScoreboardSport, SportSchema> _bySport
            = new Dictionary<ScoreboardSport, SportSchema>();

        private DateTime _lastFlushedAt = DateTime.MinValue;
        private readonly string _filePath;

        public SportzcastFrameCapture()
        {
            try
            {
                var local = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
                var dir = Path.Combine(local, "Pulse.WPF", "State");
                Directory.CreateDirectory(dir);
                _filePath = Path.Combine(dir, "sportzcast-frame-schema.json");
                LoadFromDisk();
            }
            catch
            {
                // Defensive: if we can't write the schema file, capture
                // becomes a no-op. Pulse must still work.
                _filePath = null;
            }
        }

        public string FilePath => _filePath;

        /// <summary>
        /// Record a single live frame against the detected sport. Cheap on
        /// the hot path — only does work when the frame surfaces a new
        /// field name OR when the per-field sample list isn't full yet.
        /// Flushes to disk at most once per FlushInterval.
        /// </summary>
        public void Record(ScoreboardSport sport, IDictionary<string, object> frame)
        {
            if (frame == null || frame.Count == 0 || _filePath == null) return;
            bool needsFlush;
            lock (_gate)
            {
                if (!_bySport.TryGetValue(sport, out var schema))
                {
                    schema = new SportSchema { Sport = sport, FirstSeenUtc = DateTime.UtcNow };
                    _bySport[sport] = schema;
                }
                schema.LastSeenUtc = DateTime.UtcNow;

                foreach (var kv in frame)
                {
                    if (string.IsNullOrEmpty(kv.Key)) continue;
                    if (schema.Fields.Count >= MaxFieldsPerSport && !schema.Fields.ContainsKey(kv.Key))
                        continue;
                    if (!schema.Fields.TryGetValue(kv.Key, out var fld))
                    {
                        fld = new FieldStats { Type = InferType(kv.Value) };
                        schema.Fields[kv.Key] = fld;
                    }
                    var sample = SafeSampleValue(kv.Key, kv.Value);
                    if (!string.IsNullOrEmpty(sample)
                        && fld.Samples.Count < MaxSamplesPerField
                        && !fld.Samples.Contains(sample))
                    {
                        fld.Samples.Add(sample);
                    }
                }

                needsFlush = (DateTime.UtcNow - _lastFlushedAt) >= FlushInterval;
                if (needsFlush) _lastFlushedAt = DateTime.UtcNow;
            }
            if (needsFlush) TryFlush();
        }

        // --- file I/O -----------------------------------------------------

        private void LoadFromDisk()
        {
            if (_filePath == null || !File.Exists(_filePath)) return;
            string text;
            try { text = File.ReadAllText(_filePath); }
            catch { return; }
            if (string.IsNullOrWhiteSpace(text)) return;

            // Minimal hand-parse — same shape we write below. We don't
            // care about strict validation; on any error we silently
            // start fresh.
            try
            {
                var rows = JsonScrape.TopLevelArrayOfObjects(text);
                foreach (var row in rows)
                {
                    if (!row.TryGetValue("sport", out var sportStr)) continue;
                    if (!Enum.TryParse<ScoreboardSport>(sportStr, true, out var sport)) continue;
                    var schema = new SportSchema { Sport = sport };
                    if (row.TryGetValue("firstSeenUtc", out var fs))
                        DateTime.TryParse(fs, null,
                            System.Globalization.DateTimeStyles.AssumeUniversal, out schema.FirstSeenUtc);
                    if (row.TryGetValue("lastSeenUtc", out var ls))
                        DateTime.TryParse(ls, null,
                            System.Globalization.DateTimeStyles.AssumeUniversal, out schema.LastSeenUtc);
                    if (row.TryGetValue("fields", out var fieldsJson))
                    {
                        // fieldsJson is the raw substring of the original JSON;
                        // re-parse it as another object.
                        try
                        {
                            var fieldsObj = JsonScrape.Parse(fieldsJson) as Dictionary<string, object>;
                            if (fieldsObj != null)
                            {
                                foreach (var fkv in fieldsObj)
                                {
                                    var fld = new FieldStats();
                                    if (fkv.Value is Dictionary<string, object> stats)
                                    {
                                        if (stats.TryGetValue("type", out var t))
                                            fld.Type = t?.ToString() ?? "string";
                                        if (stats.TryGetValue("samples", out var ss) && ss is List<object> samples)
                                        {
                                            foreach (var s in samples)
                                            {
                                                var v = s?.ToString();
                                                if (!string.IsNullOrEmpty(v) && fld.Samples.Count < MaxSamplesPerField)
                                                    fld.Samples.Add(v);
                                            }
                                        }
                                    }
                                    schema.Fields[fkv.Key] = fld;
                                }
                            }
                        }
                        catch { /* corrupt field entry — skip */ }
                    }
                    lock (_gate) _bySport[sport] = schema;
                }
            }
            catch { /* corrupt file — start fresh next flush */ }
        }

        private void TryFlush()
        {
            if (_filePath == null) return;
            string payload;
            lock (_gate)
            {
                payload = SerialiseLocked();
            }
            try
            {
                // Atomic write via tmp + Move so a crash mid-write doesn't
                // truncate the schema file. Matches the AppSettings pattern
                // shipped in v0.6.19.
                var tmp = _filePath + ".tmp";
                File.WriteAllText(tmp, payload, Encoding.UTF8);
                if (File.Exists(_filePath))
                {
                    File.Replace(tmp, _filePath, null);
                }
                else
                {
                    File.Move(tmp, _filePath);
                }
            }
            catch { /* disk full / locked — drop this flush, next one retries */ }
        }

        private string SerialiseLocked()
        {
            var sb = new StringBuilder();
            sb.Append("[\n");
            bool firstSport = true;
            foreach (var schema in _bySport.Values.OrderBy(s => (int)s.Sport))
            {
                if (!firstSport) sb.Append(",\n");
                firstSport = false;
                sb.Append("  {\n");
                sb.Append($"    \"sport\": \"{schema.Sport}\",\n");
                sb.Append($"    \"firstSeenUtc\": \"{schema.FirstSeenUtc:yyyy-MM-ddTHH:mm:ssZ}\",\n");
                sb.Append($"    \"lastSeenUtc\": \"{schema.LastSeenUtc:yyyy-MM-ddTHH:mm:ssZ}\",\n");
                sb.Append("    \"fields\": {\n");
                bool firstField = true;
                foreach (var kv in schema.Fields.OrderBy(k => k.Key, StringComparer.Ordinal))
                {
                    if (!firstField) sb.Append(",\n");
                    firstField = false;
                    sb.Append($"      \"{JsonEscape(kv.Key)}\": {{ \"type\": \"{kv.Value.Type}\", \"samples\": [");
                    bool firstSample = true;
                    foreach (var s in kv.Value.Samples)
                    {
                        if (!firstSample) sb.Append(", ");
                        firstSample = false;
                        sb.Append('"').Append(JsonEscape(s)).Append('"');
                    }
                    sb.Append("] }");
                }
                sb.Append("\n    }\n  }");
            }
            sb.Append("\n]\n");
            return sb.ToString();
        }

        private static string JsonEscape(string s)
        {
            if (string.IsNullOrEmpty(s)) return "";
            return s.Replace("\\", "\\\\").Replace("\"", "\\\"")
                    .Replace("\n", "\\n").Replace("\r", "\\r").Replace("\t", "\\t");
        }

        // --- redaction / sampling -----------------------------------------

        private static readonly string[] PiiFieldHints = { "team", "name", "player", "school" };

        private static string SafeSampleValue(string key, object value)
        {
            var k = (key ?? "").ToLowerInvariant();
            foreach (var h in PiiFieldHints)
            {
                if (k.Contains(h)) return "<redacted>";
            }
            var s = value?.ToString() ?? "";
            // Cap sample length — some fields ship multi-line debug strings.
            if (s.Length > 32) s = s.Substring(0, 32);
            return s;
        }

        private static string InferType(object value)
        {
            if (value == null) return "null";
            if (value is bool) return "bool";
            if (value is int || value is long || value is double || value is float) return "number";
            var s = value.ToString();
            if (string.IsNullOrEmpty(s)) return "string";
            if (long.TryParse(s, out _))   return "number";
            if (double.TryParse(s, out _)) return "number";
            if (bool.TryParse(s, out _))   return "bool";
            return "string";
        }

        // --- inner types --------------------------------------------------

        private sealed class SportSchema
        {
            public ScoreboardSport Sport;
            public DateTime FirstSeenUtc;
            public DateTime LastSeenUtc;
            public readonly Dictionary<string, FieldStats> Fields
                = new Dictionary<string, FieldStats>(StringComparer.Ordinal);
        }

        private sealed class FieldStats
        {
            public string Type = "string";
            public readonly List<string> Samples = new List<string>();
        }
    }
}
