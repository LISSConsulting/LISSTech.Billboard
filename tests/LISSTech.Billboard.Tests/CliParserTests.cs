using System;
using System.Collections.Generic;
using System.IO;
using LISSTech.Billboard.Models;
using LISSTech.Billboard.Services;
using Xunit;

namespace Billboard.Tests;

public class CliParserTests
{
    [Fact]
    public void ParseFlags_MinimalArgs_ReturnsConfig()
    {
        var config = CliParser.Parse(new[]
        {
            "--type", "Info",
            "--title", "Hello",
            "--message", "World"
        });

        Assert.Equal(NotificationType.Info, config.Type);
        Assert.Equal("Hello", config.Title);
        Assert.Equal("World", config.Message);
        Assert.Null(config.Timeout);
        Assert.False(config.Modal);
        Assert.Equal(ThemeMode.Auto, config.Theme);
        Assert.Null(config.PipeName);
        Assert.Empty(config.Buttons);
    }

    [Fact]
    public void ParseFlags_AllFlags_ReturnsConfig()
    {
        var config = CliParser.Parse(new[]
        {
            "--type", "Warn",
            "--title", "My Title",
            "--message", "My Message",
            "--timeout", "30",
            "--modal",
            "--theme", "Dark",
            "--pipe", "my-pipe",
            "--buttons", "OK:ok:Primary;Cancel:cancel:Ghost"
        });

        Assert.Equal(NotificationType.Warn, config.Type);
        Assert.Equal("My Title", config.Title);
        Assert.Equal("My Message", config.Message);
        Assert.Equal(30, config.Timeout);
        Assert.True(config.Modal);
        Assert.Equal(ThemeMode.Dark, config.Theme);
        Assert.Equal("my-pipe", config.PipeName);
        Assert.Equal(2, config.Buttons.Count);
        Assert.Equal("OK", config.Buttons[0].Label);
        Assert.Equal("ok", config.Buttons[0].Value);
        Assert.Equal(ButtonStyle.Primary, config.Buttons[0].Style);
        Assert.Equal("Cancel", config.Buttons[1].Label);
        Assert.Equal("cancel", config.Buttons[1].Value);
        Assert.Equal(ButtonStyle.Ghost, config.Buttons[1].Style);
    }

    [Fact]
    public void ParseFlags_CaseInsensitive()
    {
        var config = CliParser.Parse(new[]
        {
            "--type", "CRITICAL",
            "--title", "Alert",
            "--message", "Something critical",
            "--theme", "Light"
        });

        Assert.Equal(NotificationType.Critical, config.Type);
        Assert.Equal(ThemeMode.Light, config.Theme);
    }

    [Fact]
    public void ParseFlags_ButtonsWithoutStyle_DefaultsToGhost()
    {
        var config = CliParser.Parse(new[]
        {
            "--type", "Question",
            "--title", "Choose",
            "--message", "Pick one",
            "--buttons", "Yes:yes;No:no"
        });

        Assert.Equal(2, config.Buttons.Count);
        Assert.Equal(ButtonStyle.Ghost, config.Buttons[0].Style);
        Assert.Equal(ButtonStyle.Ghost, config.Buttons[1].Style);
    }

