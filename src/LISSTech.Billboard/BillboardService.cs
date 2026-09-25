using System;
using System.Windows;
using System.Windows.Threading;
using LISSTech.Billboard.Models;
using LISSTech.Billboard.Services;
using LISSTech.Billboard.Views;

namespace LISSTech.Billboard;

public static class BillboardService
{
    private static Application? _app;
    private static readonly object _lock = new object();

    /// <summary>
    /// Show a Billboard notification. Blocks until the window is closed.
    /// Creates a WPF Application on first call; reuses it on subsequent calls.
    /// Must be called from an STA thread (PowerShell 5.1 is STA by default).
    /// </summary>
    public static BillboardResult Show(BillboardConfig config)
    {
        if (config == null)
            throw new ArgumentNullException(nameof(config));
        ValidateConfig(config);

        EnsureApplication();

        BillboardResult? result = null;

        _app!.Dispatcher.Invoke(() =>
        {
            var theme = ThemeService.Resolve(config.Theme, IsSystemDarkTheme());

            Window window;
            if (config.Modal)
                window = new ModalWindow(config, theme);
            else
                window = new ToastWindow(config, theme);

            window.ShowDialog();

            if (window is ToastWindow toast)
                result = toast.Result;
            else if (window is ModalWindow modal)
                result = modal.Result;
        });

        return result ?? BillboardResult.FromDismiss();
    }

    private static void ValidateConfig(BillboardConfig config)
    {
        if (config.Input == null)
            return;

        if (!config.Modal)
            throw new ArgumentException("Input is only supported on modal billboards.", nameof(config));
        if (string.IsNullOrWhiteSpace(config.Input.Label))
            throw new ArgumentException("Input label cannot be empty.", nameof(config));
        if (config.Input.MaxLength < 1 || config.Input.MaxLength > 10000)
            throw new ArgumentOutOfRangeException(
                nameof(config),
                "Input MaxLength must be between 1 and 10000.");
        if ((config.Input.DefaultValue?.Length ?? 0) > config.Input.MaxLength)
            throw new ArgumentException(
                "Input default value exceeds MaxLength.",
                nameof(config));
    }

    private static void EnsureApplication()
    {
        if (Application.Current != null)
        {
            _app = Application.Current;
            return;
        }

        lock (_lock)
        {
            if (Application.Current != null)
            {
                _app = Application.Current;
                return;
            }

            _app = new Application { ShutdownMode = ShutdownMode.OnExplicitShutdown };
            _app.Resources.MergedDictionaries.Add(LoadResourceDictionary("Themes/Colors.xaml"));
            _app.Resources.MergedDictionaries.Add(LoadResourceDictionary("Themes/Typography.xaml"));
            _app.Resources.MergedDictionaries.Add(LoadResourceDictionary("Themes/Buttons.xaml"));
            _app.Resources.MergedDictionaries.Add(LoadResourceDictionary("Assets/Icons.xaml"));
        }
    }

    private static ResourceDictionary LoadResourceDictionary(string relativePath)
    {
        return new ResourceDictionary
        {
            Source = new Uri($"pack://application:,,,/LISSTech.Billboard;component/{relativePath}", UriKind.Absolute)
        };
    }

    private static bool IsSystemDarkTheme()
    {
        try
        {
            using var key = Microsoft.Win32.Registry.CurrentUser.OpenSubKey(
                @"Software\Microsoft\Windows\CurrentVersion\Themes\Personalize");
            var value = key?.GetValue("AppsUseLightTheme");
            return value is int i && i == 0;
        }
        catch
        {
            return true;
        }
    }
}
