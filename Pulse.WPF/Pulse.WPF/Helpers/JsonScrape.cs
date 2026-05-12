using System;
using System.Collections.Generic;
using System.Globalization;
using System.Text;

namespace Pulse.WPF.Helpers
{
    /// <summary>
    /// Tiny, defensive JSON reader. The Pulse project doesn't reference
    /// Newtonsoft.Json or System.Text.Json (per project convention — see the
    /// csproj note about not pulling in NuGet for one consumer), but the
    /// ScoreConnect III integration needs to chew through arbitrary JSON
    /// from a service whose response shape isn't documented.
    ///
    /// This isn't a full JSON parser. It's a "give me the value at this key
    /// path, give me up an empty result on anything weird" helper that's good
    /// enough for the few shapes we care about:
    ///
    /// * <see cref="String"/> — top-level string at a key (handles escapes).
    /// * <see cref="Bool"/>   — top-level bool.
    /// * <see cref="ObjectAsMap"/> — top-level object as Dictionary&lt;string,string&gt;
    ///   so the panel can render arbitrary key/value rows.
    /// * <see cref="ArrayOfObjects"/> — an array of objects under a key,
    ///   each projected to a string-string map.
    /// * <see cref="TopLevelArrayOfObjects"/> — same but when the response
    ///   IS the array (no wrapping object).
    /// * <see cref="Parse"/> — best-effort full parse to a nested
    ///   object/array/string/bool/double tree for the WebSocket frame path.
    ///
    /// Every public entry point is try/catch wrapped at its caller so a
    /// malformed payload surfaces as "no data" rather than a panel crash.
    /// </summary>
    internal static class JsonScrape
    {
        // ---------- Public conveniences (cheap key lookups) ----------

        /// <summary>Return the string value at the first occurrence of the
        /// given key. Case-insensitive. Returns "" when not found or when the
        /// value isn't a string.</summary>
        public static string String(string json, string key)
        {
            if (string.IsNullOrEmpty(json) || string.IsNullOrEmpty(key)) return "";
            try
            {
                var v = FindValue(json, key);
                if (v == null) return "";
                if (v.StartsWith("\""))
                {
                    return UnescapeString(v);
                }
                if (v == "null" || v == "true" || v == "false") return v;
                return v; // numeric — caller can parse if it cares.
            }
            catch { return ""; }
        }

        /// <summary>Return the bool value at the first occurrence of the
        /// given key. Returns null when not found or not a recognised bool.</summary>
        public static bool? Bool(string json, string key)
        {
            var v = String(json, key);
            if (string.IsNullOrEmpty(v)) return null;
            if (v == "true" || v == "True") return true;
            if (v == "false" || v == "False") return false;
            return null;
        }

        /// <summary>Project the top-level object into a flat string-string map.
        /// Nested objects and arrays are flattened to their raw JSON text so
        /// the caller can still see something useful in the panel even when
        /// it's not a leaf value.</summary>
        public static Dictionary<string, string> ObjectAsMap(string json)
        {
            var map = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
            if (string.IsNullOrEmpty(json)) return map;
            try
            {
                var i = SkipWs(json, 0);
                if (i >= json.Length || json[i] != '{') return map;
                i++;
                while (i < json.Length)
                {
                    i = SkipWs(json, i);
                    if (i < json.Length && json[i] == '}') break;
                    string k = ReadString(json, ref i);
                    if (k == null) break;
                    i = SkipWs(json, i);
                    if (i >= json.Length || json[i] != ':') break;
                    i++;
                    i = SkipWs(json, i);
                    var raw = ReadValueRaw(json, ref i);
                    map[k] = raw.StartsWith("\"") ? UnescapeString(raw) : raw;
                    i = SkipWs(json, i);
                    if (i < json.Length && json[i] == ',') { i++; continue; }
                    if (i < json.Length && json[i] == '}') break;
                }
            }
            catch { }
            return map;
        }

        /// <summary>Return the array at the given key as a list of
        /// string-string maps, one per object element.</summary>
        public static List<Dictionary<string, string>> ArrayOfObjects(string json, string key)
        {
            var rows = new List<Dictionary<string, string>>();
            if (string.IsNullOrEmpty(json) || string.IsNullOrEmpty(key)) return rows;
            try
            {
                int idx = IndexOfKey(json, key);
                if (idx < 0) return rows;
                int colon = json.IndexOf(':', idx);
                if (colon < 0) return rows;
                int p = SkipWs(json, colon + 1);
                if (p >= json.Length || json[p] != '[') return rows;
                rows = ParseArrayOfObjectsAt(json, ref p);
            }
            catch { }
            return rows;
        }

