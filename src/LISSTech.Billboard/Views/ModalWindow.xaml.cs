using System;
using System.Windows;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Threading;
using LISSTech.Billboard.Controls;
using LISSTech.Billboard.Helpers;
using LISSTech.Billboard.Models;

namespace LISSTech.Billboard.Views;

public partial class ModalWindow : Window
{
    private readonly BillboardConfig _config;
    private readonly DispatcherTimer? _timer;
    private BillboardResult? _result;
    private bool _closing;

    public BillboardResult Result => _result ?? BillboardResult.FromDismiss();

    public ModalWindow(BillboardConfig config, bool isDarkTheme = true)
    {
        InitializeComponent();
        _config = config;

        // Set modal container background to match theme
        ModalContainer.Background = isDarkTheme
            ? (FindResource("Card.Background.Dark") as Brush ?? Brushes.Black)
            : (FindResource("Card.Background.Light") as Brush ?? Brushes.White);

        Card.Config = config;
        Card.IsDarkTheme = isDarkTheme;
        Card.IsModal = true;

        Card.ButtonClicked += (_, e) =>
        {
            _result = BillboardResult.FromButton(e.Button, e.Index);
            AnimateOut();
        };

        Card.CloseClicked += (_, _) =>
        {
            _result = BillboardResult.FromDismiss();
            AnimateOut();
        };

        if (config.EffectiveTimeout > 0)
        {
            _timer = new DispatcherTimer
            {
                Interval = TimeSpan.FromSeconds(config.EffectiveTimeout)
            };
            _timer.Tick += (_, _) =>
            {
                _timer.Stop();
                _result = BillboardResult.FromTimeout();
                AnimateOut();
            };
        }

        // Hide all content before the window is positioned
        Backdrop.Opacity = 0;
        ModalContainer.Opacity = 0;

        // Size to work area immediately (avoids resize flash)
        var work = ScreenHelper.GetPrimaryWorkArea();
        Left = work.Left;
        Top = work.Top;
        Width = work.Width;
        Height = work.Height;

        // Animate in once layout is done; start timeout after animation completes
        ContentRendered += (_, _) => AnimateIn();

        // Keyboard accessibility
        PreviewKeyDown += OnPreviewKeyDown;
    }

    private void OnPreviewKeyDown(object sender, KeyEventArgs e)
    {
        if (e.Key == Key.Escape)
        {
            _result = BillboardResult.FromDismiss();
            AnimateOut();
            e.Handled = true;
        }
        else if (e.Key == Key.Enter)
        {
            // Activate the primary button (Tag=0) if one exists
            foreach (var child in LogicalTreeHelper.GetChildren(Card.ButtonPanel))
            {
                if (child is System.Windows.Controls.Button btn && btn.Tag is int idx && idx == 0)
                {
                    btn.RaiseEvent(new RoutedEventArgs(System.Windows.Controls.Primitives.ButtonBase.ClickEvent));
                    e.Handled = true;
                    break;
                }
            }
        }
    }

    protected override void OnMouseDown(MouseButtonEventArgs e)
    {
        base.OnMouseDown(e);
        // Click on backdrop (outside modal card) dismisses
        var hit = e.OriginalSource as DependencyObject;
        if (hit != null && !IsDescendantOf(hit, ModalContainer))
        {
            _result = BillboardResult.FromDismiss();
            AnimateOut();
        }
    }

    private static bool IsDescendantOf(DependencyObject child, DependencyObject parent)
    {
        var current = child;
        while (current != null)
        {
            if (current == parent) return true;
            current = VisualTreeHelper.GetParent(current);
        }
        return false;
    }

    private void AnimateIn()
    {
        // Fade in backdrop (already at Opacity=0 from constructor)
        var backdropFade = new DoubleAnimation(0, 1, TimeSpan.FromMilliseconds(300));
        Backdrop.BeginAnimation(OpacityProperty, backdropFade);

        // Scale in card (already at Opacity=0 from constructor)
        var scaleTransform = new ScaleTransform(0.92, 0.92);
        ModalContainer.RenderTransform = scaleTransform;
        ModalContainer.RenderTransformOrigin = new Point(0.5, 0.5);

        var ease = new CubicEase { EasingMode = EasingMode.EaseOut };
        var duration = TimeSpan.FromMilliseconds(350);

        var scaleX = new DoubleAnimation(0.92, 1, duration) { EasingFunction = ease };
        var scaleY = new DoubleAnimation(0.92, 1, duration) { EasingFunction = ease };
        var cardFade = new DoubleAnimation(0, 1, TimeSpan.FromMilliseconds(300));

        scaleX.Completed += (_, _) => { if (!_closing) _timer?.Start(); };
        scaleTransform.BeginAnimation(ScaleTransform.ScaleXProperty, scaleX);
        scaleTransform.BeginAnimation(ScaleTransform.ScaleYProperty, scaleY);
        ModalContainer.BeginAnimation(OpacityProperty, cardFade);
    }

    private void AnimateOut()
    {
        _closing = true;
        _timer?.Stop();

        var fadeOut = new DoubleAnimation(1, 0, TimeSpan.FromMilliseconds(200));
        fadeOut.Completed += (_, _) => Close();
        BeginAnimation(OpacityProperty, fadeOut);
    }
}
