using System.Collections.Generic;
using System.ComponentModel;
using System.Runtime.CompilerServices;

namespace Pulse.WPF.Helpers
{
    /// <summary>
    /// Minimal INotifyPropertyChanged base class. Lets ViewModels expose
    /// properties that XAML can bind to and have the UI auto-refresh
    /// whenever the value changes — no manual UI poking required.
    /// </summary>
    public abstract class ObservableObject : INotifyPropertyChanged
    {
        public event PropertyChangedEventHandler PropertyChanged;

        protected void OnPropertyChanged([CallerMemberName] string name = null)
        {
            PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));
        }

        /// <summary>
        /// Set a backing field, raise PropertyChanged only if the value
        /// actually changed. Returns true if the value was changed.
        /// </summary>
        protected bool Set<T>(ref T field, T value, [CallerMemberName] string name = null)
        {
            if (EqualityComparer<T>.Default.Equals(field, value)) return false;
            field = value;
            OnPropertyChanged(name);
            return true;
        }
    }
}
