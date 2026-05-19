using System;
using System.Windows;
using Pulse.WPF.ViewModels;

namespace Pulse.WPF.Views
{
    /// <summary>
    /// Modal Camera Fault Isolator wizard. Mirrors the legacy PowerShell
    /// 4-phase swap test, ported to the WPF host as its own dialog so the
    /// Camera Connectivity panel stays a passive monitor and the wizard
    /// can pause the 1Hz NIC poller for the duration of the run.
    ///
    /// Lifecycle:
    ///   1. Caller (CameraConnectivityViewModel) pauses the live monitor.
    ///   2. Caller seeds the VM from the live PortViewModel list and shows
    ///      this dialog with Owner = MainWindow.
    ///   3. VM raises <see cref="FaultIsolatorViewModel.RequestClose"/>
    ///      when the user clicks Cancel — handled here.
    ///   4. Caller resumes the monitor and (if Conclusion != None) fires
    ///      its SaveSnapshotCommand on the host VM.
    /// </summary>
    public partial class FaultIsolatorDialog : Window
    {
        public FaultIsolatorDialog(FaultIsolatorViewModel vm)
        {
            if (vm == null) throw new ArgumentNullException(nameof(vm));
            InitializeComponent();
            DataContext = vm;
            vm.RequestClose += OnRequestClose;
            Closed += (_, __) => vm.RequestClose -= OnRequestClose;
        }

        private void OnRequestClose()
        {
            try { Close(); } catch { /* dialog already gone */ }
        }
    }
}
