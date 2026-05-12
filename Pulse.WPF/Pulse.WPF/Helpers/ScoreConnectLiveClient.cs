using System;
using System.Collections.Generic;
using System.Net.WebSockets;
using System.Text;
using System.Threading;
using System.Threading.Tasks;

namespace Pulse.WPF.Helpers
{
    /// <summary>
    /// Live data feed for the Score Connect panel. Wraps a
    /// <see cref="ClientWebSocket"/> against the ScoreConnect III WebSocket
    /// middleware with auto-reconnect, per-frame defensive parsing, and a
    /// <see cref="MessageReceived"/> event the panel VM subscribes to.
    ///
    /// Path discovery: the binary's <c>UseWebSocketsMiddleware</c> doesn't
    /// expose its path in the strings dump, so this client probes a small
    /// fixed list of common candidates in order and remembers the first one
    /// that produces a successful upgrade. The path it settled on is exposed
    /// via <see cref="EffectivePath"/> so the operator can see it in the panel.
    ///
    /// Reconnect: on any disconnect (close, error, timeout) the client
    /// retries with exponential backoff capped at 30 s. The loop exits only
    /// when <see cref="StopAsync"/> cancels the inner token.
    ///
    /// Threading: the <see cref="MessageReceived"/> event is raised from the
    /// receive loop thread — subscribers must marshal to the UI dispatcher
    /// themselves.
    /// </summary>
    public sealed class ScoreConnectLiveClient : IDisposable
    {
        // Candidate paths to try on the first connect. The middleware
        // doesn't constrain the path in the binary; "/" is the most likely
        // bet for a pure-middleware setup, but "/ws" and the SignalR-style
        // "/hub" are common enough we try them too.
        private static readonly string[] CandidatePaths = { "/ws", "/", "/scoreconnect/ws", "/notifications" };

        private readonly string _httpBaseUrl;
        private CancellationTokenSource _cts;
        private Task _runTask;
        private ClientWebSocket _ws;
        private readonly object _gate = new object();

        public bool IsConnected { get; private set; }
        public string EffectivePath { get; private set; } = "";

        /// <summary>Raised once per inbound frame. <c>raw</c> is the UTF-8
        /// decoded payload as-received; <c>parsed</c> is a best-effort
        /// dictionary projection, null when parsing failed (binary frames or
        /// malformed JSON).</summary>
        public event Action<string, Dictionary<string, object>> MessageReceived;

        public event Action<bool> ConnectionStateChanged;

        public ScoreConnectLiveClient(string httpBaseUrl)
        {
            if (string.IsNullOrWhiteSpace(httpBaseUrl))
                throw new ArgumentException("httpBaseUrl required", nameof(httpBaseUrl));
            _httpBaseUrl = httpBaseUrl.TrimEnd('/');
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
            Task t;
            lock (_gate)
            {
                cts = _cts;
                t = _runTask;
                _cts = null;
                _runTask = null;
            }
            try { cts?.Cancel(); } catch { }
            try
            {
                if (_ws != null && _ws.State == WebSocketState.Open)
                {
                    try
                    {
                        using (var ctsClose = new CancellationTokenSource(TimeSpan.FromSeconds(2)))
                        {
                            await _ws.CloseAsync(WebSocketCloseStatus.NormalClosure,
                                                 "shutdown",
                                                 ctsClose.Token).ConfigureAwait(false);
                        }
                    }
                    catch { }
                }
            }
            catch { }
            try { if (t != null) await t.ConfigureAwait(false); } catch { }
            SetConnected(false);
        }

        public async Task SendAsync(string message)
        {
            var ws = _ws;
            if (ws == null || ws.State != WebSocketState.Open) return;
            try
            {
                var bytes = Encoding.UTF8.GetBytes(message ?? "");
                using (var cts = new CancellationTokenSource(TimeSpan.FromSeconds(5)))
                {
                    await ws.SendAsync(new ArraySegment<byte>(bytes),
                                       WebSocketMessageType.Text,
                                       endOfMessage: true,
                                       cancellationToken: cts.Token).ConfigureAwait(false);
                }
            }
            catch (Exception ex)
            {
                AppLogFile.Instance.WriteLine("ScoreConnect", "Warn",
                    $"WebSocket send failed: {ex.Message}");
            }
        }

        // ---------- Inner connect/reconnect loop ----------

        private async Task RunLoopAsync(CancellationToken ct)
        {
            // Per-attempt backoff: 1s, 2s, 4s, ..., capped at 30s. Reset to
            // 1s after every successful connect so a flapping service that
            // briefly drops then comes back doesn't blow the backoff out.
            int backoffSeconds = 1;
            // Index into CandidatePaths; sticky after the first success.
            int pathIndex = 0;

            while (!ct.IsCancellationRequested)
            {
                var path = CandidatePaths[pathIndex];
                bool ok = await TryConnectAndPumpAsync(path, ct).ConfigureAwait(false);
                if (ok)
                {
                    backoffSeconds = 1;
                    // Path stays sticky. Next iteration uses the same one.
                    continue;
                }

                // Failed to connect on this path — rotate through the
                // candidates ONCE before falling into the backoff sleep.
                // After we've tried all of them, sleep and try again.
                pathIndex = (pathIndex + 1) % CandidatePaths.Length;
                if (pathIndex != 0)
                {
                    continue;
                }

                try
                {
                    await Task.Delay(TimeSpan.FromSeconds(backoffSeconds), ct).ConfigureAwait(false);
                }
                catch (OperationCanceledException) { return; }
                backoffSeconds = Math.Min(30, backoffSeconds * 2);
            }
        }

