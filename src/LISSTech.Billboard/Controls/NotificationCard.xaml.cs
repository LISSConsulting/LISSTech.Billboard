using System;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Documents;
using System.Windows.Media;
using System.Windows.Input;
using System.Windows.Media.Imaging;
using LISSTech.Billboard.Models;
using LISSTech.Billboard.Services;

namespace LISSTech.Billboard.Controls;

public partial class NotificationCard : UserControl
{
    public static readonly DependencyProperty ConfigProperty =
        DependencyProperty.Register(nameof(Config), typeof(BillboardConfig), typeof(NotificationCard),
            new PropertyMetadata(null, OnConfigChanged));

    public static readonly DependencyProperty IsModalProperty =
        DependencyProperty.Register(nameof(IsModal), typeof(bool), typeof(NotificationCard),
            new PropertyMetadata(false));

    public static readonly DependencyProperty IsDarkThemeProperty =
        DependencyProperty.Register(nameof(IsDarkTheme), typeof(bool), typeof(NotificationCard),
            new PropertyMetadata(true, OnThemeChanged));

    public BillboardConfig? Config
    {
        get => (BillboardConfig?)GetValue(ConfigProperty);
        set => SetValue(ConfigProperty, value);
    }

    public bool IsModal
    {
        get => (bool)GetValue(IsModalProperty);
        set => SetValue(IsModalProperty, value);
    }

    public bool IsDarkTheme
    {
        get => (bool)GetValue(IsDarkThemeProperty);
        set => SetValue(IsDarkThemeProperty, value);
    }

    public event EventHandler<ButtonClickedEventArgs>? ButtonClicked;
    public event EventHandler? CloseClicked;

    public NotificationCard()
    {
        InitializeComponent();
    }

    private static void OnConfigChanged(DependencyObject d, DependencyPropertyChangedEventArgs e)
    {
        if (d is NotificationCard card && e.NewValue is BillboardConfig config)
            card.ApplyConfig(config);
    }

    private static void OnThemeChanged(DependencyObject d, DependencyPropertyChangedEventArgs e)
    {
        if (d is NotificationCard card && card.Config != null)
            card.ApplyConfig(card.Config);
    }

    private void ApplyConfig(BillboardConfig config)
    {
        var theme = IsDarkTheme ? "Dark" : "Light";
        var type = config.Type.ToString();

        // Apply type-based colors
        ApplyTypeColors(type, theme);

        // Set badge icon geometry
        SetBadgeIcon(config.Type);

        // Set badge icon stroke to match badge text color
        var badgeTextBrush = GetBadgeTextBrush(type, theme);
        BadgeIcon.Stroke = badgeTextBrush;

        // Set type label text
        TypeLabel.Text = config.Type switch
        {
            NotificationType.Info     => "INFORMATION",
            NotificationType.Warn     => "WARNING",
            NotificationType.Alert    => "ALERT",
            NotificationType.Critical => "CRITICAL",
            NotificationType.Question => "QUESTION",
            _                         => config.Type.ToString().ToUpperInvariant()
        };

        // Set title
        TitleBlock.Text = config.Title;
        TitleBlock.Foreground = FindBrush($"Text.Primary.{theme}");

        // Update title style for modal (larger font)
        TitleBlock.Style = (Style?)TryFindResource(IsModal ? "ModalTitle" : "ToastTitle");

        // Set message via markdown parser
        ApplyMessage(config.Message, theme);

        // Set illustration placeholder
        ApplyIllustration(config, theme);

        // MSP logo
        ApplyMspLogo(config.MspLogo);

        // Context footer
        ContextFooter.Text = GetDefaultBrand(config.Type, config.MspName);
        ContextFooter.Foreground = FindBrush($"Text.Body.{theme}");
        ContextFooter.Visibility = Visibility.Visible;

        // Generate buttons
        GenerateButtons(config, theme);

        // Close button: theme-aware style and icon stroke
        CloseButton.Style = (Style?)TryFindResource($"CloseButton.{theme}");
        var closePath = CloseButton.Content as System.Windows.Shapes.Path;
        if (closePath != null)
            closePath.Stroke = FindBrush($"Text.Body.{theme}");

        // MSP logo opacity — subtler in light theme
        MspLogoImage.Opacity = theme == "Dark" ? 0.5 : 0.35;

        // Show brand footer for modals without illustration panel (panel has its own footer)
        var showContentFooter = IsModal && IllustrationPanel.Visibility != Visibility.Visible;
        BrandFooter.Visibility = showContentFooter ? Visibility.Visible : Visibility.Collapsed;
        BrandFooter.Foreground = FindBrush($"Text.BrandWatermark.{theme}");
    }

