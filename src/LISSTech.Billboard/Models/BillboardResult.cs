using System;
using System.Text.Json.Serialization;

namespace LISSTech.Billboard.Models;

public sealed class BillboardResult
{
    [JsonPropertyName("button")]
    public string? Button { get; set; }

    [JsonPropertyName("value")]
    public string? Value { get; set; }

    [JsonPropertyName("index")]
    public int Index { get; set; } = -1;

    [JsonPropertyName("dismissed")]
    public bool Dismissed { get; set; }

    [JsonPropertyName("timeout")]
    public bool Timeout { get; set; }

    [JsonPropertyName("timestamp")]
    public DateTimeOffset Timestamp { get; set; } = DateTimeOffset.UtcNow;

    public static BillboardResult FromButton(ButtonDefinition button, int index) => new()
    {
        Button = button.Label,
        Value = button.Value,
        Index = index,
        Dismissed = false,
        Timeout = false
    };

    public static BillboardResult FromDismiss() => new()
    {
        Dismissed = true
    };

    public static BillboardResult FromTimeout() => new()
    {
        Dismissed = true,
        Timeout = true
    };
}
