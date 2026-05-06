using System;
using System.Collections.ObjectModel;
using System.Diagnostics;
using System.Threading.Tasks;
using System.Windows.Input;
using System.Windows.Media;
using Pulse.WPF.Helpers;
using Pulse.WPF.Models;
using Pulse.WPF.Services;

namespace Pulse.WPF.ViewModels
{
    /// <summary>
    /// Dashboard (home) panel VM. Owns the hub-tile list and the
    /// "Last Run: …" summary line. NavigateCommand fires off a navigation
    /// request — the MainViewModel is responsible for switching CurrentView.
    /// (Renamed from SystemOverviewViewModel — the hub is now "Dashboard"
    /// and a separate SystemOverviewViewModel hosts hardware specs.)
    /// </summary>
    public class DashboardViewModel : ObservableObject
    {
        private readonly IDashboardService _svc;

        public ObservableCollection<HubTileViewModel> Tiles { get; } = new ObservableCollection<HubTileViewModel>();

        private string _lastRunSummary = "Last Run: Never";
        public string LastRunSummary { get => _lastRunSummary; set => Set(ref _lastRunSummary, value); }
        private Brush _lastRunColor = StatusHelpers.Brush("MutedForegroundBrush");
        public Brush LastRunColor { get => _lastRunColor; set => Set(ref _lastRunColor, value); }

        // Tile click handler — XAML invokes via CommandParameter=TargetNav.
        public ICommand NavigateCommand { get; }
        // "Open Last Report" button.
        public ICommand OpenLastReportCommand { get; }

        public Action<string> RequestNavigate { get; set; }   // wired up by MainViewModel
        private string _lastReportPath;

        public DashboardViewModel(IDashboardService svc)
        {
            _svc = svc;
            // Tile click handler — RelayCommand takes no parameter, so use a
            // small ICommand wrapper that forwards the TargetNav string.
            NavigateCommand = new NavigateCommandImpl(target => RequestNavigate?.Invoke(target as string));
            OpenLastReportCommand = new RelayCommand(OpenLastReport);
        }

        public Task RefreshAsync()
        {
            return Task.Run(() =>
            {
                var tiles = _svc.GetHubTiles();
                var last = _svc.GetLastRunSummary();
                System.Windows.Application.Current?.Dispatcher.Invoke(() =>
                {
                    Tiles.Clear();
                    foreach (var t in tiles) Tiles.Add(t);

                    if (last == null)
                    {
                        LastRunSummary = "Last Run: Never";
                        LastRunColor = StatusHelpers.Brush("MutedForegroundBrush");
                        _lastReportPath = null;
                    }
                    else
                    {
                        var when = last.When.ToString("MMM d, h:mm tt");
                        var model = string.IsNullOrEmpty(last.VpuModel) ? "" : $" — {last.VpuModel}";
                        var res = string.IsNullOrEmpty(last.Result) ? "" : $"   |   {last.Result}";
                        LastRunSummary = $"Last Run: {when}{model}{res}";
                        LastRunColor =
                            last.Severity == "Fail" ? StatusHelpers.Brush("RedBrush") :
                            last.Severity == "Warn" ? StatusHelpers.Brush("YellowBrush") :
                            last.Severity == "Pass" ? StatusHelpers.Brush("GreenBrush") :
                                                       StatusHelpers.Brush("MutedForegroundBrush");
                        _lastReportPath = last.ReportPath;
                    }
                });
            });
        }

        private void OpenLastReport()
        {
            if (string.IsNullOrEmpty(_lastReportPath)) return;
            try { Process.Start("notepad.exe", _lastReportPath); }
            catch { }
        }

        // Internal ICommand that takes a parameter (the TargetNav string).
        private class NavigateCommandImpl : ICommand
        {
            private readonly Action<object> _execute;
            public NavigateCommandImpl(Action<object> execute) { _execute = execute; }
            public bool CanExecute(object parameter) => true;
            public void Execute(object parameter) => _execute(parameter);
            public event EventHandler CanExecuteChanged
            {
                add { System.Windows.Input.CommandManager.RequerySuggested += value; }
                remove { System.Windows.Input.CommandManager.RequerySuggested -= value; }
            }
        }
    }
}
