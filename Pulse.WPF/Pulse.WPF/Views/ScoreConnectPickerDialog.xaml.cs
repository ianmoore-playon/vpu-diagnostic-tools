using System.Collections.Generic;
using System.Linq;
using System.Windows;
using Pulse.WPF.Models;

namespace Pulse.WPF.Views
{
    /// <summary>
    /// Minimal modal picker dialog used by the Score Connect panel's
    /// Edit commands. Hosts a single ComboBox bound to a list of
    /// <see cref="ScoreConnectListItem"/> rows and exposes the chosen id /
    /// name via <see cref="SelectedId"/> / <see cref="SelectedName"/> when
    /// the user clicks OK.
    ///
    /// Kept deliberately simple — no MVVM ceremony, just two text knobs and
    /// a ComboBox. The two-stage confirm flow (this picker, then a
    /// MessageBox warning "this will reconfigure ScoreConnect III and may
    /// interrupt live data") lives on the calling VM.
    /// </summary>
    public partial class ScoreConnectPickerDialog : Window
    {
        public string SelectedId { get; private set; } = "";
        public string SelectedName { get; private set; } = "";

        public ScoreConnectPickerDialog(
            string title,
            string description,
            IEnumerable<ScoreConnectListItem> items,
            string currentSelectionId = null)
        {
            InitializeComponent();
            Title = title ?? "Choose";
            TitleText.Text = title ?? "Choose";
            DescriptionText.Text = description ?? "";

            var list = items?.ToList() ?? new List<ScoreConnectListItem>();
            ValueCombo.ItemsSource = list;

            if (!string.IsNullOrEmpty(currentSelectionId))
            {
                var match = list.FirstOrDefault(i =>
                    string.Equals(i.Id, currentSelectionId, System.StringComparison.OrdinalIgnoreCase));
                if (match != null) ValueCombo.SelectedItem = match;
            }
            if (ValueCombo.SelectedItem == null && list.Count > 0)
            {
                ValueCombo.SelectedIndex = 0;
            }
        }

        private void OkButton_Click(object sender, RoutedEventArgs e)
        {
            if (ValueCombo.SelectedItem is ScoreConnectListItem item)
            {
                SelectedId   = item.Id   ?? "";
                SelectedName = item.Name ?? "";
                DialogResult = true;
                return;
            }
            DialogResult = false;
        }

        private void CancelButton_Click(object sender, RoutedEventArgs e)
        {
            DialogResult = false;
        }
    }
}
