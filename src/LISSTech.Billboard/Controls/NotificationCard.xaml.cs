using System;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Documents;
using System.Windows.Media;
using System.Windows.Input;
using System.Windows.Media.Imaging;
using System.Windows.Media.Animation;
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

    public static readonly DependencyProperty ThemeProperty =
        DependencyProperty.Register(nameof(Theme), typeof(ThemeMode), typeof(NotificationCard),
            new PropertyMetadata(ThemeMode.Dark, OnThemeChanged));

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

    public ThemeMode Theme
    {
        get => (ThemeMode)GetValue(ThemeProperty);
        set => SetValue(ThemeProperty, value);
    }

    public string? InputText => Config?.Input == null ? null : InputBox.Text;

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
        var theme = Theme.ToString();
        var contrast = ThemeService.ContrastVariant(Theme);
        var type = config.Type.ToString();

        ApplyTypeColors(type, theme, contrast);
        SetBadgeIcon(config.Type);
        BadgeIcon.Stroke = GetBadgeTextBrush(type, contrast);

        TypeLabel.Text = config.Type switch
        {
            NotificationType.Info     => "INFORMATION",
            NotificationType.Warn     => "WARNING",
            NotificationType.Alert    => "ALERT",
            NotificationType.Critical => "CRITICAL",
            NotificationType.Question => "QUESTION",
            _                         => config.Type.ToString().ToUpperInvariant()
        };

        var contentDirection = TextDirectionService.GetFlowDirection(
            config.Title + "\n" + config.Message);
        TitleBlock.Text = config.Title;
        TitleBlock.Foreground = FindBrush($"Text.Primary.{theme}");
        TitleBlock.Style = (Style?)TryFindResource(IsModal ? "ModalTitle" : "ToastTitle");
        TitleBlock.FlowDirection = TextDirectionService.GetFlowDirection(config.Title);
        TitleBlock.Language = TextDirectionService.GetLanguage(config.Title);
        TitleBlock.TextAlignment = TitleBlock.FlowDirection == FlowDirection.RightToLeft
            ? TextAlignment.Right
            : TextAlignment.Left;

        ApplyMessage(config.Message, theme);
        ApplyInput(config.Input, theme);
        ApplyIllustration(config, theme, contrast);
        ApplyMspLogo(config.Branding?.Logo);

        ContextFooter.Text = GetDefaultBrand(config.Type, config.Branding?.Name, IsModal);
        ContextFooter.Foreground = FindBrush($"Text.Body.{theme}");
        ContextFooter.FlowDirection = FlowDirection.LeftToRight;
        ContextFooter.TextAlignment = TextAlignment.Left;
        ContextFooter.Visibility = Visibility.Visible;

        ButtonPanel.FlowDirection = contentDirection;
        GenerateButtons(config, theme);

        CloseButton.Style = (Style?)TryFindResource($"CloseButton.{contrast}");
        if (CloseButton.Content is System.Windows.Shapes.Path closePath)
            closePath.Stroke = FindBrush($"Text.Body.{theme}");

        MspLogoImage.Opacity = ThemeService.IsDark(Theme) ? 0.5 : 0.35;

        var showContentFooter = IsModal && IllustrationPanel.Visibility != Visibility.Visible;
        BrandFooter.Visibility = showContentFooter ? Visibility.Visible : Visibility.Collapsed;
        BrandFooter.Foreground = FindBrush($"Text.BrandWatermark.{theme}");
    }

    private void ApplyTypeColors(string type, string theme, string contrast)
    {
        Badge.Background = GetBadgeBrush(type, contrast);

        if (ThemeService.IsArtistic(Theme))
        {
            HeaderBorder.Background = TryFindResource($"Theme.HeaderBg.{theme}") as Brush ??
                Brushes.Transparent;
            CardBorder.BorderBrush = TryFindResource($"Theme.Border.{theme}") as Brush ??
                Brushes.Transparent;
            TypeLabel.Foreground = FindBrush($"Theme.Accent.{theme}");
            ApplyAnimatedBackground(theme);
            return;
        }

        HeaderBorder.Background = TryFindResource($"{type}.HeaderBg.{theme}") as Brush ??
            Brushes.Transparent;
        CardBorder.BorderBrush = TryFindResource($"{type}.Border.{theme}") as Brush ??
            Brushes.Transparent;
        TypeLabel.Foreground = TryFindResource($"{type}.Label.{theme}") as Brush ??
            Brushes.White;
        CardBorder.Background = TryFindResource($"{type}.CardBg.{theme}") as Brush ??
            TryFindResource($"Card.Background.{theme}") as Brush ??
            Brushes.Transparent;
    }

    private void ApplyAnimatedBackground(string theme)
    {
        if (TryFindResource($"Card.Background.{theme}") is not LinearGradientBrush source)
        {
            CardBorder.Background = TryFindResource($"Card.Background.{theme}") as Brush;
            return;
        }

        var brush = source.Clone();
        var transform = new RotateTransform(0, 0.5, 0.5);
        brush.RelativeTransform = transform;
        transform.BeginAnimation(
            RotateTransform.AngleProperty,
            new DoubleAnimation(-8, 8, TimeSpan.FromSeconds(12))
            {
                AutoReverse = true,
                RepeatBehavior = RepeatBehavior.Forever,
                EasingFunction = new SineEase { EasingMode = EasingMode.EaseInOut }
            });
        CardBorder.Background = brush;
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

    private void ApplyIllustration(BillboardConfig config, string theme, string contrast)
    {
        var source = config.Illustration ?? GetDefaultIllustration(config.Type);

        if (source is null)
        {
            HideIllustration();
            return;
        }
        if (source.Equals("none", StringComparison.OrdinalIgnoreCase))
        {
            HideIllustration();
            return;
        }

        try
        {
            var isRemote = Uri.TryCreate(source, UriKind.Absolute, out var remoteUri) &&
                (remoteUri.Scheme == Uri.UriSchemeHttp || remoteUri.Scheme == Uri.UriSchemeHttps);
            var isLocal = System.IO.Path.IsPathRooted(source) || System.IO.File.Exists(source);
            if (isRemote || isLocal)
            {
                var image = ImageService.LoadImage(source, IsModal ? 720 : 360);
                if (image != null)
                    ShowIllustration(config, image, theme, contrast);
                else
                    HideIllustration();

                if (isRemote)
                {
                    ImageService.DownloadAndCacheAsync(source, IsModal ? 720 : 360, loaded =>
                    {
                        if (ReferenceEquals(Config, config))
                            ShowIllustration(config, loaded, theme, contrast);
                    });
                }
                return;
            }

            var themeSuffix = contrast == "Light" ? "-light" : "";
            BitmapImage bitmap;
            var themedUri = new Uri(
                $"pack://application:,,,/LISSTech.Billboard;component/Assets/Illustrations/{source}{themeSuffix}.png",
                UriKind.Absolute);
            var streamInfo = Application.GetResourceStream(themedUri);
            if (streamInfo != null)
            {
                streamInfo.Stream.Dispose();
                bitmap = new BitmapImage(themedUri);
            }
            else
            {
                bitmap = new BitmapImage(new Uri(
                    $"pack://application:,,,/LISSTech.Billboard;component/Assets/Illustrations/{source}.png",
                    UriKind.Absolute));
            }
            ShowIllustration(config, bitmap, theme, contrast);
        }
        catch (Exception ex)
        {
            System.Diagnostics.Debug.WriteLine($"Billboard: failed to load illustration: {ex.Message}");
            HideIllustration();
        }
    }

    private void ShowIllustration(
        BillboardConfig config,
        BitmapSource bitmap,
        string theme,
        string contrast)
    {
        if (IsModal)
        {
            IllustrationPanel.Visibility = Visibility.Visible;
            IllustrationPanelImage.Source = bitmap;
            IllustrationImage.Visibility = Visibility.Collapsed;
            if (!ThemeService.IsArtistic(Theme))
            {
                HeaderBorder.Background = new SolidColorBrush(
                    contrast == "Dark"
                        ? Color.FromArgb(0x18, 0xFF, 0xFF, 0xFF)
                        : Color.FromArgb(0x0A, 0x00, 0x00, 0x00));
            }
            BrandFooter.Visibility = Visibility.Collapsed;
            PanelBrandText.Foreground = FindBrush($"Text.BrandWatermark.{theme}");
            PanelBrandText.Text = config.Branding?.Name?.ToUpperInvariant() ?? "LISS TECHNOLOGIES";
        }
        else
        {
            IllustrationPanel.Visibility = Visibility.Collapsed;
            IllustrationImage.Source = bitmap;
            IllustrationImage.Visibility = Visibility.Visible;
            IllustrationImage.Width = 180;
            IllustrationImage.Opacity = 0.10;
        }
    }

    private void HideIllustration()
    {
        IllustrationPanelImage.Source = null;
        IllustrationImage.Source = null;
        IllustrationPanel.Visibility = Visibility.Collapsed;
        IllustrationImage.Visibility = Visibility.Collapsed;
    }

    private void ApplyMspLogo(string? logoPath)
    {
        var fallback = new BitmapImage(new Uri(
            "pack://application:,,,/LISSTech.Billboard;component/Assets/Brand/liss-logo.png",
            UriKind.Absolute));

        if (string.IsNullOrWhiteSpace(logoPath))
        {
            MspLogoImage.Source = fallback;
            return;
        }

        var image = ImageService.LoadImage(logoPath, 96);
        if (image != null)
        {
            MspLogoImage.Source = image;
            return;
        }

        MspLogoImage.Source = fallback;
        ImageService.DownloadAndCacheAsync(
            logoPath!,
            96,
            loaded => MspLogoImage.Source = loaded);
    }

    private static string GetDefaultBrand(NotificationType type, string? brand, bool isModal)
    {
        var org = brand ?? "your organization";
        var helpdesk = brand != null ? $"{brand} support" : "your IT helpdesk";

        if (!isModal)
        {
            return type switch
            {
                NotificationType.Info     => $"Sent by {org}. Contact {helpdesk} with questions.",
                NotificationType.Warn     => $"Sent by {org}. Contact {helpdesk} if you need help.",
                NotificationType.Alert    => $"Sent by {org}. Contact {helpdesk} if you need assistance.",
                NotificationType.Critical => $"Sent by {org}. Contact {helpdesk} immediately if you need help.",
                NotificationType.Question => $"Sent by {org}. Contact {helpdesk} if you're unsure how to respond.",
                _                         => $"Sent by {org}. Contact {helpdesk} with questions."
            };
        }

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

    private void ApplyInput(InputDefinition? input, string theme)
    {
        if (input == null || !IsModal)
        {
            InputPanel.Visibility = Visibility.Collapsed;
            InputBox.Text = "";
            return;
        }

        InputPanel.Visibility = Visibility.Visible;
        InputLabel.Text = input.Required ? $"{input.Label} *" : input.Label;
        InputPlaceholder.Text = input.Placeholder ?? "";
        InputBox.MaxLength = input.MaxLength;
        InputBox.AcceptsReturn = input.Multiline;
        InputBox.MinHeight = input.Multiline ? 96 : 44;
        InputBox.MaxHeight = input.Multiline ? 180 : 44;
        InputBox.VerticalContentAlignment = input.Multiline
            ? VerticalAlignment.Top
            : VerticalAlignment.Center;
        InputBox.VerticalScrollBarVisibility = input.Multiline
            ? ScrollBarVisibility.Auto
            : ScrollBarVisibility.Hidden;
        InputBox.Text = input.DefaultValue ?? "";

        var direction = TextDirectionService.GetFlowDirection(
            input.DefaultValue ?? input.Placeholder ?? input.Label);
        var language = TextDirectionService.GetLanguage(
            input.DefaultValue ?? input.Placeholder ?? input.Label);
        InputLabel.FlowDirection = direction;
        InputLabel.Language = language;
        InputLabel.TextAlignment = direction == FlowDirection.RightToLeft
            ? TextAlignment.Right
            : TextAlignment.Left;
        InputBox.FlowDirection = direction;
        InputBox.Language = language;
        InputBox.TextAlignment = direction == FlowDirection.RightToLeft
            ? TextAlignment.Right
            : TextAlignment.Left;
        InputPlaceholder.FlowDirection = direction;
        InputPlaceholder.Language = language;
        InputPlaceholder.TextAlignment = InputBox.TextAlignment;

        InputLabel.Foreground = FindBrush($"Text.Primary.{theme}");
        InputBox.Foreground = FindBrush($"Text.Primary.{theme}");
        InputBox.CaretBrush = FindBrush($"Text.Primary.{theme}");
        InputPlaceholder.Foreground = FindBrush($"Text.Body.{theme}");
        InputBox.Background = TryFindResource($"Input.Background.{theme}") as Brush ??
            Brushes.Transparent;
        InputBox.BorderBrush = TryFindResource($"Theme.Border.{theme}") as Brush ??
            FindBrush($"Text.Body.{theme}");
        InputValidation.Visibility = Visibility.Collapsed;
        InputPlaceholder.Visibility = InputBox.Text.Length == 0
            ? Visibility.Visible
            : Visibility.Collapsed;
    }

    private void ApplyMessage(string message, string theme)
    {
        var direction = TextDirectionService.GetFlowDirection(message);
        var doc = new FlowDocument
        {
            FontFamily = new FontFamily("Cascadia Code, Aptos, Consolas, Segoe UI"),
            FontSize = 14,
            LineHeight = 22,
            Foreground = FindBrush($"Text.Body.{theme}"),
            PagePadding = new Thickness(0),
            FlowDirection = direction,
            Language = TextDirectionService.GetLanguage(message),
            TextAlignment = direction == FlowDirection.RightToLeft
                ? TextAlignment.Right
                : TextAlignment.Left
        };

        foreach (var block in MarkdownParser.ParseBlocks(message))
            doc.Blocks.Add(block);

        MessageViewer.FlowDirection = direction;
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
        var direction = TextDirectionService.GetFlowDirection(btnDef.Label);
        var button = new Button
        {
            Content = direction == FlowDirection.RightToLeft
                ? btnDef.Label
                : btnDef.Label.ToUpperInvariant(),
            Tag = index,
            FlowDirection = direction,
            Language = TextDirectionService.GetLanguage(btnDef.Label)
        };

        if (btnDef.Style == ButtonStyle.Primary && Config != null)
        {
            var prefix = ThemeService.IsArtistic(Theme)
                ? $"Theme.Accent.{theme}"
                : $"{Config.Type}.Accent";
            var hoverPrefix = ThemeService.IsArtistic(Theme)
                ? $"Theme.AccentHover.{theme}"
                : $"{Config.Type}.AccentHover";
            var pressedPrefix = ThemeService.IsArtistic(Theme)
                ? $"Theme.AccentPressed.{theme}"
                : $"{Config.Type}.AccentPressed";
            var borderPrefix = ThemeService.IsArtistic(Theme)
                ? $"Theme.Border.{theme}"
                : $"{Config.Type}.AccentBorder";
            var accent = TryFindResource(prefix) as SolidColorBrush;
            var accentHover = TryFindResource(hoverPrefix) as SolidColorBrush;
            var accentPressed = TryFindResource(pressedPrefix) as SolidColorBrush;
            var accentBorder = TryFindResource(borderPrefix) as SolidColorBrush;

            if (accent != null)
                button.Style = CreateAccentButtonStyle(
                    accent,
                    accentHover ?? accent,
                    accentPressed ?? accent,
                    accentBorder ?? accent);
            else
                button.Style = (Style)FindResource("PrimaryButton");
        }
        else
        {
            var contrast = ThemeService.ContrastVariant(Theme);
            var styleKey = btnDef.Style == ButtonStyle.Danger
                ? $"DangerButton.{contrast}"
                : $"GhostButton.{contrast}";
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
        if (sender is not Button button || button.Tag is not int index || Config == null)
            return;

        if (Config.Input?.Required == true && string.IsNullOrWhiteSpace(InputBox.Text))
        {
            InputValidation.Visibility = Visibility.Visible;
            InputBox.Focus();
            return;
        }

        ButtonClicked?.Invoke(this, new ButtonClickedEventArgs(Config.Buttons[index], index));
    }

    private void OnInputTextChanged(object sender, TextChangedEventArgs e)
    {
        if (InputPlaceholder == null)
            return;

        InputPlaceholder.Visibility = InputBox.Text.Length == 0
            ? Visibility.Visible
            : Visibility.Collapsed;
        if (!string.IsNullOrWhiteSpace(InputBox.Text))
            InputValidation.Visibility = Visibility.Collapsed;
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
