using System;

namespace LISSTech.Billboard.Models;

public enum ButtonStyle
{
    Ghost,
    Primary,
    Danger
}

public sealed class ButtonDefinition
{
    public string Label { get; init; } = "";
    public string Value { get; init; } = "";
    public ButtonStyle Style { get; init; } = ButtonStyle.Ghost;
    public TimeSpan? Defer { get; init; }
}
