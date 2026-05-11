using System;

namespace Pulse.WPF.Helpers
{
    /// <summary>
    /// Tiny `catch {}` replacement. The two diagnostic services together have
    /// ~26 silent catches between them; each one swallows a real failure
    /// without telling the UI. <see cref="Run{T}(Func{T}, T, Action{Exception})"/>
    /// keeps the "don't take the panel down" contract while routing the
    /// exception through an optional callback so the Dashboard log sink (or
    /// any future telemetry surface) can finally see what failed.
    ///
    /// Used by Services/DashboardService.cs (Phase 5 migration). Lower-
    /// volume callers in NetworkService follow as time allows — this is
    /// drop-in compatible with existing code, no behaviour change unless an
    /// onError callback is supplied.
    /// </summary>
    public static class Try
    {
        /// <summary>
        /// Run <paramref name="action"/> and return its value. On exception,
        /// invoke <paramref name="onError"/> (also wrapped in a swallow so
        /// the logger itself can't crash the host) and return
        /// <paramref name="fallback"/>.
        /// </summary>
        public static T Run<T>(Func<T> action, T fallback = default, Action<Exception> onError = null)
        {
            if (action == null) return fallback;
            try
            {
                return action();
            }
            catch (Exception ex)
            {
                if (onError != null)
                {
                    try { onError(ex); } catch { }
                }
                return fallback;
            }
        }

        /// <summary>Void-returning overload.</summary>
        public static void Run(Action action, Action<Exception> onError = null)
        {
            if (action == null) return;
            try
            {
                action();
            }
            catch (Exception ex)
            {
                if (onError != null)
                {
                    try { onError(ex); } catch { }
                }
            }
        }
    }
}
