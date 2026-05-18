using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;

namespace Pulse.WPF.Helpers
{
    /// <summary>
    /// Reads vendor / sport / configuration name mappings from the local
    /// ScoreConnect III installation's wwwroot data directory:
    ///
    ///   C:\Program Files (x86)\Sportzcast LLC\ScoreConnectIII\wwwroot\data\
    ///
    /// The ScoreConnect III HTTP API returns vendor / sport / configuration
    /// objects with numeric Id fields but often empty Name fields — the
    /// web UI is expected to dereference the names from the local data
    /// files. Pulse's dropdowns previously rendered the numeric IDs verbatim
    /// because the API gave us nothing better. This helper makes Pulse a
    /// proper API consumer by reading the same data files the web UI does.
    ///
    /// Defensive: the file naming + JSON shape varies across ScoreConnect III
    /// versions. We try several likely filenames and parse both common
    /// shapes — array-of-objects and dictionary-of-strings. Anything that
    /// can't be parsed is silently skipped; callers fall back to the
    /// numeric ID just like they did before this helper existed.
    ///
    /// Cached for the lifetime of the process. Restart Pulse to pick up
    /// new files (this is a static-data lookup; it should not change
    /// during a session).
    /// </summary>
    public static class SportzcastDataDirReader
    {
        private static readonly object _gate = new object();
        private static readonly string[] CandidateRoots =
        {
            @"C:\Program Files (x86)\Sportzcast LLC\ScoreConnectIII\wwwroot\data",
            @"C:\Program Files\Sportzcast LLC\ScoreConnectIII\wwwroot\data",
        };

        // Filename heuristics — first match wins per dictionary. Lowercased
        // before comparison; we match by `Contains` so partial filenames
        // (e.g. "vendor-list.json", "vendors.json", "Vendor_v2.json") all
        // hit the vendor bucket.
        //
        // "scoreboardcodes" is the schema Sportzcast uses for the master
        // ScoreBOT codes file — each row carries SCOREBOARD / SBVENDOR /
        // SBCODE / VENDORCODE, and a single file populates both the sports
        // bucket (SBCODE -> SCOREBOARD) and the vendors bucket (derived as
        // the common prefix among rows sharing SBVENDOR).
        private static readonly (string Bucket, string[] Needles)[] BucketHints =
        {
            ("scoreboardcodes",new[] { "scoreboard code", "scorebot scoreboard" }),
            ("vendors",        new[] { "vendor-list", "vendors" }),
            ("sports",         new[] { "vendor-sport", "sport-list", "sports" }),
            ("configurations", new[] { "vendor-configuration", "configuration" }),
            ("devices",        new[] { "device-list", "devices" }),
        };

        private static bool _loaded;
        private static Dictionary<string, Dictionary<string, string>> _byBucket;
        private static string _resolvedRoot;

        /// <summary>True once Load() has actually located the data dir.</summary>
        public static bool IsAvailable
        {
            get { lock (_gate) { EnsureLoaded(); return _byBucket != null && _byBucket.Count > 0; } }
        }

        /// <summary>The data directory we ended up reading, or empty string.</summary>
        public static string ResolvedRoot
        {
            get { lock (_gate) { EnsureLoaded(); return _resolvedRoot ?? ""; } }
        }

        /// <summary>Resolve a vendor ID to its name. Returns null when unknown.</summary>
        public static string GetVendorName(string id) => Lookup("vendors", id);

        /// <summary>Resolve a vendor-sport ID to its name. Returns null when unknown.</summary>
        public static string GetSportName(string id) => Lookup("sports", id);

        /// <summary>Resolve a vendor-configuration ID to its name. Returns null when unknown.</summary>
        public static string GetConfigurationName(string id) => Lookup("configurations", id);

        /// <summary>Resolve a device ID to its name. Returns null when unknown.</summary>
        public static string GetDeviceName(string id) => Lookup("devices", id);

