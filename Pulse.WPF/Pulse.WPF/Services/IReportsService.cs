using System.Collections.Generic;
using System.Threading.Tasks;
using Pulse.WPF.Models;

namespace Pulse.WPF.Services
{
    /// <summary>
    /// Enumerates and reads saved diagnostic-run reports living under
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
    }
}
