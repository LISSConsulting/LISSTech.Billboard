using System;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Threading;
using LISSTech.Billboard.Controls;
using LISSTech.Billboard.Helpers;
using LISSTech.Billboard.Models;

namespace LISSTech.Billboard.Views;

public partial class ToastWindow : Window
{
    private readonly BillboardConfig _config;
    private readonly DispatcherTimer? _timer;
    private BillboardResult? _result;
    private bool _closing;

    public BillboardResult Result => _result ?? BillboardResult.FromDismiss();

    public ToastWindow(BillboardConfig config, bool isDarkTheme = true)
    {
        InitializeComponent();
        _config = config;

        // Set outer border background to match theme
        CardBorder.Background = isDarkTheme
            ? (FindResource("Card.Background.Dark") as Brush ?? new SolidColorBrush(Color.FromArgb(0xEB, 0x1C, 0x1C, 0x26)))
            : (FindResource("Card.Background.Light") as Brush ?? new SolidColorBrush(Color.FromArgb(0xE0, 0xFF, 0xFF, 0xFF)));

        Card.Config = config;
        Card.IsDarkTheme = isDarkTheme;

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

        // Position off-screen initially, then slide in
        Left = 10000; // Off-screen
        ContentRendered += (_, _) =>
        {
            ScreenHelper.PositionBottomRight(this);
            AnimateIn();
        };

        // Prevent toast from stealing focus via WS_EX_NOACTIVATE
        SourceInitialized += (_, _) =>
        {
            var hwnd = new WindowInteropHelper(this).Handle;
            var exStyle = GetWindowLong(hwnd, GWL_EXSTYLE);
            SetWindowLong(hwnd, GWL_EXSTYLE, exStyle | WS_EX_NOACTIVATE);
        };

        // Keyboard accessibility
        PreviewKeyDown += OnPreviewKeyDown;
    }

    private const int GWL_EXSTYLE = -20;
    private const int WS_EX_NOACTIVATE = 0x08000000;

    [DllImport("user32.dll")]
    private static extern int GetWindowLong(IntPtr hwnd, int index);

    [DllImport("user32.dll")]
    private static extern int SetWindowLong(IntPtr hwnd, int index, int newStyle);

    private void OnPreviewKeyDown(object sender, System.Windows.Input.KeyEventArgs e)
    {
        if (e.Key == System.Windows.Input.Key.Escape)
        {
            _result = BillboardResult.FromDismiss();
            AnimateOut();
            e.Handled = true;
        }
    }

    private void AnimateIn()
    {
        var targetLeft = Left;
        Left = targetLeft + 120;
        Opacity = 0;

        var slideIn = new DoubleAnimation
        {
            To = targetLeft,
            Duration = TimeSpan.FromMilliseconds(400),
            EasingFunction = new CubicEase { EasingMode = EasingMode.EaseOut }
        };
        slideIn.Completed += (_, _) => { if (!_closing) _timer?.Start(); };
        var fadeIn = new DoubleAnimation(0, 1, TimeSpan.FromMilliseconds(300));

        BeginAnimation(LeftProperty, slideIn);
        BeginAnimation(OpacityProperty, fadeIn);
    }

    private void AnimateOut()
    {
        _closing = true;
        _timer?.Stop();

        var slideOut = new DoubleAnimation
        {
            To = Left + 120,
            Duration = TimeSpan.FromMilliseconds(300),
            EasingFunction = new CubicEase { EasingMode = EasingMode.EaseIn }
        };
        var fadeOut = new DoubleAnimation(1, 0, TimeSpan.FromMilliseconds(250));
        fadeOut.Completed += (_, _) => Close();

        BeginAnimation(LeftProperty, slideOut);
        BeginAnimation(OpacityProperty, fadeOut);
    }
}