        private static string Lookup(string bucket, string id)
        {
            if (string.IsNullOrWhiteSpace(id)) return null;
            lock (_gate)
            {
                EnsureLoaded();
                if (_byBucket == null) return null;
                if (!_byBucket.TryGetValue(bucket, out var dict)) return null;
                return dict.TryGetValue(id, out var name) ? name : null;
            }
        }

        // Force a fresh read on next access. Primarily for tests; not wired
        // to any UI action today.
        public static void InvalidateCache()
        {
            lock (_gate)
            {
                _loaded = false;
                _byBucket = null;
                _resolvedRoot = null;
            }
        }

        private static void EnsureLoaded()
        {
            if (_loaded) return;
            _loaded = true;   // mark loaded even on failure so we don't retry every Lookup
            try
            {
                var root = FindFirstExistingRoot();
                if (root == null) return;
                _resolvedRoot = root;
                _byBucket = new Dictionary<string, Dictionary<string, string>>(StringComparer.OrdinalIgnoreCase);
                foreach (var (bucket, _) in BucketHints)
                    _byBucket[bucket] = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);

                IEnumerable<string> files;
                try { files = Directory.EnumerateFiles(root, "*.json", SearchOption.AllDirectories); }
                catch { return; }

                foreach (var file in files)
                {
                    var bucket = BucketForFile(file);
                    if (bucket == null) continue;
                    string text;
                    try { text = File.ReadAllText(file); }
                    catch { continue; }
                    if (bucket == "scoreboardcodes")
                    {
                        // Special case: one file populates two buckets.
                        // SBCODE -> SCOREBOARD goes into the sports bucket
                        // (so sport IDs returned by the API get a human-
                        // readable name when the API itself returns empty
                        // names). Vendor names are derived as the common
                        // prefix among all SCOREBOARDs sharing an SBVENDOR.
                        MergeScoreboardCodes(text, _byBucket["sports"], _byBucket["vendors"]);
                        continue;
                    }
                    MergeNamePairs(text, _byBucket[bucket]);
                }
            }
            catch
            {
                // Defensive: a malformed data dir must not break Pulse's
                // startup. Leave _byBucket null so IsAvailable returns false.
            }
        }

        private static string FindFirstExistingRoot()
        {
            foreach (var p in CandidateRoots)
            {
                try { if (Directory.Exists(p)) return p; }
                catch { }
            }
            return null;
        }

        private static string BucketForFile(string filePath)
        {
            var name = (Path.GetFileNameWithoutExtension(filePath) ?? "").ToLowerInvariant();
            foreach (var (bucket, needles) in BucketHints)
            {
                foreach (var n in needles)
                    if (name.Contains(n)) return bucket;
            }
            return null;
        }

