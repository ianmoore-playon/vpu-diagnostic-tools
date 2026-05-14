using System.Collections.Generic;
using System.Threading.Tasks;
using Pulse.WPF.Models;

namespace Pulse.WPF.Services
{
    /// <summary>
    /// Reads filtered Windows event-log entries relevant to Pixellot VPU
    /// operation. Implementation reads the Application + System logs via
    /// <see cref="System.Diagnostics.EventLog"/> and tolerates the security
    /// exceptions that locked-down VPU images throw on first read.
    /// </summary>
    public interface IEventViewerService
    {
        /// <summary>
        /// Log names/details that could not be read during the last query.
        /// An empty list means the query inspected every configured log.
        /// </summary>
        IReadOnlyList<string> LastReadFailures { get; }

        /// <summary>
        /// Returns the most-recent event-log entries that match the supplied
        /// filters. Capped at 500 rows to keep the UI responsive.
        ///
        /// <paramref name="sources"/> matches case-insensitively against the
        /// start of <c>WindowsEventEntry.Source</c> so caller can pass either an
        /// exact source name ("WHEA-Logger") or a prefix ("Pixellot").
        /// </summary>
        Task<List<WindowsEventEntry>> GetRecentAsync(int hoursBack,
                                                 IEnumerable<string> sources,
                                                 IEnumerable<string> levels);
    }
}
