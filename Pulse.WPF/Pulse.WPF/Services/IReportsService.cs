using System.Collections.Generic;
using System.Threading.Tasks;
using Pulse.WPF.Models;

namespace Pulse.WPF.Services
{
    /// <summary>
    /// Enumerates and reads saved diagnostic-run reports and support bundles living under
    /// %LOCALAPPDATA%\Pulse.WPF\Reports. Implementations must never throw
    /// from IO — the panel falls back to an empty state.
    /// </summary>
    public interface IReportsService
    {
        /// <summary>Returns the most-recent reports, newest first, capped at 200.</summary>
        Task<List<Report>> GetAllAsync();

        /// <summary>Reads the full text of a saved report.</summary>
        Task<string> ReadAsync(string fileName);

        /// <summary>Deletes a saved report. Returns true on success.</summary>
        bool Delete(string fileName);

        /// <summary>The directory reports live in (also the target of "Open Folder").</summary>
        string ReportsDirectory { get; }

        /// <summary>The directory the rolling daily log lives in.
        /// Surfaced via AppLogFile so the Reports panel's "Open Logs Folder"
        /// button has somewhere to point at.</summary>
        string LogsDirectory { get; }

        /// <summary>Full path to today's rolling log file. Empty / non-existent
        /// when the day's log hasn't been touched yet.</summary>
        string TodayLogPath { get; }

        /// <summary>Tail of today's rolling app log — used by the Reports
        /// panel's App Log sub-card. Returns oldest-first.</summary>
        System.Collections.Generic.IReadOnlyList<string> GetRecentAppLogLines(int count);

        /// <summary>Prune reports older than the cutoff. The 200-file cap in
        /// <see cref="GetAllAsync"/> still applies as a secondary ceiling.</summary>
        void CleanupOlderThan(int days);
    }
}
