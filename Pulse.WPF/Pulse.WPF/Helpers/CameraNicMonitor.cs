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
        // Stores the timestamp of every *debounced* IsUp transition observed
        // in the last 60 s. >= 3 transitions in the window = flapping.
        //
        // Debounce (v0.5.2 follow-up): Intel I210 NICs report multiple
        // transient up/down/up sequences during gigabit auto-negotiation —
        // a single physical plug-in can fire as much as 3-4 IsUp toggles in
        // a few seconds. We only commit a state change to this list (and to
        // PreviousIsUp) after the new state has held for >= 2 s. The tile's
        // raw responsive state binding is unaffected; only the flap counter
        // and the VM's per-port history feed read from this debounced source.
        public List<DateTime> LinkTransitions { get; } = new List<DateTime>();

        // ---- Sub-debounce flap detection (v0.8.12-beta) ----
        // Timestamps of "pending" transitions that got dropped by the
        // debounce because the raw state flipped back within the window
        // (i.e. raw == PreviousIsUp before the hold-off expired). These
        // are normally NIC negotiation settling noise — but a damaged
        // NIC pin produces the same shape of signal and was being
        // silently filtered. Counted alongside LinkTransitions by
        // FlapCountInWindow so fast flaps surface as flapping just like
        // slow ones. Field test on an 82574L with a damaged pin: this
        // list filled up at ~5-10/sec while LinkTransitions stayed empty,
        // confirming the gap.
        public List<DateTime> NoiseFlaps { get; } = new List<DateTime>();

        // The last *committed* (debounced-stable) IsUp value. The VM reads
        // this for its Recent activity entries.
        public bool? PreviousIsUp { get; set; }
        // The candidate state we're currently waiting to confirm. Set when
        // the raw IsUp first disagrees with PreviousIsUp; cleared either
        // when the raw flips back (it was negotiation noise) or when the
        // pending state has held long enough to be committed.
        public bool? PendingIsUp { get; set; }
        public DateTime? PendingSince { get; set; }

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

        // ---- Cabled-no-link hold-off (v0.5.2 §3) ----
        // Set when the port first enters "link down, but a remote MAC is
        // still cached" — i.e. Windows reports a cable but no negotiation.
        // Cleared when the port leaves that state (either the link comes
        // back up, or the cable is removed and the remote MAC falls off).
        // The recommendations engine only fires the cable-swap advice when
        // (now - CabledNoLinkSince) > 30 s, so a normal unplug — which
        // Windows often shows as cabled-no-link for a tick or two before
        // settling on no-cable — doesn't generate noise.
        public DateTime? CabledNoLinkSince { get; set; }

        // ---- Last successful *resolve* timestamp ----
        // Distinct from LastRemoteAt: this is updated every tick where the
        // current snapshot still carries a real remote, so the 30-second
        // stale window is measured from "we still saw it that recently"
        // rather than "the tile first lit up". When a port goes from
        // linked-with-ARP to linked-without-ARP, this stops advancing and
        // the VM uses (now - LastResolveAt) for the "stale Ns" subscript.
        public DateTime? LastResolveAt { get; set; }

        /// <summary>
        /// Combined transition count (committed + sub-debounce) over the
        /// window. Used for the tile's "↯ Flapping ×N/60s" display so the
        /// number the tech sees reflects everything we observed, not just
        /// committed transitions. Detection itself uses
        /// <see cref="IsFlappingPattern"/> which differentiates the two
        /// signal classes to avoid false positives on a single yank+replug.
        /// </summary>
        public int FlapCountInWindow(TimeSpan window, DateTime now)
        {
            var threshold = now - window;
            int n = 0;
            foreach (var t in LinkTransitions)
                if (t >= threshold) n++;
            foreach (var t in NoiseFlaps)
                if (t >= threshold) n++;
            return n;
        }

        /// <summary>
        /// Committed-transition count only (each entry crossed the 2 s
        /// debounce, meaning the new state held for >= 2 s). Excludes
        /// sub-debounce NoiseFlaps. A single yank-replug produces exactly
        /// 2 committed transitions; sustained slow flapping produces 3+
        /// in a minute.
        /// </summary>
        public int LinkTransitionCountInWindow(TimeSpan window, DateTime now)
        {
            var threshold = now - window;
            int n = 0;
            foreach (var t in LinkTransitions)
                if (t >= threshold) n++;
            return n;
        }

        /// <summary>
        /// Sub-debounce flap count only (raw IsUp toggles that flipped
        /// back inside the 2 s hold-off). I210 NIC settling produces a
        /// brief burst of 3-4 noise events when a link comes up; a damaged
        /// NIC pin produces sustained noise (8+ events in 30 s). The
        /// threshold (8 in 30 s in <see cref="IsFlappingPattern"/>) is set
        /// to be well clear of normal settling.
        /// </summary>
        public int NoiseFlapCountInWindow(TimeSpan window, DateTime now)
        {
            var threshold = now - window;
            int n = 0;
            foreach (var t in NoiseFlaps)
                if (t >= threshold) n++;
            return n;
        }

        /// <summary>
        /// v0.8.13-beta: differentiates real flapping from a single
        /// physical plug cycle. Returns true if EITHER:
        ///   - Committed transitions >= 3 in 60 s window (sustained slow
        ///     flap; a single yank-replug is only 2 transitions and
        ///     doesn't trip this), OR
        ///   - Noise transitions >= 8 in 30 s window (rapid sub-debounce
        ///     hardware bounce; NIC settling produces ~3-4 events at
        ///     most, this threshold is well clear).
        ///
        /// False-positive sanity check across common workflows:
        ///   - Tech yanks + replugs once     -> 2 LinkTransitions + 0-4
        ///                                       NoiseFlaps. NEITHER rule
        ///                                       fires. ✓
        ///   - Damaged pin, slow flap        -> 4-6 LinkTransitions/60 s.
        ///                                       Rule 1 fires. ✓
        ///   - Damaged pin, fast flap        -> 10-30 NoiseFlaps/30 s.
        ///                                       Rule 2 fires. ✓
        ///   - NIC plug-in settling          -> 3-4 NoiseFlaps in 5 s.
        ///                                       Rule 2 needs 8.       ✓
        /// </summary>
        public bool IsFlappingPattern(TimeSpan flapWindow, DateTime now)
        {
            if (LinkTransitionCountInWindow(flapWindow, now) >= 3) return true;
            if (NoiseFlapCountInWindow(TimeSpan.FromSeconds(30), now) >= 8) return true;
            return false;
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
        // How long a new IsUp state must hold before we count it as a real
        // transition. 2 s is long enough to filter out Intel I210 gigabit
        // auto-negotiation noise (which settles in well under a second on
        // healthy hardware) and short enough that legitimate flapping still
        // crosses the threshold quickly. The tile's StatusLine binds to the
        // raw IsUp via the per-tick snapshot — only the flap counter and the
        // VM's Recent-activity history read from the debounced source.
        public TimeSpan TransitionDebounce { get; } = TimeSpan.FromSeconds(2);

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
            // v0.8.9-beta: poll cadence dropped 1 s -> 500 ms for closer-to-
            // real-time link / IP / MAC reaction. Field tech feedback: cable
            // swaps were taking ~1-2 s to reflect on the tile. The underlying
            // reads (NetworkInterface.GetAllNetworkInterfaces + ARP table
            // queries) are kernel-cached IPHLPAPI calls, not real WMI, so
            // doubling the rate has negligible CPU impact on a 4-port NIC.
            // Time-window thresholds (FlapWindow, ErrorWindow,
            // TransitionDebounce) stay in TimeSpan so they're unaffected.
            _timer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(500) };
            _timer.Tick += OnTimerTick;
        }

        /// <summary>Start the monitor and fire one immediate poll.</summary>
        public void Start()
        {
            _timer.Start();
            // Kick an immediate poll so the UI isn't empty for the first second.
            // R12 fix: catch any exception from the initial poll. Previously a
            // fire-and-forget Task swallowed exceptions in PollAsync's later
            // steps (anything after the GetCameraPortsAsync catch). An
            // unhandled exception here would have propagated to the
            // TaskScheduler.UnobservedTaskException event and the app would
            // crash on next GC.
            _ = SafePollAsync();
        }

        public void Stop() => _timer.Stop();

        // v0.8.0-beta: Pause / Resume for the Fault Isolator wizard. While
        // the wizard is open the monitor's 2-s transition debounce + flap
        // detection + DidSpeedRegress would fight the wizard's own per-port
        // poll loop and emit spurious Critical recommendations whenever the
        // tech moves a cable between ports. Distinct from Stop because the
        // monitor lifecycle (subscriptions, internal state) is preserved
        // across the pause — Resume() picks up where Pause() left off.
        private bool _paused;
        public bool IsPaused => _paused;
        public void Pause()
        {
            _paused = true;
            _timer.Stop();
        }
        public void Resume()
        {
            if (!_paused) return;
            _paused = false;
            _timer.Start();
            // Kick an immediate poll so the live panel doesn't lag a full
            // second after the wizard closes.
            _ = SafePollAsync();
        }

        // R3 fix: async void with an unguarded body. Anything in PollAsync
        // after the GetCameraPortsAsync catch (PruneAll, the foreach, the
        // Tick?.Invoke) was unprotected. A throw from RemoteDeviceResolver or
        // anything else inside PollAsync would propagate out of OnTimerTick
        // as an unhandled exception on the UI thread — instant crash. The
        // wrapper below catches anything to ensure the timer keeps running.
        private async void OnTimerTick(object sender, EventArgs e)
        {
            if (_ticksToSkip > 0) { _ticksToSkip--; return; }
            await SafePollAsync().ConfigureAwait(true);
        }

        private async Task SafePollAsync()
        {
            try { await PollAsync().ConfigureAwait(true); }
            catch (Exception ex)
            {
                // Don't crash the monitor on a one-off poll exception.
                System.Diagnostics.Debug.WriteLine($"CameraNicMonitor.PollAsync threw: {ex}");
                // Treat it like the documented backoff so a flapping
                // GetCameraPortsAsync doesn't burn the UI thread.
                _consecutiveFailures = Math.Min(_consecutiveFailures + 1, 10);
                _ticksToSkip = Math.Min(MaxTicksToSkip, 1 << Math.Min(5, Math.Max(0, _consecutiveFailures - 1)));
            }
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
                _ticksToSkip = Math.Min(MaxTicksToSkip, 1 << Math.Min(5, Math.Max(0, _consecutiveFailures - 1)));
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

                // -- IsUp transition tracking (with debounce) --
                // PreviousIsUp is the last *committed* (stable for >=
                // TransitionDebounce) state. PendingIsUp tracks a candidate
                // change we're holding off on. See the field comments on
                // PortState for the why; the short version is that I210 NICs
                // emit settling noise during gigabit auto-negotiation and we
                // don't want that to look like flap.
                bool currentIsUp = s.IsUp;
                if (!st.PreviousIsUp.HasValue)
                {
                    // First observation; seed without debounce so we have a
                    // baseline. Subsequent changes will be debounced.
                    st.PreviousIsUp = currentIsUp;
                    if (currentIsUp) st.LinkUpSince = now;
                }
                else if (currentIsUp == st.PreviousIsUp.Value)
                {
                    // Raw state matches the committed state — any pending
                    // change was either negotiation noise OR a sub-debounce
                    // flap from a damaged NIC. We can't tell them apart at
                    // this single moment, so record the drop as a "noise
                    // flap" timestamp. FlapCountInWindow now sums these in
                    // alongside LinkTransitions; a few drops in a minute is
                    // benign settling, but a damaged-pin port produces
                    // dozens per minute and trips the flap threshold.
                    //
                    // v0.8.12-beta: was previously throwing the timestamp
                    // away entirely - rapid flaps from a damaged pin went
                    // unflagged.
                    if (st.PendingIsUp.HasValue)
                        st.NoiseFlaps.Add(now);
                    st.PendingIsUp = null;
                    st.PendingSince = null;
                }
                else
                {
                    // Raw state differs from committed. Either start a fresh
                    // hold-off window or continue the existing one.
                    if (!st.PendingIsUp.HasValue || st.PendingIsUp.Value != currentIsUp)
                    {
                        st.PendingIsUp = currentIsUp;
                        st.PendingSince = now;
                    }
                    else if ((now - st.PendingSince.Value) >= TransitionDebounce)
                    {
                        // Pending has held long enough — commit the transition.
                        st.LinkTransitions.Add(now);
                        st.PreviousIsUp = currentIsUp;
                        if (currentIsUp) st.LinkUpSince = now;
                        else             st.LinkUpSince = null;
                        st.PendingIsUp = null;
                        st.PendingSince = null;
                    }
                    // else: still inside the hold-off window; keep waiting.
                }

                // -- Error-count sample --
                st.ErrorSamples.Add((now, s.ErrorCount));

                // -- Cabled-no-link tracking (v0.5.2 §3) --
                // "Cabled no link" = link is down AND we have a remote MAC
                // cached. Set the timestamp on first entry, clear when the
                // port leaves the state.
                bool isCabledNoLink = !s.IsUp && !string.IsNullOrEmpty(s.RemoteMac);
                if (isCabledNoLink)
                {
                    if (!st.CabledNoLinkSince.HasValue) st.CabledNoLinkSince = now;
                }
                else
                {
                    st.CabledNoLinkSince = null;
                }

                // -- Last-seen remote snapshot --
                // After bug-fix #1/#2/#3, RemoteMac is null when the only ARP
                // candidate was the local self-IP or an INCOMPLETE row. We
                // therefore only stamp LastRemoteAt / LastResolveAt when the
                // remote is *real*. The VM uses LastResolveAt to drive the
                // 30-second stale window (§7).
                if (!string.IsNullOrEmpty(s.RemoteMac))
                {
                    st.LastRemoteIp = s.RemoteIp;
                    st.LastRemoteMac = s.RemoteMac;
                    st.LastRemoteAt = now;
                    st.LastResolveAt = now;
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

                // v0.8.12-beta: same prune pass for the new NoiseFlaps list
                // so a damaged-pin port doesn't accumulate unbounded
                // sub-debounce flap timestamps over hours of runtime.
                int nfWriteIdx = 0;
                for (int i = 0; i < st.NoiseFlaps.Count; i++)
                {
                    if (st.NoiseFlaps[i] >= flapThreshold)
                    {
                        st.NoiseFlaps[nfWriteIdx++] = st.NoiseFlaps[i];
                    }
                }
                if (nfWriteIdx < st.NoiseFlaps.Count)
                    st.NoiseFlaps.RemoveRange(nfWriteIdx, st.NoiseFlaps.Count - nfWriteIdx);

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
