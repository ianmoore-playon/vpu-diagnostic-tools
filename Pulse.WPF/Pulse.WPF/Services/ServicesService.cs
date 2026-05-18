using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Linq;
using System.ServiceProcess;
using Pulse.WPF.Models;

namespace Pulse.WPF.Services
{
    /// <summary>
    /// Pure-C# port of PixellotServices.psm1. Process-name set matches the
    /// canonical $required list there: Agent, KeepAgentUp, Coordinator,
    /// LogMeIn, plus VPU (informational) and Scoreconnect* (services + procs).
    /// </summary>
    public class ServicesService : IServicesService
    {
        // Required core processes. D5 fix: severity is now per-process, not
        // uniformly Critical. Agent and Coordinator are stream-affecting -> Fail.
        // KeepAgentUp is a watchdog and LogMeIn is remote support; neither
        // affects streaming/recording, so they're demoted to Warn. This stops
        // the panel from screaming Critical when LogMeIn happens to be down.
        private static readonly (string Proc, string Label, string MissingSeverity)[] RequiredCore =
        {
            ("Agent",       "Agent.exe",       "Fail"),
            ("Coordinator", "Coordinator.exe", "Fail"),
            ("KeepAgentUp", "KeepAgentUp.exe", "Warn"),
            ("LogMeIn",     "LogMeIn.exe",     "Warn"),
        };

        public List<ServiceStatusRow> GetServiceStatuses()
        {
            var rows = new List<ServiceStatusRow>();

            foreach (var item in RequiredCore)
            {
                rows.Add(BuildProcessRow(item.Proc, item.Label, requireRunning: true, missingSeverity: item.MissingSeverity));
            }

            // VPU.exe — informational; not running is normal when cameras are idle.
            rows.Add(BuildProcessRow("VPU", "VPU.exe", requireRunning: false, missingSeverity: "Gray"));

            // Scoreconnect — both service & process detection.
            rows.Add(BuildScoreconnectRow());

            return rows;
        }

        // R2 fix: Process objects from GetProcessesByName own kernel handles
        // and were never disposed. ~5 handles leaked per refresh; over a 24-h
        // baseline run that's >100k leaked handles. Now wrapped in
        // try/finally so every Process returned is disposed before return.
        private static ServiceStatusRow BuildProcessRow(string procName, string label, bool requireRunning, string missingSeverity = "Fail")
        {
            Process[] procs = null;
            try
            {
                procs = Process.GetProcessesByName(procName);
                if (procs.Length > 0)
                {
                    var pids = string.Join(", ", procs.Select(p => p.Id.ToString()));
                    return new ServiceStatusRow
                    {
                        Name = label,
                        DisplayName = procName,
                        RowKind = "Process",
                        StartMode = "Process",
                        RestartUnavailableReason = "Restart unavailable for process rows",
                        Status = "Running",
                        Detail = $"PID {pids}",
                        Severity = "Pass",
                    };
                }
                if (!requireRunning)
                {
                    return new ServiceStatusRow
                    {
                        Name = label,
                        DisplayName = procName,
                        RowKind = "Process",
                        StartMode = "Process",
                        RestartUnavailableReason = "Restart unavailable for process rows",
                        Status = "Stopped",
                        Detail = "Not running — normal when cameras are idle",
                        Severity = "Gray",
                    };
                }
                return new ServiceStatusRow
                {
                    Name = label,
                    DisplayName = procName,
                    RowKind = "Process",
                    StartMode = "Process",
                    RestartUnavailableReason = "Restart unavailable for process rows",
                    Status = "Stopped",
                    Detail = "Required process not running",
                    Severity = missingSeverity,
                };
            }
            catch (Exception ex)
            {
                return new ServiceStatusRow
                {
                    Name = label,
                    DisplayName = procName,
                    RowKind = "Process",
                    StartMode = "Process",
                    RestartUnavailableReason = "Restart unavailable for process rows",
                    Status = "Unknown",
                    Detail = $"Query failed: {ex.Message}",
                    Severity = "Warn",
                };
            }
            finally
            {
                if (procs != null)
                    foreach (var p in procs) { try { p.Dispose(); } catch { } }
            }
        }

