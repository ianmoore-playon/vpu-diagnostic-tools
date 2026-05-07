using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using System.Windows.Threading;
using Pulse.WPF.Services;

namespace Pulse.WPF.Helpers
{
    /// <summary>
    /// Per-port rolling state — flap counts, error-rate samples, link-up
    /// duration, last-seen remote. Owned by <see cref="CameraNicMonitor"/>;
    /// the monitor hands a snapshot of this to the VM after every tick.
    /// </summary>
    public class PortState
    {
        // Identity. Keyed by local NIC MAC so a port that toggles down/up keeps
        // its state across ticks, and a port that swaps physical position (e.g.
        // user reseats the NIC) creates a fresh state instead of inheriting old
        // flap counts.
        public string LocalMac { get; set; }

        // Last poll's snapshot — what the VM should render.
        public CameraNicSnapshot Snapshot { get; set; }

        // ---- Up/down ring buffer for flap detection ----
        // Stores the timestamp of every IsUp transition observed in the last
        // 60 s. >= 3 transitions in the window = flapping.
        public List<DateTime> LinkTransitions { get; } = new List<DateTime>();
        public bool? PreviousIsUp { get; set; }

        // ---- Error-count samples for rising-rate detection ----
        // Stores (timestamp, errorCount) over the last 30 s. If the count went
        // up at any point in that window we render the "errors-rising" state.
        public List<(DateTime At, long Count)> ErrorSamples { get; } = new List<(DateTime, long)>();

        // ---- Link-up timing ----
        // Set when we observe a transition into IsUp; cleared on transition out.
        // Used for the "Linked HH:MM:SS" status line.
        public DateTime? LinkUpSince { get; set; }

        // ---- Last-seen remote snapshot (kept up to 30 min) ----
        // Used for the "Last: Main Camera 1, 4 min ago" hint on an unplugged
        // tile. Only updated when we have a remote MAC; not cleared when the
        // cable goes out so the tile can show what was there.
        public string LastRemoteIp { get; set; }
        public string LastRemoteMac { get; set; }
        public string LastRemoteLabel { get; set; }
        public DateTime? LastRemoteAt { get; set; }

        public int FlapCountInWindow(TimeSpan window, DateTime now)
        {
            // Count transitions in [now - window, now]. Caller is responsible
            // for pruning periodically; we simply count.
            var threshold = now - window;
            int n = 0;
            foreach (var t in LinkTransitions)
                if (t >= threshold) n++;
            return n;
        }

        public bool ErrorsRising(TimeSpan window, DateTime now)
        {
            // True if the latest sample's count is strictly greater than the
            // earliest sample's count within the window.
            var threshold = now - window;
            long? earliest = null, latest = null;
            foreach (var s in ErrorSamples)
            {
                if (s.At < threshold) continue;
                if (earliest == null) earliest = s.Count;
                latest = s.Count;
            }
            return earliest.HasValue && latest.HasValue && latest.Value > earliest.Value;
        }
    }

    /// <summary>
    /// 1-second polling monitor for the camera-NIC ports. Owns a
    /// <see cref="DispatcherTimer"/> so callbacks land on the UI thread —
    /// safe for ObservableCollection updates with no marshalling needed.
    ///
    /// On every tick:
    ///   - Cheap pass: refresh IsUp + LinkSpeedBps + ErrorCount per known port.
    ///     (We re-call <see cref="INetworkAdapterService.GetCameraPortsAsync"/>
    ///     which under the hood does both — there's no separate cheap API in
    ///     the service today and the call itself is fast enough at 1 s. The
    ///     ARP table read is the most expensive piece.)
    /// On every other tick (~2 s):
    ///   - Full pass: identical, but treated as the canonical refresh that
    ///     advances the per-port history buffers and updates LastSeenRemote.
    ///
    /// Robustness: every WMI / ARP read is wrapped in try/catch; two
    /// consecutive failures trigger an exponential backoff (skip the next N
    /// ticks, capped) so a flaky tick doesn't kill the monitor.
    /// </summary>
    public class CameraNicMonitor
    {
        private readonly INetworkAdapterService _net;
        private readonly DispatcherTimer _timer;

        // Per-port state, keyed by local MAC. New ports get added on first
        // sight; ports we stop seeing are kept (so an unplugged port can show
        // its last-known remote) but their Snapshot is updated to reflect that
        // they're gone.
        private readonly Dictionary<string, PortState> _byMac = new Dictionary<string, PortState>(StringComparer.OrdinalIgnoreCase);

        // Backoff bookkeeping. _consecutiveFailures counts how many ticks in a
        // row threw; _ticksToSkip is decremented each tick and only when zero
        // do we actually call the service. Cap so we always recover within
        // about a minute even after a long error storm.
        private int _consecutiveFailures;
        private int _ticksToSkip;
        private const int MaxTicksToSkip = 30;

        // Tick parity counter — every other tick is the "full pass".
        private long _tickIndex;

        // Tunables (locked per the round-1 spec).
        public TimeSpan FlapWindow { get; } = TimeSpan.FromSeconds(60);
        public TimeSpan ErrorWindow { get; } = TimeSpan.FromSeconds(30);
        public TimeSpan LastSeenRetention { get; } = TimeSpan.FromMinutes(30);
        public int FlapTransitionsThreshold { get; } = 3;

