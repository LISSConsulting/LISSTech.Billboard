namespace LISSTech.Billboard.Models;

public sealed class InputDefinition
{
    public string Label { get; init; } = "Response";
    public string? Placeholder { get; init; }
    public string? DefaultValue { get; init; }
    public bool Required { get; init; }
    public bool Multiline { get; init; }
    public int MaxLength { get; init; } = 1024;
}