        // Pull every (id, name) pair we can find out of `text` and merge into
        // `dict`. Two common shapes are handled:
        //   1. Array of objects with id+name fields:
        //        [{"id":24,"name":"Daktronics"}, ...]
        //      Field names are tried in order: id|vendorId|sportId|configurationId|deviceId
        //      and: name|vendorName|sportName|description|displayName
        //   2. Dictionary of id -> name:
        //        {"24":"Daktronics","32":"Colorado Time", ...}
        // We use the existing JsonScrape helper for #1 to stay consistent
        // with the rest of the codebase; the dictionary form is parsed by
        // a tiny inline scanner so we don't take a new JSON dependency.
        private static void MergeNamePairs(string text, Dictionary<string, string> dict)
        {
            if (string.IsNullOrWhiteSpace(text)) return;
            text = text.TrimStart();
            if (text.Length == 0) return;
            if (text[0] == '[')
            {
                try
                {
                    foreach (var row in JsonScrape.TopLevelArrayOfObjects(text))
                    {
                        var id = PickFirst(row, "id", "vendorId", "vendorSportId", "sportId", "configurationId", "deviceId");
                        var nm = PickFirst(row, "name", "vendorName", "sportName", "configurationName", "description", "displayName", "deviceName");
                        if (!string.IsNullOrWhiteSpace(id) && !string.IsNullOrWhiteSpace(nm))
                            dict[id.Trim()] = nm.Trim();
                    }
                }
                catch { }
                return;
            }
            if (text[0] == '{')
            {
                // Two cases here:
                //   a) Flat dict of id -> name strings
                //   b) Object with a top-level "data": [...] or "vendors": [...]
                // We try the array-inside-object case via a cheap scan, then
                // fall back to the flat-dict case.
                if (TryExtractInnerArray(text, out var inner))
                {
                    try
                    {
                        foreach (var row in JsonScrape.TopLevelArrayOfObjects(inner))
                        {
                            var id = PickFirst(row, "id", "vendorId", "vendorSportId", "sportId", "configurationId", "deviceId");
                            var nm = PickFirst(row, "name", "vendorName", "sportName", "configurationName", "description", "displayName", "deviceName");
                            if (!string.IsNullOrWhiteSpace(id) && !string.IsNullOrWhiteSpace(nm))
                                dict[id.Trim()] = nm.Trim();
                        }
                        return;
                    }
                    catch { }
                }
                // Flat dict — match "<id>" : "<name>" pairs at top level.
                // Conservative regex: numeric/string id key, string value.
                var rx = new System.Text.RegularExpressions.Regex(
                    "\"([^\"\\\\]+)\"\\s*:\\s*\"([^\"\\\\]*)\"",
                    System.Text.RegularExpressions.RegexOptions.Compiled);
                foreach (System.Text.RegularExpressions.Match m in rx.Matches(text))
                {
                    var k = m.Groups[1].Value;
                    var v = m.Groups[2].Value;
                    if (string.IsNullOrWhiteSpace(k) || string.IsNullOrWhiteSpace(v)) continue;
                    // Skip obviously-not-id keys (lower-case english words that
                    // look like field names rather than IDs).
                    if (LooksLikeFieldNameNotId(k)) continue;
                    dict[k.Trim()] = v.Trim();
                }
            }
        }

        // ScoreBOT Scoreboard Codes schema:
        //   [{"ID":N,"SCOREBOARD":"...","SBVENDOR":N,"SBCODE":N,"VENDORCODE":N}, ...]
        // Populates two buckets:
        //   sports  : SBCODE   -> SCOREBOARD                       (verbatim)
        //   vendors : SBVENDOR -> longest common word prefix of all
        //                          SCOREBOARDs sharing that SBVENDOR
        // The vendor-name derivation is heuristic — Sportzcast doesn't
        // ship an explicit vendor-name field in this file. For vendor 14
        // ("All American Baseball/Basketball/Football") the prefix is
        // "All American"; for vendor 52 ("Alge Timing") it's "Alge Timing".
        // When the prefix is empty (rows share no leading word) we fall
        // back to the first SCOREBOARD verbatim — a reasonable hint, and
        // still better than the bare numeric ID.
        private static void MergeScoreboardCodes(string text,
            Dictionary<string, string> sports,
            Dictionary<string, string> vendors)
        {
            List<Dictionary<string, string>> rows;
            try { rows = JsonScrape.TopLevelArrayOfObjects(text); }
            catch { return; }
            if (rows == null || rows.Count == 0) return;

            // Group SCOREBOARDs by SBVENDOR; populate the sports bucket as
            // we iterate. Newer rows overwrite older for the same SBCODE —
            // that's fine since SBCODE is supposed to be unique per ID.
            var byVendor = new Dictionary<string, List<string>>(StringComparer.OrdinalIgnoreCase);
            foreach (var row in rows)
            {
                var sb = PickFirst(row, "SCOREBOARD", "scoreboard", "Name");
                var vendorId = PickFirst(row, "SBVENDOR", "sbVendor", "vendorId");
                var sportId  = PickFirst(row, "SBCODE",   "sbCode",   "sportId");

                if (!string.IsNullOrWhiteSpace(sportId) && !string.IsNullOrWhiteSpace(sb))
                    sports[sportId.Trim()] = sb.Trim();

                if (!string.IsNullOrWhiteSpace(vendorId) && !string.IsNullOrWhiteSpace(sb))
                {
                    if (!byVendor.TryGetValue(vendorId.Trim(), out var list))
                    {
                        list = new List<string>();
                        byVendor[vendorId.Trim()] = list;
                    }
                    list.Add(sb.Trim());
                }
            }

            foreach (var kv in byVendor)
            {
                var name = LongestCommonWordPrefix(kv.Value);
                if (string.IsNullOrEmpty(name) && kv.Value.Count > 0) name = kv.Value[0];
                if (!string.IsNullOrEmpty(name)) vendors[kv.Key] = name;
            }
        }