        private static ServiceStatusRow BuildScoreconnectRow()
        {
            ServiceController[] services = null;
            Process[] procs = null;
            Process[] allProcs = null;   // R2 fix: capture the full enumerate so we dispose every Process, not just the Scoreconnect-named ones
            try { services = ServiceController.GetServices()
                .Where(s => s.ServiceName.StartsWith("Scoreconnect", StringComparison.OrdinalIgnoreCase) ||
                            (s.DisplayName != null && s.DisplayName.StartsWith("Scoreconnect", StringComparison.OrdinalIgnoreCase)))
                .ToArray(); }
            catch { services = new ServiceController[0]; }

            try
            {
                allProcs = Process.GetProcesses();
                procs = allProcs
                    .Where(p => SafeStartsWith(p.ProcessName, "Scoreconnect"))
                    .ToArray();
            }
            catch { procs = new Process[0]; }
            // ServiceController objects also wrap an unmanaged handle. They
            // were never disposed either; schedule them for disposal at end.
            try
            {
                // Wrap the whole row-build in try/finally so the disposal
                // happens regardless of which return branch fires below.
                return BuildScoreconnectRowCore(services, procs);
            }
            finally
            {
                if (services != null)
                    foreach (var s in services) { try { s.Dispose(); } catch { } }
                if (allProcs != null)
                    foreach (var p in allProcs) { try { p.Dispose(); } catch { } }
                // procs is a subset of allProcs — already disposed above.
            }
        }

        private static ServiceStatusRow BuildScoreconnectRowCore(ServiceController[] services, Process[] procs)
        {
            if ((services == null || services.Length == 0) && (procs == null || procs.Length == 0))
            {
                return new ServiceStatusRow
                {
                    Name = "Scoreconnect",
                    DisplayName = "Scoreconnect",
                    RowKind = "Windows service",
                    RestartUnavailableReason = "Scoreconnect service is not registered",
                    Status = "Not detected",
                    Detail = "Not installed on this VPU",
                    Severity = "Gray",
                };
            }

            var primaryService = services?.OrderBy(s => s.ServiceName, StringComparer.OrdinalIgnoreCase).FirstOrDefault();
            var serviceName = primaryService?.ServiceName ?? "";
            var displayName = !string.IsNullOrWhiteSpace(primaryService?.DisplayName)
                ? primaryService.DisplayName
                : "Scoreconnect";
            var rowName = !string.IsNullOrWhiteSpace(serviceName) ? serviceName : "Scoreconnect";
            var restartUnavailable = string.IsNullOrWhiteSpace(serviceName)
                ? "Scoreconnect process detected but no Windows service was registered"
                : "";

            var svcRunning = services?.Any(s => s.Status == ServiceControllerStatus.Running) ?? false;
            var procRunning = procs?.Length > 0;
            if (svcRunning || procRunning)
            {
                var detail = svcRunning && procRunning
                    ? $"Service running ({procs.Length} process(es))"
                    : (svcRunning ? "Service running, no process detected" : $"{procs.Length} process(es) running");
                return new ServiceStatusRow
                {
                    Name = rowName,
                    DisplayName = displayName,
                    RowKind = "Windows service",
                    ServiceName = serviceName,
                    StartMode = string.IsNullOrWhiteSpace(serviceName) ? "Process" : "Registered",
                    RestartUnavailableReason = restartUnavailable,
                    Status = "Running",
                    Detail = detail,
                    Severity = "Pass",
                };
            }
            return new ServiceStatusRow
            {
                Name = rowName,
                DisplayName = displayName,
                RowKind = "Windows service",
                ServiceName = serviceName,
                StartMode = string.IsNullOrWhiteSpace(serviceName) ? "Process" : "Registered",
                RestartUnavailableReason = restartUnavailable,
                Status = "Stopped",
                Detail = "Service registered, process not found",
                Severity = "Warn",
            };
        }

        private static bool SafeStartsWith(string s, string prefix)
        {
            return !string.IsNullOrEmpty(s) && s.StartsWith(prefix, StringComparison.OrdinalIgnoreCase);
        }
    }
}