    private void ApplyTypeColors(string type, string theme)
    {
        // Badge background
        Badge.Background = GetBadgeBrush(type, theme);

        // Header background
        var headerBrush = TryFindResource($"{type}.HeaderBg.{theme}") as SolidColorBrush;
        HeaderBorder.Background = headerBrush ?? Brushes.Transparent;

        // Card border
        var borderBrush = TryFindResource($"{type}.Border.{theme}") as SolidColorBrush;
        CardBorder.BorderBrush = borderBrush ?? Brushes.Transparent;

        // Type label foreground
        var labelBrush = TryFindResource($"{type}.Label.{theme}") as SolidColorBrush;
        TypeLabel.Foreground = labelBrush ?? Brushes.White;

        // Card background: type-tinted for all types, fallback to generic
        var cardBg = TryFindResource($"{type}.CardBg.{theme}") as SolidColorBrush;
        CardBorder.Background = cardBg ?? FindBrush($"Card.Background.{theme}");
    }

    // Badge backgrounds: Info has no theme suffix; all others do.
    private SolidColorBrush GetBadgeBrush(string type, string theme)
    {
        if (type == "Info")
            return FindBrush("Info.Badge");

        return TryFindResource($"{type}.Badge.{theme}") as SolidColorBrush ?? FindBrush("Info.Badge");
    }

    // Badge text/stroke color: Info has no theme suffix; all others do.
    private SolidColorBrush GetBadgeTextBrush(string type, string theme)
    {
        if (type == "Info")
            return FindBrush("Info.BadgeText");

        return TryFindResource($"{type}.BadgeText.{theme}") as SolidColorBrush ?? Brushes.White;
    }

    private void SetBadgeIcon(NotificationType type)
    {
        var geometryKey = type switch
        {
            NotificationType.Info     => "Icon.Info",
            NotificationType.Warn     => "Icon.TriangleAlert",
            NotificationType.Alert    => "Icon.BellRing",
            NotificationType.Critical => "Icon.OctagonX",
            NotificationType.Question => "Icon.CircleHelp",
            _                         => "Icon.Info"
        };

        if (TryFindResource(geometryKey) is Geometry geo)
            BadgeIcon.Data = geo;
    }

    private void ApplyIllustration(BillboardConfig config, string theme)
    {
        var name = config.Illustration ?? GetDefaultIllustration(config.Type);

        if (name is null)
        {
            IllustrationPanel.Visibility = Visibility.Collapsed;
            IllustrationImage.Visibility = Visibility.Collapsed;
            return;
        }

        try
        {
            // Try theme-specific illustration first (e.g., info-light.png), fall back to default
            var themeSuffix = theme == "Light" ? "-light" : "";
            BitmapImage bitmap;
            var themedUri = new Uri($"pack://application:,,,/Assets/Illustrations/{name}{themeSuffix}.png", UriKind.Absolute);
            var streamInfo = Application.GetResourceStream(themedUri);
            if (streamInfo != null)
            {
                streamInfo.Stream.Dispose();
                bitmap = new BitmapImage(themedUri);
            }
            else
            {
                bitmap = new BitmapImage(new Uri($"pack://application:,,,/Assets/Illustrations/{name}.png", UriKind.Absolute));
            }

            if (IsModal)
            {
                // Side panel for modals — background is baked into illustrations
                IllustrationPanel.Visibility = Visibility.Visible;
                IllustrationPanelImage.Source = bitmap;
                IllustrationImage.Visibility = Visibility.Collapsed;
                // Subtle header tint — slightly different shade from card body
                HeaderBorder.Background = new SolidColorBrush(
                    theme == "Dark" ? Color.FromArgb(0x18, 0xFF, 0xFF, 0xFF)
                                    : Color.FromArgb(0x0A, 0x00, 0x00, 0x00));
                // Brand footer goes under illustration, not in content area
                BrandFooter.Visibility = Visibility.Collapsed;
                PanelBrandText.Foreground = FindBrush($"Text.BrandWatermark.{theme}");
                PanelBrandText.Text = config.MspName?.ToUpperInvariant() ?? "LISS TECHNOLOGIES";
            }
            else
            {
                // Subtle overlay for toasts
                IllustrationPanel.Visibility = Visibility.Collapsed;
                IllustrationImage.Source = bitmap;
                IllustrationImage.Visibility = Visibility.Visible;
                IllustrationImage.Width = 180;
                IllustrationImage.Opacity = 0.10;
            }
        }
        catch (Exception ex)
        {
            System.Diagnostics.Debug.WriteLine($"Billboard: failed to load illustration: {ex.Message}");
            IllustrationPanel.Visibility = Visibility.Collapsed;
            IllustrationImage.Visibility = Visibility.Collapsed;
        }
    }