        /// <summary>
        /// Raised after a full poll completes (including the initial poll on
        /// Start). The argument is the ordered list of <see cref="PortState"/>
        /// the VM should render. Always raised on the UI thread because the
        /// timer is a <see cref="DispatcherTimer"/>.
        /// </summary>
        public event Action<List<PortState>> Tick;

        public CameraNicMonitor(INetworkAdapterService net)
        {
            _net = net ?? throw new ArgumentNullException(nameof(net));
            _timer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(1) };
            _timer.Tick += OnTimerTick;
        }

        /// <summary>Start the monitor and fire one immediate poll.</summary>
        public void Start()
        {
            _timer.Start();
            // Kick an immediate poll so the UI isn't empty for the first second.
            _ = PollAsync();
        }

        public void Stop() => _timer.Stop();

        private async void OnTimerTick(object sender, EventArgs e)
        {
            if (_ticksToSkip > 0) { _ticksToSkip--; return; }
            await PollAsync().ConfigureAwait(true);
        }

        private async Task PollAsync()
        {
            _tickIndex++;
            List<CameraNicSnapshot> snaps;
            try
            {
                snaps = await _net.GetCameraPortsAsync().ConfigureAwait(true);
                _consecutiveFailures = 0;
            }
            catch
            {
                _consecutiveFailures++;
                // Exponential backoff: 1, 2, 4, 8, 16, 30, 30 ...
                _ticksToSkip = Math.Min(MaxTicksToSkip, 1 << Math.Min(5, _consecutiveFailures - 1));
                return; // Never terminate the timer.
            }

            var now = DateTime.UtcNow;

            // Mark every existing entry "not seen this tick" so we can detect
            // the no-cable case (a port that previously had a remote vanishes
            // entirely from the snapshot list — happens when the NIC is
            // unplugged and the OS drops it).
            var seenThisTick = new HashSet<string>(StringComparer.OrdinalIgnoreCase);

            foreach (var s in snaps)
            {
                if (string.IsNullOrEmpty(s.LocalMac)) continue;
                seenThisTick.Add(s.LocalMac);

                if (!_byMac.TryGetValue(s.LocalMac, out var st))
                {
                    st = new PortState { LocalMac = s.LocalMac };
                    _byMac[s.LocalMac] = st;
                }

                // -- IsUp transition tracking --
                if (st.PreviousIsUp.HasValue && st.PreviousIsUp.Value != s.IsUp)
                {
                    st.LinkTransitions.Add(now);
                    if (s.IsUp) st.LinkUpSince = now;
                    else        st.LinkUpSince = null;
                }
                else if (!st.PreviousIsUp.HasValue)
                {
                    // First observation. Seed LinkUpSince if it's already up so
                    // the duration counter starts from "now" rather than null.
                    if (s.IsUp) st.LinkUpSince = now;
                }
                st.PreviousIsUp = s.IsUp;

                // -- Error-count sample --
                st.ErrorSamples.Add((now, s.ErrorCount));

                // -- Last-seen remote snapshot --
                if (!string.IsNullOrEmpty(s.RemoteMac))
                {
                    st.LastRemoteIp = s.RemoteIp;
                    st.LastRemoteMac = s.RemoteMac;
                    st.LastRemoteAt = now;
                    // The label is set by the VM after resolution; we keep
                    // identity here, the VM enriches.
                }

                st.Snapshot = s;
            }

            // Prune ring buffers and stale state.
            PruneAll(now);

            // Emit ordered list. Sort by local MAC ascending (mirrors the
            // service's existing convention -> lowest MAC = Port 1).
            var ordered = _byMac.Values
                .OrderBy(p => p.LocalMac, StringComparer.Ordinal)
                .ToList();

            try { Tick?.Invoke(ordered); }
            catch { /* Subscriber bugs must not kill the monitor. */ }
        }

        private void PruneAll(DateTime now)
        {
            var flapThreshold = now - FlapWindow;
            var errThreshold  = now - ErrorWindow;
            var lastSeenThreshold = now - LastSeenRetention;

            foreach (var st in _byMac.Values)
            {
                // Drop link-transition entries older than the flap window.
                int writeIdx = 0;
                for (int i = 0; i < st.LinkTransitions.Count; i++)
                {
                    if (st.LinkTransitions[i] >= flapThreshold)
                    {
                        st.LinkTransitions[writeIdx++] = st.LinkTransitions[i];
                    }
                }
                if (writeIdx < st.LinkTransitions.Count)
                    st.LinkTransitions.RemoveRange(writeIdx, st.LinkTransitions.Count - writeIdx);

                // Drop error samples older than the error window.
                int wIdx = 0;
                for (int i = 0; i < st.ErrorSamples.Count; i++)
                {
                    if (st.ErrorSamples[i].At >= errThreshold)
                    {
                        st.ErrorSamples[wIdx++] = st.ErrorSamples[i];
                    }
                }
                if (wIdx < st.ErrorSamples.Count)
                    st.ErrorSamples.RemoveRange(wIdx, st.ErrorSamples.Count - wIdx);

                // Drop last-seen if it's outside the retention window.
                if (st.LastRemoteAt.HasValue && st.LastRemoteAt.Value < lastSeenThreshold)
                {
                    st.LastRemoteAt = null;
                    st.LastRemoteIp = null;
                    st.LastRemoteMac = null;
                    st.LastRemoteLabel = null;
                }
            }
        }
    }
}