        /// <summary>Same as <see cref="ArrayOfObjects"/> but when the response
        /// JSON IS the array, e.g. <c>[ { "id": "...", "name": "..." }, ... ]</c>.</summary>
        public static List<Dictionary<string, string>> TopLevelArrayOfObjects(string json)
        {
            var rows = new List<Dictionary<string, string>>();
            if (string.IsNullOrEmpty(json)) return rows;
            try
            {
                int p = SkipWs(json, 0);
                if (p >= json.Length || json[p] != '[') return rows;
                rows = ParseArrayOfObjectsAt(json, ref p);
            }
            catch { }
            return rows;
        }

        // ---------- Internals ----------

        private static List<Dictionary<string, string>> ParseArrayOfObjectsAt(string json, ref int p)
        {
            var rows = new List<Dictionary<string, string>>();
            if (json[p] != '[') return rows;
            p++;
            while (p < json.Length)
            {
                p = SkipWs(json, p);
                if (p < json.Length && json[p] == ']') { p++; break; }
                if (json[p] == '{')
                {
                    int start = p;
                    SkipValue(json, ref p);
                    var objText = json.Substring(start, p - start);
                    rows.Add(ObjectAsMap(objText));
                }
                else
                {
                    // Non-object element — skip and continue gracefully.
                    SkipValue(json, ref p);
                }
                p = SkipWs(json, p);
                if (p < json.Length && json[p] == ',') { p++; continue; }
                if (p < json.Length && json[p] == ']') { p++; break; }
            }
            return rows;
        }

        // Find the raw JSON text following a given key (first occurrence,
        // case-insensitive). Returns null when not found. Bare values, strings,
        // objects, and arrays are all returned verbatim including their
        // surrounding quotes / braces / brackets.
        private static string FindValue(string json, string key)
        {
            int idx = IndexOfKey(json, key);
            if (idx < 0) return null;
            int colon = json.IndexOf(':', idx);
            if (colon < 0) return null;
            int p = SkipWs(json, colon + 1);
            return ReadValueRaw(json, ref p);
        }

        // Locate the first byte of "key" used as an object key (preceded by
        // a quote, optional whitespace, optional comma/brace before that).
        // Case-insensitive match on the key bytes.
        private static int IndexOfKey(string json, string key)
        {
            int from = 0;
            while (from < json.Length)
            {
                int q = json.IndexOf('"', from);
                if (q < 0) return -1;
                int end = FindStringEnd(json, q);
                if (end < 0) return -1;
                int len = end - q - 1;
                if (len == key.Length &&
                    string.Compare(json, q + 1, key, 0, key.Length,
                                   StringComparison.OrdinalIgnoreCase) == 0)
                {
                    int afterClose = end + 1;
                    int colon = SkipWs(json, afterClose);
                    if (colon < json.Length && json[colon] == ':') return q;
                }
                from = end + 1;
            }
            return -1;
        }

        private static int FindStringEnd(string json, int openQuote)
        {
            for (int i = openQuote + 1; i < json.Length; i++)
            {
                char c = json[i];
                if (c == '\\') { i++; continue; }
                if (c == '"') return i;
            }
            return -1;
        }

        private static int SkipWs(string json, int p)
        {
            while (p < json.Length && (json[p] == ' ' || json[p] == '\t' ||
                                       json[p] == '\r' || json[p] == '\n')) p++;
            return p;
        }

        private static string ReadString(string json, ref int p)
        {
            p = SkipWs(json, p);
            if (p >= json.Length || json[p] != '"') return null;
            int end = FindStringEnd(json, p);
            if (end < 0) return null;
            var raw = json.Substring(p, end - p + 1);
            p = end + 1;
            return UnescapeString(raw);
        }

        // Return the value verbatim — caller decides whether to unwrap strings
        // or recurse into objects/arrays. Advances p to one past the value.
        private static string ReadValueRaw(string json, ref int p)
        {
            p = SkipWs(json, p);
            if (p >= json.Length) return "";
            int start = p;
            char c = json[p];
            if (c == '"')
            {
                int end = FindStringEnd(json, p);
                if (end < 0) { p = json.Length; return ""; }
                p = end + 1;
                return json.Substring(start, p - start);
            }
            if (c == '{' || c == '[')
            {
                SkipValue(json, ref p);
                return json.Substring(start, p - start);
            }
            // bare token (number / true / false / null)
            while (p < json.Length && ",}]\r\n\t ".IndexOf(json[p]) < 0) p++;
            return json.Substring(start, p - start);
        }

        // Walk past a value of any kind. Doesn't validate JSON strictly — the
        // service might emit edge cases the spec wouldn't, and we'd rather
        // return "some data" than throw.
        private static void SkipValue(string json, ref int p)
        {
            p = SkipWs(json, p);
            if (p >= json.Length) return;
            char c = json[p];
            if (c == '"')
            {
                int end = FindStringEnd(json, p);
                p = end < 0 ? json.Length : end + 1;
                return;
            }
            if (c == '{' || c == '[')
            {
                char open = c, close = c == '{' ? '}' : ']';
                int depth = 0;
                while (p < json.Length)
                {
                    char ch = json[p];
                    if (ch == '"')
                    {
                        int end = FindStringEnd(json, p);
                        p = end < 0 ? json.Length : end + 1;
                        continue;
                    }
                    if (ch == open) depth++;
                    else if (ch == close)
                    {
                        depth--;
                        if (depth == 0) { p++; return; }
                    }
                    p++;
                }
                return;
            }
            while (p < json.Length && ",}]\r\n\t ".IndexOf(json[p]) < 0) p++;
        }

