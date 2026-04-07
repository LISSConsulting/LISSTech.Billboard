using System;
using Xunit;
using LISSTech.Billboard.Models;
using LISSTech.Billboard.Services;

namespace LISSTech.Billboard.Tests;

public class DeferParsingTests
{
    [Theory]
    [InlineData("30m", 30, 0, 0)]
    [InlineData("1h", 0, 1, 0)]
    [InlineData("4h", 0, 4, 0)]
    [InlineData("1d", 0, 0, 1)]
    [InlineData("7d", 0, 0, 7)]
    public void CliButtons_ParsesDeferDuration(string duration, int expectedMinutes, int expectedHours, int expectedDays)
    {
        var args = new[] { "--type", "question", "--title", "T", "--message", "M",
            "--buttons", $"Later:defer:ghost:defer={duration}" };
        var config = CliParser.Parse(args);

        Assert.Single(config.Buttons);
        Assert.NotNull(config.Buttons[0].Defer);

        var expected = new TimeSpan(expectedDays, expectedHours, expectedMinutes, 0);
        Assert.Equal(expected, config.Buttons[0].Defer);
    }

    [Fact]
    public void CliButtons_NoDeferSegment_DeferIsNull()
    {
        var args = new[] { "--type", "question", "--title", "T", "--message", "M",
            "--buttons", "OK:ok:primary" };
        var config = CliParser.Parse(args);

        Assert.Single(config.Buttons);
        Assert.Null(config.Buttons[0].Defer);
    }

    [Fact]
    public void CliButtons_DeferWithMultiWordLabel()
    {
        var args = new[] { "--type", "question", "--title", "T", "--message", "M",
            "--buttons", "Remind Me Later:defer:ghost:defer=1h" };
        var config = CliParser.Parse(args);

        Assert.Equal("Remind Me Later", config.Buttons[0].Label);
        Assert.Equal("defer", config.Buttons[0].Value);
        Assert.Equal(ButtonStyle.Ghost, config.Buttons[0].Style);
        Assert.Equal(TimeSpan.FromHours(1), config.Buttons[0].Defer);
    }

    [Fact]
    public void JsonButtons_ParsesDefer()
    {
        var json = @"{
            ""type"": ""question"", ""title"": ""T"", ""message"": ""M"",
            ""buttons"": [{ ""label"": ""Later"", ""value"": ""defer"", ""style"": ""ghost"", ""defer"": ""4h"" }]
        }";
        var config = CliParser.Parse(new[] { "--json" }, new System.IO.StringReader(json));

        Assert.Single(config.Buttons);
        Assert.Equal(TimeSpan.FromHours(4), config.Buttons[0].Defer);
    }

    [Fact]
    public void BillboardResult_FromButton_CopiesDefer()
    {
        var button = new ButtonDefinition { Label = "Later", Value = "defer", Defer = TimeSpan.FromHours(2) };
        var result = BillboardResult.FromButton(button, 0);

        Assert.Equal(TimeSpan.FromHours(2), result.Defer);
    }

    [Fact]
    public void BillboardResult_FromDismiss_DeferIsNull()
    {
        var result = BillboardResult.FromDismiss();
        Assert.Null(result.Defer);
    }
}
