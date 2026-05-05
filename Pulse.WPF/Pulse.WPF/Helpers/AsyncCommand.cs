using System;
using System.Threading.Tasks;
using System.Windows.Input;

namespace Pulse.WPF.Helpers
{
    /// <summary>
    /// ICommand for synchronous actions. Equivalent to a Click handler.
    /// </summary>
    public class RelayCommand : ICommand
    {
        private readonly Action _execute;
        private readonly Func<bool> _canExecute;

        public RelayCommand(Action execute, Func<bool> canExecute = null)
        {
            _execute = execute ?? throw new ArgumentNullException(nameof(execute));
            _canExecute = canExecute;
        }

        public event EventHandler CanExecuteChanged
        {
            add    { CommandManager.RequerySuggested += value; }
            remove { CommandManager.RequerySuggested -= value; }
        }

        public bool CanExecute(object parameter) => _canExecute == null || _canExecute();
        public void Execute(object parameter)    => _execute();
    }

    /// <summary>
    /// Generic ICommand that takes one CommandParameter. Used by sidebar nav
    /// buttons (CommandParameter="Network", "Camera", etc.).
    /// </summary>
    public class RelayCommand<T> : ICommand
    {
        private readonly Action<T>     _execute;
        private readonly Predicate<T>  _canExecute;

        public RelayCommand(Action<T> execute, Predicate<T> canExecute = null)
        {
            _execute    = execute ?? throw new ArgumentNullException(nameof(execute));
            _canExecute = canExecute;
        }

        public event EventHandler CanExecuteChanged
        {
            add    { CommandManager.RequerySuggested += value; }
            remove { CommandManager.RequerySuggested -= value; }
        }

        public bool CanExecute(object parameter) => _canExecute == null || _canExecute(Cast(parameter));
        public void Execute(object parameter)    => _execute(Cast(parameter));

        private static T Cast(object parameter)
        {
            if (parameter is T t) return t;
            if (parameter == null) return default;
            // Fall back via Convert — handles "Network" (string) → T (string)
            try { return (T)Convert.ChangeType(parameter, typeof(T)); }
            catch { return default; }
        }
    }

    /// <summary>
    /// ICommand for async actions. Disables itself while running so a tech
    /// can't double-click "Run Test" and start two diagnostics. Mirrors the
    /// $btnRun.Enabled = $false dance in the WinForms version.
    /// </summary>
    public class AsyncCommand : ICommand
    {
        private readonly Func<Task> _execute;
        private readonly Func<bool> _canExecute;
        private bool _running;

        public AsyncCommand(Func<Task> execute, Func<bool> canExecute = null)
        {
            _execute = execute ?? throw new ArgumentNullException(nameof(execute));
            _canExecute = canExecute;
        }

        public event EventHandler CanExecuteChanged
        {
            add    { CommandManager.RequerySuggested += value; }
            remove { CommandManager.RequerySuggested -= value; }
        }

        public bool CanExecute(object parameter)
        {
            if (_running) return false;
            return _canExecute == null || _canExecute();
        }

        public async void Execute(object parameter)
        {
            if (_running) return;
            _running = true;
            CommandManager.InvalidateRequerySuggested();
            try { await _execute(); }
            finally
            {
                _running = false;
                CommandManager.InvalidateRequerySuggested();
            }
        }
    }
}