        // Unescape \", \\, \n, \r, \t, \/, \uXXXX. Leaves any unrecognised
        // escape verbatim (defensive — we don't want to lose data on a
        // malformed feed).
        private static string UnescapeString(string raw)
        {
            if (string.IsNullOrEmpty(raw)) return "";
            if (raw[0] != '"') return raw;
            int end = raw.Length - 1;
            if (end > 0 && raw[end] == '"') end--;
            var sb = new StringBuilder(raw.Length);
            for (int i = 1; i <= end; i++)
            {
                char c = raw[i];
                if (c != '\\') { sb.Append(c); continue; }
                if (i == end) { sb.Append('\\'); break; }
                char n = raw[++i];
                switch (n)
                {
                    case '"': sb.Append('"'); break;
                    case '\\': sb.Append('\\'); break;
                    case '/': sb.Append('/'); break;
                    case 'b': sb.Append('\b'); break;
                    case 'f': sb.Append('\f'); break;
                    case 'n': sb.Append('\n'); break;
                    case 'r': sb.Append('\r'); break;
                    case 't': sb.Append('\t'); break;
                    case 'u':
                        if (i + 4 <= end)
                        {
                            var hex = raw.Substring(i + 1, 4);
                            if (ushort.TryParse(hex, NumberStyles.HexNumber,
                                                CultureInfo.InvariantCulture, out ushort code))
                            {
                                sb.Append((char)code);
                                i += 4;
                                break;
                            }
                        }
                        sb.Append('\\').Append('u');
                        break;
                    default: sb.Append('\\').Append(n); break;
                }
            }
            return sb.ToString();
        }

        // ---------- Best-effort full parse for WebSocket frames ----------

        /// <summary>Best-effort parse to <c>Dictionary&lt;string, object&gt;</c>
        /// (object) / <c>List&lt;object&gt;</c> (array) / <c>string</c> /
        /// <c>double</c> / <c>bool</c> / null. Returns null on any failure —
        /// callers must check before indexing.</summary>
        public static object Parse(string json)
        {
            if (string.IsNullOrEmpty(json)) return null;
            try
            {
                int p = 0;
                var value = ParseValue(json, ref p);
                return value;
            }
            catch { return null; }
        }

        private static object ParseValue(string json, ref int p)
        {
            p = SkipWs(json, p);
            if (p >= json.Length) return null;
            char c = json[p];
            if (c == '{') return ParseObject(json, ref p);
            if (c == '[') return ParseArray(json, ref p);
            if (c == '"')
            {
                int end = FindStringEnd(json, p);
                if (end < 0) { p = json.Length; return ""; }
                var raw = json.Substring(p, end - p + 1);
                p = end + 1;
                return UnescapeString(raw);
            }
            int start = p;
            while (p < json.Length && ",}]\r\n\t ".IndexOf(json[p]) < 0) p++;
            var token = json.Substring(start, p - start);
            if (token == "true") return true;
            if (token == "false") return false;
            if (token == "null") return null;
            if (double.TryParse(token, NumberStyles.Float,
                                CultureInfo.InvariantCulture, out double d)) return d;
            return token;
        }

        private static Dictionary<string, object> ParseObject(string json, ref int p)
        {
            var obj = new Dictionary<string, object>(StringComparer.OrdinalIgnoreCase);
            if (json[p] != '{') return obj;
            p++;
            while (p < json.Length)
            {
                p = SkipWs(json, p);
                if (p < json.Length && json[p] == '}') { p++; break; }
                string k = ReadString(json, ref p);
                if (k == null) break;
                p = SkipWs(json, p);
                if (p >= json.Length || json[p] != ':') break;
                p++;
                obj[k] = ParseValue(json, ref p);
                p = SkipWs(json, p);
                if (p < json.Length && json[p] == ',') { p++; continue; }
                if (p < json.Length && json[p] == '}') { p++; break; }
            }
            return obj;
        }

        private static List<object> ParseArray(string json, ref int p)
        {
            var arr = new List<object>();
            if (json[p] != '[') return arr;
            p++;
            while (p < json.Length)
            {
                p = SkipWs(json, p);
                if (p < json.Length && json[p] == ']') { p++; break; }
                arr.Add(ParseValue(json, ref p));
                p = SkipWs(json, p);
                if (p < json.Length && json[p] == ',') { p++; continue; }
                if (p < json.Length && json[p] == ']') { p++; break; }
            }
            return arr;
        }
    }
}
