using System;
using Pulse.WPF.Helpers;

namespace Pulse.WPF.Models
{
    /// <summary>
    /// Snapshot of whether the local ScoreConnect III service is detected and
    /// reachable, plus what version it advertised (if anything). Populated by
    /// <see cref="Pulse.WPF.Services.IScoreConnectService.ProbeAsync"/>.
    ///
    /// The probe is a cheap HTTP GET with a short timeout — the panel must
    /// render cleanly even when the service isn't running on this VPU, so
    /// every consumer should treat <see cref="IsDetected"/> as the gate
    /// before reading the other fields.
    ///
    /// Type name is fully namespaced ("ScoreConnect" prefix) to avoid the
    /// BCL collision class we hit in v0.5.0 (EventLogEntry).
    /// </summary>
    public class ScoreConnectStatus : ObservableObject
    {
        private bool _isDetected;
        public bool IsDetected { get => _isDetected; set => Set(ref _isDetected, value); }

        private string _baseUrl = "";
        public string BaseUrl { get => _baseUrl; set => Set(ref _baseUrl, value); }

        private string _version = "";
        public string Version { get => _version; set => Set(ref _version, value); }

        private DateTime? _lastProbedAt;
        public DateTime? LastProbedAt { get => _lastProbedAt; set => Set(ref _lastProbedAt, value); }

        /// <summary>Last error string from a failed probe, empty when the
        /// last probe succeeded. Surfaced in the Service Status card so a
        /// tech can see why detection failed (timeout vs connection refused).</summary>
        private string _probeError = "";
        public string ProbeError { get => _probeError; set => Set(ref _probeError, value); }
    }
}