    [Fact]
    public void ParseFlags_MissingRequired_Throws()
    {
        var ex = Assert.Throws<ArgumentException>(() =>
            CliParser.Parse(new[]
            {
                "--type", "Alert",
                "--title", "My Title"
                // --message missing
            })
        );

        Assert.Contains("message", ex.Message, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public void ParseFlags_QuestionType_DefaultsToOkButton()
    {
        var config = CliParser.Parse(new[] { "--type", "Question", "--title", "T", "--message", "M" });
        Assert.Single(config.Buttons);
        Assert.Equal("OK", config.Buttons[0].Label);
        Assert.Equal("ok", config.Buttons[0].Value);
        Assert.Equal(ButtonStyle.Primary, config.Buttons[0].Style);
    }

    [Fact]
    public void ParseFlags_QuestionType_WithExplicitButtons_DoesNotAddDefault()
    {
        var config = CliParser.Parse(new[]
        {
            "--type", "Question",
            "--title", "T",
            "--message", "M",
            "--buttons", "Yes:yes:primary;No:no:ghost"
        });
        Assert.Equal(2, config.Buttons.Count);
        Assert.Equal("Yes", config.Buttons[0].Label);
        Assert.Equal("No", config.Buttons[1].Label);
    }

    [Fact]
    public void ParseFlags_IllustrationNone_SetsNullIllustration()
    {
        var config = CliParser.Parse(new[]
        {
            "--type", "Info",
            "--title", "T",
            "--message", "M",
            "--illustration", "none"
        });
        Assert.Null(config.Illustration);
    }

    [Fact]
    public void EffectiveTimeout_UsesPerTypeDefaults()
    {
        var info = CliParser.Parse(new[] { "--type", "Info", "--title", "T", "--message", "M" });
        var critical = CliParser.Parse(new[] { "--type", "Critical", "--title", "T", "--message", "M" });
        var alert = CliParser.Parse(new[] { "--type", "Alert", "--title", "T", "--message", "M" });

        Assert.Equal(10, info.EffectiveTimeout);
        Assert.Equal(0, critical.EffectiveTimeout);
        Assert.Equal(15, alert.EffectiveTimeout);
    }

    [Fact]
    public void EffectiveTimeout_ExplicitOverridesDefault()
    {
        var config = CliParser.Parse(new[]
        {
            "--type", "Critical",
            "--title", "T",
            "--message", "M",
            "--timeout", "60"
        });

        Assert.Equal(60, config.EffectiveTimeout);
    }

    // JSON stdin tests

    [Fact]
    public void ParseJson_PascalCase_ReturnsConfig()
    {
        var json = """{"Type":"Info","Title":"Hello","Message":"World"}""";
        var config = CliParser.Parse(new[] { "--json" }, new StringReader(json));

        Assert.Equal(NotificationType.Info, config.Type);
        Assert.Equal("Hello", config.Title);
        Assert.Equal("World", config.Message);
        Assert.Null(config.Timeout);
        Assert.False(config.Modal);
    }

    [Fact]
    public void ParseJson_CamelCase_ReturnsConfig()
    {
        var json = """{"type":"warn","title":"Warning","message":"Something went wrong"}""";
        var config = CliParser.Parse(new[] { "--json" }, new StringReader(json));

        Assert.Equal(NotificationType.Warn, config.Type);
        Assert.Equal("Warning", config.Title);
    }

    [Fact]
    public void ParseJson_AllOptionalFields_Parsed()
    {
        var json = """{"Type":"Alert","Title":"T","Message":"M","Timeout":30,"Modal":true,"Theme":"Dark","PipeName":"my-pipe","MspName":"Acme IT","MspLogo":"C:\\logo.png"}""";
        var config = CliParser.Parse(new[] { "--json" }, new StringReader(json));

        Assert.Equal(30, config.Timeout);
        Assert.True(config.Modal);
        Assert.Equal(ThemeMode.Dark, config.Theme);
        Assert.Equal("my-pipe", config.PipeName);
        Assert.Equal("Acme IT", config.Branding?.Name);
        Assert.Equal("C:\\logo.png", config.Branding?.Logo);
    }

    [Fact]
    public void ParseJson_WithButtons_ParsesButtonArray()
    {
        var json = """{"Type":"Question","Title":"T","Message":"M","Buttons":[{"Label":"Yes","Value":"yes","Style":"Primary"},{"Label":"No","Value":"no"}]}""";
        var config = CliParser.Parse(new[] { "--json" }, new StringReader(json));

        Assert.Equal(2, config.Buttons.Count);
        Assert.Equal("Yes", config.Buttons[0].Label);
        Assert.Equal("yes", config.Buttons[0].Value);
        Assert.Equal(ButtonStyle.Primary, config.Buttons[0].Style);
        Assert.Equal("No", config.Buttons[1].Label);
        Assert.Equal(ButtonStyle.Ghost, config.Buttons[1].Style);
    }

    [Fact]
    public void ParseJson_IllustrationNone_SetsNullIllustration()
    {
        var json = """{"Type":"Info","Title":"T","Message":"M","Illustration":"none"}""";
        var config = CliParser.Parse(new[] { "--json" }, new StringReader(json));

        Assert.Null(config.Illustration);
    }

    [Fact]
    public void ParseJson_MissingRequired_Throws()
    {
        var json = """{"Type":"Info","Title":"T"}""";
        Assert.Throws<ArgumentException>(() =>
            CliParser.Parse(new[] { "--json" }, new StringReader(json)));
    }

    [Fact]
    public void ParseJson_FlagsOverrideJsonValues()
    {
        var json = """{"Type":"Info","Title":"From JSON","Message":"JSON message"}""";
        var config = CliParser.Parse(new[] { "--json", "--title", "Flag Override" }, new StringReader(json));

        Assert.Equal("Flag Override", config.Title);
        Assert.Equal("JSON message", config.Message);
    }

    [Fact]
    public void ParseFlags_MspNameAndLogo_Parsed()
    {
        var config = CliParser.Parse(new[]
        {
            "--type", "Info",
            "--title", "T",
            "--message", "M",
            "--msp-name", "Acme IT",
            "--msp-logo", @"C:\logo.png"
        });

        Assert.Equal("Acme IT", config.Branding?.Name);
        Assert.Equal(@"C:\logo.png", config.Branding?.Logo);
    }

    [Fact]
    public void ParseFlags_IllustrationCustomName_Preserved()
    {
        var config = CliParser.Parse(new[]
        {
            "--type", "Info",
            "--title", "T",
            "--message", "M",
            "--illustration", "custom-banner"
        });

        Assert.Equal("custom-banner", config.Illustration);
    }

    [Fact]
    public void ParseFlags_NegativeTimeout_Throws()
    {
        var ex = Assert.Throws<ArgumentException>(() =>
            CliParser.Parse(new[]
            {
                "--type", "Info",
                "--title", "T",
                "--message", "M",
                "--timeout", "-1"
            })
        );
        Assert.Contains("timeout", ex.Message, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public void ParseJson_NegativeTimeout_Throws()
    {
        var json = """{"Type":"Info","Title":"T","Message":"M","Timeout":-1}""";
        var ex = Assert.Throws<ArgumentException>(() =>
            CliParser.Parse(new[] { "--json" }, new StringReader(json)));
        Assert.Contains("timeout", ex.Message, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public void ParseFlags_NonNumericTimeout_ThrowsArgumentException()
    {
        var ex = Assert.Throws<ArgumentException>(() =>
            CliParser.Parse(new[]
            {
                "--type", "Info",
                "--title", "T",
                "--message", "M",
                "--timeout", "abc"
            })
        );
        Assert.Contains("timeout", ex.Message, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public void ParseFlags_ButtonWithEmptyLabel_Throws()
    {
        var ex = Assert.Throws<ArgumentException>(() =>
            CliParser.Parse(new[]
            {
                "--type", "Info",
                "--title", "T",
                "--message", "M",
                "--buttons", ":ok:primary"
            })
        );
        Assert.Contains("label", ex.Message, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public void ParseFlags_ButtonWithEmptyValue_Throws()
    {
        var ex = Assert.Throws<ArgumentException>(() =>
            CliParser.Parse(new[]
            {
                "--type", "Info",
                "--title", "T",
                "--message", "M",
                "--buttons", "OK::primary"
            })
        );
        Assert.Contains("value", ex.Message, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public void ParseJson_ButtonWithEmptyLabel_Throws()
    {
        var json = """{"Type":"Info","Title":"T","Message":"M","Buttons":[{"Label":"","Value":"ok"}]}""";
        var ex = Assert.Throws<ArgumentException>(() =>
            CliParser.Parse(new[] { "--json" }, new StringReader(json)));
        Assert.Contains("label", ex.Message, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public void ParseJson_ButtonWithEmptyValue_Throws()
    {
        var json = """{"Type":"Info","Title":"T","Message":"M","Buttons":[{"Label":"OK","Value":""}]}""";
        var ex = Assert.Throws<ArgumentException>(() =>
            CliParser.Parse(new[] { "--json" }, new StringReader(json)));
        Assert.Contains("value", ex.Message, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public void ParseFlags_ButtonValueWithColons_ParsedCorrectly()
    {
        // Button values can contain colons (e.g. URLs); only split on first two colons
        var config = CliParser.Parse(new[]
        {
            "--type", "Info",
            "--title", "T",
            "--message", "M",
            "--buttons", "Open Site:https://example.com/path:primary;Dismiss:dismiss"
        });

        Assert.Equal(2, config.Buttons.Count);
        Assert.Equal("Open Site", config.Buttons[0].Label);
        Assert.Equal("https://example.com/path", config.Buttons[0].Value);
        Assert.Equal(ButtonStyle.Primary, config.Buttons[0].Style);
        Assert.Equal("Dismiss", config.Buttons[1].Label);
        Assert.Equal("dismiss", config.Buttons[1].Value);
    }

    [Fact]
    public void ParseFlags_ButtonLabelAndValueWithWhitespace_AreTrimmed()
    {
        var config = CliParser.Parse(new[]
        {
            "--type", "Info",
            "--title", "T",
            "--message", "M",
            "--buttons", "  OK  :  ok  :primary"
        });

        Assert.Single(config.Buttons);
        Assert.Equal("OK", config.Buttons[0].Label);
        Assert.Equal("ok", config.Buttons[0].Value);
    }

    [Fact]
    public void ParseJson_ButtonLabelAndValueWithWhitespace_AreTrimmed()
    {
        var json = """{"Type":"Info","Title":"T","Message":"M","Buttons":[{"Label":"  OK  ","Value":"  ok  "}]}""";
        var config = CliParser.Parse(new[] { "--json" }, new StringReader(json));

        Assert.Single(config.Buttons);
        Assert.Equal("OK", config.Buttons[0].Label);
        Assert.Equal("ok", config.Buttons[0].Value);
    }

    [Fact]
    public void ParseFlags_InvalidType_ThrowsWithHelpfulMessage()
    {
        var ex = Assert.Throws<ArgumentException>(() =>
            CliParser.Parse(new[] { "--type", "badtype", "--title", "T", "--message", "M" }));
        Assert.Contains("badtype", ex.Message, StringComparison.OrdinalIgnoreCase);
        Assert.Contains("info", ex.Message, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public void ParseFlags_InvalidTheme_ThrowsWithHelpfulMessage()
    {
        var ex = Assert.Throws<ArgumentException>(() =>
            CliParser.Parse(new[] { "--type", "Info", "--title", "T", "--message", "M", "--theme", "neon" }));
        Assert.Contains("neon", ex.Message, StringComparison.OrdinalIgnoreCase);
        Assert.Contains("light", ex.Message, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public void ParseJson_InvalidType_ThrowsWithHelpfulMessage()
    {
        var json = """{"Type":"badtype","Title":"T","Message":"M"}""";
        var ex = Assert.Throws<ArgumentException>(() =>
            CliParser.Parse(new[] { "--json" }, new StringReader(json)));
        Assert.Contains("badtype", ex.Message, StringComparison.OrdinalIgnoreCase);
        Assert.Contains("info", ex.Message, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public void ParseJson_InvalidButtonStyle_ThrowsWithHelpfulMessage()
    {
        var json = """{"Type":"Info","Title":"T","Message":"M","Buttons":[{"Label":"OK","Value":"ok","Style":"badstyle"}]}""";
        var ex = Assert.Throws<ArgumentException>(() =>
            CliParser.Parse(new[] { "--json" }, new StringReader(json)));
        Assert.Contains("badstyle", ex.Message, StringComparison.OrdinalIgnoreCase);
        Assert.Contains("ghost", ex.Message, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public void Parse_MspNameAndLogo_CreatesBrandingConfig()
    {
        var args = new[] { "--type", "info", "--title", "T", "--message", "M",
            "--msp-name", "LISS Consulting", "--msp-logo", "C:\\logo.png" };
        var config = CliParser.Parse(args);

        Assert.NotNull(config.Branding);
        Assert.Equal("LISS Consulting", config.Branding!.Name);
        Assert.Equal("C:\\logo.png", config.Branding.Logo);
    }

    [Fact]
    public void Parse_NoMspFlags_BrandingIsNull()
    {
        var args = new[] { "--type", "info", "--title", "T", "--message", "M" };
        var config = CliParser.Parse(args);

        Assert.Null(config.Branding);
    }
}
