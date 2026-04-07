using System.Collections.Generic;

namespace LISSTech.Billboard.Models;

public enum NotificationType
{
    Info,
    Warn,
    Alert,
    Critical,
    Question
}

public enum ThemeMode
{
    Auto,
    Light,
    Dark
}

public sealed class BillboardConfig
{
    public NotificationType Type { get; init; }
    public string Title { get; init; } = "";
    public string Message { get; init; } = "";
    public int? Timeout { get; init; }
    public bool Modal { get; init; }
    public ThemeMode Theme { get; init; } = ThemeMode.Auto;
    public string? PipeName { get; init; }
    public List<ButtonDefinition> Buttons { get; init; } = new();
    public string? Illustration { get; init; }
    public string? MspName { get; init; }
    public string? MspLogo { get; init; }

    public int EffectiveTimeout => Timeout ?? Type switch
    {
        NotificationType.Info => 10,
        NotificationType.Warn => 10,
        NotificationType.Alert => 15,
        NotificationType.Critical => 0,
        NotificationType.Question => 0,
        _ => 10
    };
}
