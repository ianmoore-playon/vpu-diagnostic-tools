using System.Collections;
using System.Collections.Specialized;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Animation;

namespace Pulse.WPF.Controls
{
    /// <summary>
    /// Reusable banner that lists every Warning / Critical finding on a panel.
    /// Bind <see cref="Findings"/> (preferred) or the legacy <see cref="ItemsSource"/>
    /// to the panel VM's collection. Auto-collapses when the collection is empty
    /// and slide-in animates from 0 -> 1 finding (per UX_REVIEW Section 5).
    /// </summary>
    public partial class FindingsBanner : UserControl
    {
        // ----- Findings (canonical binding) -----
        public static readonly DependencyProperty FindingsProperty =
            DependencyProperty.Register(
                nameof(Findings),
                typeof(IEnumerable),
                typeof(FindingsBanner),
                new PropertyMetadata(null, OnFindingsChanged));

        public IEnumerable Findings
        {
            get => (IEnumerable)GetValue(FindingsProperty);
            set => SetValue(FindingsProperty, value);
        }

        // ----- ItemsSource (legacy alias kept for existing markup) -----
        public static readonly DependencyProperty ItemsSourceProperty =
            DependencyProperty.Register(
                nameof(ItemsSource),
                typeof(IEnumerable),
                typeof(FindingsBanner),
                new PropertyMetadata(null, OnItemsSourceChanged));

        public IEnumerable ItemsSource
        {
            get => (IEnumerable)GetValue(ItemsSourceProperty);
            set => SetValue(ItemsSourceProperty, value);
        }

        // ----- DismissCommand -----
        public static readonly DependencyProperty DismissCommandProperty =
            DependencyProperty.Register(
                nameof(DismissCommand),
                typeof(ICommand),
                typeof(FindingsBanner),
                new PropertyMetadata(null));

        public ICommand DismissCommand
        {
            get => (ICommand)GetValue(DismissCommandProperty);
            set => SetValue(DismissCommandProperty, value);
        }

        public FindingsBanner()
        {
            InitializeComponent();
            // Start hidden — slide-in storyboard will reveal.
            Opacity = 0;
            UpdateVisibility();
        }

        private static void OnFindingsChanged(DependencyObject d, DependencyPropertyChangedEventArgs e)
        {
            var b = (FindingsBanner)d;
            // Mirror to ItemsSource so the XAML ItemsControl picks it up.
            b.ItemsSource = e.NewValue as IEnumerable;
            b.HookCollection(e.OldValue as IEnumerable, e.NewValue as IEnumerable);
            b.UpdateVisibility();
        }

        private static void OnItemsSourceChanged(DependencyObject d, DependencyPropertyChangedEventArgs e)
        {
            var b = (FindingsBanner)d;
            b.HookCollection(e.OldValue as IEnumerable, e.NewValue as IEnumerable);
            b.UpdateVisibility();
        }

        private INotifyCollectionChanged _hooked;

        private void HookCollection(IEnumerable oldVal, IEnumerable newVal)
        {
            if (_hooked != null)
            {
                _hooked.CollectionChanged -= OnCollectionChanged;
                _hooked = null;
            }
            if (newVal is INotifyCollectionChanged ncc)
            {
                _hooked = ncc;
                ncc.CollectionChanged += OnCollectionChanged;
            }
        }

        private void OnCollectionChanged(object sender, NotifyCollectionChangedEventArgs e)
        {
            UpdateVisibility();
        }

        private void UpdateVisibility()
        {
            int count = 0;
            if (Findings is ICollection c) count = c.Count;
            else if (ItemsSource is ICollection c2) count = c2.Count;
            else
            {
                var src = Findings ?? ItemsSource;
                if (src != null)
                    foreach (var _ in src) { count++; if (count > 0) break; }
            }

            if (count > 0)
            {
                if (Visibility != Visibility.Visible)
                {
                    Visibility = Visibility.Visible;
                    PlaySlideIn();
                }
                else if (Opacity < 0.99)
                {
                    PlaySlideIn();
                }
            }
            else
            {
                Visibility = Visibility.Collapsed;
                Opacity = 0;
            }
        }

        private void PlaySlideIn()
        {
            var transform = RenderTransform as TranslateTransform;
            if (transform == null)
            {
                transform = new TranslateTransform();
                RenderTransform = transform;
            }

            var sb = new Storyboard();

            var slide = new DoubleAnimation
            {
                From = -20, To = 0,
                Duration = new Duration(System.TimeSpan.FromMilliseconds(250)),
                EasingFunction = new CubicEase { EasingMode = EasingMode.EaseOut }
            };
            Storyboard.SetTarget(slide, this);
            Storyboard.SetTargetProperty(slide,
                new PropertyPath("RenderTransform.(TranslateTransform.Y)"));
            sb.Children.Add(slide);

            var fade = new DoubleAnimation
            {
                From = 0, To = 1,
                Duration = new Duration(System.TimeSpan.FromMilliseconds(250))
            };
            Storyboard.SetTarget(fade, this);
            Storyboard.SetTargetProperty(fade, new PropertyPath("Opacity"));
            sb.Children.Add(fade);

            sb.Begin();
        }
    }
}