        // Returns the longest leading whitespace-delimited word sequence
        // shared by every string in `items`. Used to derive a vendor name
        // from a group of scoreboard names. Case-insensitive comparison
        // on the comparator side; original casing of the first item is
        // returned so display reads naturally ("All American" not "ALL AMERICAN").
        private static string LongestCommonWordPrefix(List<string> items)
        {
            if (items == null || items.Count == 0) return "";
            if (items.Count == 1) return items[0];
            var splits = items.Select(s => (s ?? "").Split(new[] { ' ' }, StringSplitOptions.RemoveEmptyEntries)).ToList();
            int min = splits.Min(a => a.Length);
            var prefix = new List<string>();
            for (int i = 0; i < min; i++)
            {
                var word = splits[0][i];
                bool allMatch = splits.All(a => string.Equals(a[i], word, StringComparison.OrdinalIgnoreCase));
                if (!allMatch) break;
                prefix.Add(word);
            }
            // Drop trailing common-but-meaningless tokens (parens, dashes).
            while (prefix.Count > 0)
            {
                var last = prefix[prefix.Count - 1];
                if (last == "-" || last == "—" || last.StartsWith("(")) prefix.RemoveAt(prefix.Count - 1);
                else break;
            }
            return string.Join(" ", prefix);
        }

        private static bool LooksLikeFieldNameNotId(string key)
        {
            if (string.IsNullOrEmpty(key)) return true;
            // Field-name-ish: starts with a letter, contains lowercase only,
            // length < 20. IDs are usually numeric or GUID-like.
            if (!char.IsLetter(key[0])) return false;
            foreach (var c in key)
            {
                if (!(char.IsLetter(c) || c == '_' || char.IsDigit(c))) return false;
            }
            return key.Length <= 24;   // generous; IDs longer than this are GUIDs (not letter-leading)
        }

        // Trivial JSON helper: find a top-level array property inside a JSON
        // object. Looks for any "key": [ ... ] block whose key is one of the
        // names we'd expect to wrap a vendor/sport/config list.
        private static bool TryExtractInnerArray(string text, out string inner)
        {
            inner = null;
            string[] wrapKeys = { "data", "items", "result", "results", "vendors", "sports", "configurations", "devices" };
            foreach (var key in wrapKeys)
            {
                var startTag = "\"" + key + "\"";
                int idx = text.IndexOf(startTag, StringComparison.OrdinalIgnoreCase);
                if (idx < 0) continue;
                int colon = text.IndexOf(':', idx);
                if (colon < 0) continue;
                int open = text.IndexOf('[', colon);
                if (open < 0) continue;
                // Find matching close bracket with naive depth tracking.
                int depth = 0;
                for (int i = open; i < text.Length; i++)
                {
                    if (text[i] == '[') depth++;
                    else if (text[i] == ']')
                    {
                        depth--;
                        if (depth == 0) { inner = text.Substring(open, i - open + 1); return true; }
                    }
                }
            }
            return false;
        }

        // Mirror PickFirst from ScoreConnectService — pulls the first
        // non-empty value out of a parsed JSON row. JsonScrape rows are
        // Dictionary<string, string>.
        private static string PickFirst(IDictionary<string, string> row, params string[] keys)
        {
            if (row == null) return "";
            foreach (var k in keys)
            {
                if (!row.TryGetValue(k, out var v)) continue;
                if (!string.IsNullOrWhiteSpace(v)) return v;
            }
            return "";
        }
    }
}