    private void ApplyMspLogo(string? logoPath)
    {
        var fallback = new BitmapImage(new Uri("pack://application:,,,/Assets/Brand/liss-logo.png", UriKind.Absolute));

        if (string.IsNullOrWhiteSpace(logoPath))
        {
            MspLogoImage.Source = fallback;
            return;
        }

        var syncResult = LogoService.LoadMspLogo(logoPath);
        if (syncResult != null)
        {
            MspLogoImage.Source = syncResult;
            return;
        }

        // For remote URLs without a cache hit, show fallback immediately
        // then download asynchronously and swap in when ready
        MspLogoImage.Source = fallback;

        if (Uri.TryCreate(logoPath, UriKind.Absolute, out var uri) &&
            (uri.Scheme == "http" || uri.Scheme == "https"))
        {
            LogoService.DownloadAndCacheAsync(uri, logoPath!, img =>
            {
                Dispatcher.BeginInvoke(new Action(() => MspLogoImage.Source = img));
            });
        }
    }

    private static string GetDefaultBrand(NotificationType type, string? brand)
    {
        var org = brand ?? "your organization";
        var helpdesk = brand != null ? $"{brand} support" : "your IT helpdesk";

        return type switch
        {
            NotificationType.Info     => $"This notification was delivered by {org}'s endpoint management system on behalf of your IT administrator. Please review the information above and follow any instructions provided. If you have questions or believe this notification was sent in error, contact {helpdesk} for assistance.",
            NotificationType.Warn     => $"This warning was generated by {org}'s system monitoring service after detecting a condition on your device that may require your attention. Please review the details above carefully and take the recommended action. Ignoring this warning may lead to further issues. If you need help or are unsure how to proceed, reach out to {helpdesk}.",
            NotificationType.Alert    => $"This alert was raised by {org}'s endpoint management platform because a time-sensitive condition has been detected on your device. Please review the information above and take action as soon as possible. Delaying your response may impact your system's performance or security. If you need assistance, contact {helpdesk} immediately.",
            NotificationType.Critical => $"This is a high-priority notification from {org}'s security and endpoint management system. The situation described above requires your immediate attention — please act on the instructions provided without delay. Failure to respond may result in restricted access to your device or organizational resources. If you are unable to resolve the issue yourself, contact {helpdesk} right away.",
            NotificationType.Question => $"This prompt was sent by {org}'s IT administrator because a decision is required before your system can proceed. Please review the options above and make your selection. Your choice may affect when updates are applied, when your device restarts, or how your system is configured. If you are unsure which option to choose, contact {helpdesk} for guidance before responding.",
            _                         => $"This notification was delivered by {org}'s endpoint management system. Please review the information above and follow any instructions provided. If you have questions, contact {helpdesk}."
        };
    }

    private static string? GetDefaultIllustration(NotificationType type)
    {
        return type switch
        {
            NotificationType.Info     => "info",
            NotificationType.Warn     => "warn",
            NotificationType.Alert    => "alert",
            NotificationType.Critical => "critical",
            NotificationType.Question => "question",
            _                         => null
        };
    }

    private void ApplyMessage(string message, string theme)
    {
        var doc = new FlowDocument
        {
            FontFamily  = new FontFamily("Cascadia Code, Aptos, Consolas, Segoe UI"),
            FontSize    = 14,
            LineHeight  = 22,
            Foreground  = FindBrush($"Text.Body.{theme}"),
            PagePadding = new Thickness(0),
            TextAlignment = TextAlignment.Left
        };

        foreach (var block in MarkdownParser.ParseBlocks(message))
            doc.Blocks.Add(block);

        MessageViewer.Document = doc;
    }

    private void GenerateButtons(BillboardConfig config, string theme)
    {
        ButtonPanel.Children.Clear();
        ButtonPanel.ColumnDefinitions.Clear();
        ButtonPanel.RowDefinitions.Clear();

        bool horizontal = IsModal && config.Buttons.Count <= 2
                          && IllustrationPanel.Visibility == Visibility.Visible;

        if (horizontal)
        {
            for (int i = 0; i < config.Buttons.Count; i++)
                ButtonPanel.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });

            for (int i = 0; i < config.Buttons.Count; i++)
            {
                var button = CreateStyledButton(config.Buttons[i], i, theme);
                button.Margin = new Thickness(i > 0 ? 10 : 0, 0, 0, 0);
                Grid.SetColumn(button, i);
                ButtonPanel.Children.Add(button);
            }
        }
        else
        {
            for (int i = 0; i < config.Buttons.Count; i++)
            {
                ButtonPanel.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
                var button = CreateStyledButton(config.Buttons[i], i, theme);
                button.Margin = new Thickness(0, i > 0 ? 10 : 0, 0, 0);
                Grid.SetRow(button, i);
                ButtonPanel.Children.Add(button);
            }
        }
    }

    private Button CreateStyledButton(ButtonDefinition btnDef, int index, string theme)
    {
        var button = new Button
        {
            Content = btnDef.Label.ToUpperInvariant(),
            Tag     = index
        };

        if (btnDef.Style == ButtonStyle.Primary && Config != null)
        {
            // Primary buttons use the type's accent color
            var type = Config.Type.ToString();
            var accent = TryFindResource($"{type}.Accent") as SolidColorBrush;
            var accentHover = TryFindResource($"{type}.AccentHover") as SolidColorBrush;
            var accentPressed = TryFindResource($"{type}.AccentPressed") as SolidColorBrush;
            var accentBorder = TryFindResource($"{type}.AccentBorder") as SolidColorBrush;

            if (accent != null)
                button.Style = CreateAccentButtonStyle(accent, accentHover ?? accent, accentPressed ?? accent, accentBorder ?? accent);
            else
                button.Style = (Style)FindResource("PrimaryButton");
        }
        else
        {
            var styleKey = btnDef.Style switch
            {
                ButtonStyle.Danger => $"DangerButton.{theme}",
                _                 => $"GhostButton.{theme}"
            };
            button.Style = (Style)FindResource(styleKey);
        }

        button.Click += OnButtonClick;
        return button;
    }

    private Style CreateAccentButtonStyle(SolidColorBrush bg, SolidColorBrush hover, SolidColorBrush pressed, SolidColorBrush border)
    {
        var style = new Style(typeof(Button));
        style.Setters.Add(new Setter(HorizontalAlignmentProperty, HorizontalAlignment.Stretch));
        style.Setters.Add(new Setter(CursorProperty, Cursors.Hand));

        var template = new ControlTemplate(typeof(Button));
        var borderFactory = new FrameworkElementFactory(typeof(Border));
        borderFactory.Name = "Root";
        borderFactory.SetValue(Border.BackgroundProperty, bg);
        borderFactory.SetValue(Border.BorderBrushProperty, border);
        borderFactory.SetValue(Border.BorderThicknessProperty, new Thickness(2));
        borderFactory.SetValue(Border.CornerRadiusProperty, new CornerRadius(6));
        borderFactory.SetValue(Border.PaddingProperty, new Thickness(32, 14, 32, 14));

        var contentFactory = new FrameworkElementFactory(typeof(ContentPresenter));
        contentFactory.SetValue(HorizontalAlignmentProperty, HorizontalAlignment.Center);
        contentFactory.SetValue(VerticalAlignmentProperty, VerticalAlignment.Center);

        // Text styling — set on the border so ContentPresenter inherits
        var font = TryFindResource("InterFont") as FontFamily ?? new FontFamily("Segoe UI");
        borderFactory.SetValue(TextElement.FontFamilyProperty, font);
        borderFactory.SetValue(TextElement.FontWeightProperty, FontWeights.Bold);
        borderFactory.SetValue(TextElement.FontSizeProperty, 15.0);
        // Use dark text on light accent colors for WCAG contrast (ITU-R BT.601 luminance)
        var bgColor = bg.Color;
        var luminance = 0.299 * bgColor.R + 0.587 * bgColor.G + 0.114 * bgColor.B;
        var textBrush = luminance > 128
            ? new SolidColorBrush(Color.FromRgb(0x1A, 0x1A, 0x1A))
            : Brushes.White;
        borderFactory.SetValue(TextElement.ForegroundProperty, (Brush)textBrush);

        borderFactory.AppendChild(contentFactory);
        template.VisualTree = borderFactory;

        // Hover trigger
        var hoverTrigger = new Trigger { Property = UIElement.IsMouseOverProperty, Value = true };
        hoverTrigger.Setters.Add(new Setter(Border.BackgroundProperty, hover, "Root"));
        template.Triggers.Add(hoverTrigger);

        // Pressed trigger
        var pressedTrigger = new Trigger { Property = System.Windows.Controls.Primitives.ButtonBase.IsPressedProperty, Value = true };
        pressedTrigger.Setters.Add(new Setter(Border.BackgroundProperty, pressed, "Root"));
        pressedTrigger.Setters.Add(new Setter(UIElement.OpacityProperty, 0.9, "Root"));
        template.Triggers.Add(pressedTrigger);

        style.Setters.Add(new Setter(Control.TemplateProperty, template));
        return style;
    }

    private void OnButtonClick(object sender, RoutedEventArgs e)
    {
        if (sender is Button btn && btn.Tag is int index && Config != null)
            ButtonClicked?.Invoke(this, new ButtonClickedEventArgs(Config.Buttons[index], index));
    }

    private void OnCloseClick(object sender, RoutedEventArgs e)
    {
        CloseClicked?.Invoke(this, EventArgs.Empty);
    }

    private SolidColorBrush FindBrush(string key)
    {
        return TryFindResource(key) is SolidColorBrush brush ? brush : Brushes.Transparent;
    }
}