        // One full connect + receive lifecycle. Returns true if we
        // successfully got to State==Open at any point (so the outer loop
        // can keep the path sticky), false on connect failure.
        private async Task<bool> TryConnectAndPumpAsync(string path, CancellationToken ct)
        {
            ClientWebSocket ws = null;
            try
            {
                ws = new ClientWebSocket();
                var wsUrl = BuildWsUrl(path);
                using (var ctsConnect = CancellationTokenSource.CreateLinkedTokenSource(ct))
                {
                    ctsConnect.CancelAfter(TimeSpan.FromSeconds(5));
                    await ws.ConnectAsync(new Uri(wsUrl), ctsConnect.Token).ConfigureAwait(false);
                }

                _ws = ws;
                EffectivePath = path;
                AppLogFile.Instance.WriteLine("ScoreConnect", "Pass",
                    $"WebSocket connected at {wsUrl}");
                SetConnected(true);

                await PumpReceiveAsync(ws, ct).ConfigureAwait(false);
                return true;
            }
            catch (OperationCanceledException) when (ct.IsCancellationRequested)
            {
                return true; // outer loop will exit
            }
            catch (Exception ex)
            {
                // 404 / wrong path / refused — log and let the caller rotate.
                AppLogFile.Instance.WriteLine("ScoreConnect", "Info",
                    $"WebSocket connect failed at {BuildWsUrl(path)}: {ex.Message}");
                return false;
            }
            finally
            {
                SetConnected(false);
                try { ws?.Dispose(); } catch { }
                _ws = null;
            }
        }

        private string BuildWsUrl(string path)
        {
            // http://localhost:5000  -> ws://localhost:5000/path
            // https://...:5001       -> wss://...:5001/path
            string scheme;
            if (_httpBaseUrl.StartsWith("https://", StringComparison.OrdinalIgnoreCase))
                scheme = "wss://";
            else
                scheme = "ws://";
            string hostPath = _httpBaseUrl;
            int idx = hostPath.IndexOf("://", StringComparison.Ordinal);
            if (idx >= 0) hostPath = hostPath.Substring(idx + 3);
            if (string.IsNullOrEmpty(path) || path == "/") return scheme + hostPath + "/";
            if (!path.StartsWith("/")) path = "/" + path;
            return scheme + hostPath + path;
        }

        private async Task PumpReceiveAsync(ClientWebSocket ws, CancellationToken ct)
        {
            var buffer = new byte[16 * 1024];
            var assembled = new MemoryAccumulator();
            while (ws.State == WebSocketState.Open && !ct.IsCancellationRequested)
            {
                WebSocketReceiveResult r;
                try
                {
                    r = await ws.ReceiveAsync(new ArraySegment<byte>(buffer), ct)
                                .ConfigureAwait(false);
                }
                catch (OperationCanceledException) { return; }
                catch (Exception ex)
                {
                    AppLogFile.Instance.WriteLine("ScoreConnect", "Warn",
                        $"WebSocket receive failed: {ex.Message}");
                    return;
                }
                if (r.MessageType == WebSocketMessageType.Close)
                {
                    AppLogFile.Instance.WriteLine("ScoreConnect", "Info",
                        $"WebSocket closed by server: {r.CloseStatus} {r.CloseStatusDescription}");
                    return;
                }
                if (r.Count > 0) assembled.Append(buffer, r.Count);
                if (!r.EndOfMessage) continue;

                var raw = assembled.TakeText();
                if (string.IsNullOrEmpty(raw)) continue;
                Dictionary<string, object> parsed = null;
                try
                {
                    var obj = JsonScrape.Parse(raw);
                    parsed = obj as Dictionary<string, object>;
                }
                catch { }

                try { MessageReceived?.Invoke(raw, parsed); }
                catch (Exception ex)
                {
                    AppLogFile.Instance.WriteLine("ScoreConnect", "Warn",
                        $"WebSocket subscriber threw: {ex.Message}");
                }
            }
        }

        private void SetConnected(bool connected)
        {
            if (IsConnected == connected) return;
            IsConnected = connected;
            try { ConnectionStateChanged?.Invoke(connected); } catch { }
        }

        public void Dispose()
        {
            try { _cts?.Cancel(); } catch { }
            try { _ws?.Dispose(); } catch { }
            try { _cts?.Dispose(); } catch { }
        }

        // Tiny growing-buffer for multi-frame messages. Avoids the
        // allocation churn of new MemoryStream per frame on a chatty feed.
        private sealed class MemoryAccumulator
        {
            private byte[] _buf = new byte[16 * 1024];
            private int _len;
            public void Append(byte[] src, int count)
            {
                if (_len + count > _buf.Length)
                {
                    int next = Math.Max(_buf.Length * 2, _len + count);
                    Array.Resize(ref _buf, next);
                }
                Buffer.BlockCopy(src, 0, _buf, _len, count);
                _len += count;
            }
            public string TakeText()
            {
                var s = Encoding.UTF8.GetString(_buf, 0, _len);
                _len = 0;
                return s;
            }
        }
    }
}
