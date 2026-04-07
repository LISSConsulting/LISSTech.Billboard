# Billboard DLL Refactor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Convert Billboard from a WinExe into a class library DLL + thin exe host, move to its own repo, and rewrite the PowerShell module to use builder cmdlets with direct DLL calls.

**Architecture:** The DLL (`LISSTech.Billboard.dll`) contains all WPF UI, models, and services. A static `BillboardService.Show()` API manages the WPF Application lifecycle internally. A thin exe host (`Billboard.exe`) wraps the DLL for ServiceUI/SYSTEM scenarios. The `.psm1` provides builder cmdlets (`New-BillboardButton`, `New-BillboardBranding`, `New-BillboardNotification`) and action cmdlets (`Show-Billboard`, `Request-Billboard`) that call the DLL directly or route through the exe for `-AsUser`.

**Tech Stack:** .NET Framework 4.7.2, WPF, PowerShell 5.1, xUnit, System.Text.Json 8.0.5

---

## File Map

### New project root: `~\Projects\LISSConsulting\@PowerShell\LISSTech.Billboard\`

**Project files (create):**
- `CLAUDE.md` — project instructions
- `.gitignore` — ignore obj/, Release/, .env, etc.
- `justfile` — build recipes (build, publish, test, clean)

**DLL project — `src/LISSTech.Billboard/` (move + modify):**
- `LISSTech.Billboard.csproj` — change OutputType from WinExe to Library, AssemblyName to LISSTech.Billboard
- `BillboardService.cs` — **new** static public API class
- `Models/BillboardConfig.cs` — modify: replace MspName/MspLogo with BrandingConfig, make PipeName internal
- `Models/BrandingConfig.cs` — **new** branding model
- `Models/ButtonDefinition.cs` — modify: add Defer property
- `Models/BillboardResult.cs` — modify: add Defer property, update FromButton
- `Models/ButtonClickedEventArgs.cs` — no changes (move only)
- `Services/CliParser.cs` — modify: parse defer= segment, map Branding
- `Services/PipeServer.cs` — no changes (move only)
- `Services/MarkdownParser.cs` — no changes (move only)
- `Services/LogoService.cs` — no changes (move only)
- `Helpers/ScreenHelper.cs` — no changes (move only)
- `Controls/NotificationCard.xaml` — no changes (move only)
- `Controls/NotificationCard.xaml.cs` — modify: read Branding instead of MspName/MspLogo
- `Views/ModalWindow.xaml` — no changes (move only)
- `Views/ModalWindow.xaml.cs` — no changes (move only)
- `Views/ToastWindow.xaml` — no changes (move only)
- `Views/ToastWindow.xaml.cs` — no changes (move only)
- `Themes/Colors.xaml` — no changes (move only)
- `Themes/Typography.xaml` — no changes (move only)
- `Themes/Buttons.xaml` — no changes (move only)
- `Assets/Icons.xaml` — no changes (move only)
- `Assets/Fonts/*.ttf` — no changes (move only)
- `Assets/Illustrations/*.png` — no changes (move only)
- `Assets/Brand/*.png` — no changes (move only)
- `Polyfills.cs` — modify: update InternalsVisibleTo for Host project

**Exe host — `src/LISSTech.Billboard.Host/` (create):**
- `LISSTech.Billboard.Host.csproj` — WinExe, references DLL project
- `Program.cs` — CLI args → BillboardService.Show() → pipe → exit code

**Tests — `tests/LISSTech.Billboard.Tests/` (move + modify):**
- `LISSTech.Billboard.Tests.csproj` — update ProjectReference path
- `CliParserTests.cs` — modify: add defer parsing tests
- `MarkdownParserTests.cs` — no changes (move only)
- `LogoServiceTests.cs` — no changes (move only)
- `PipeServerTests.cs` — no changes (move only)
- `BillboardServiceTests.cs` — **new** integration tests for Show()
- `DeferParsingTests.cs` — **new** defer TimeSpan parsing tests

**PowerShell module — root (create new):**
- `LISSTech.Billboard.psd1` — updated manifest with all 6 exported functions
- `LISSTech.Billboard.psm1` — complete rewrite: builder cmdlets, direct DLL calls, deferral helper

**Delete (from App.xaml entry point, replaced by BillboardService):**
- `App.xaml` — removed, resource loading moves to BillboardService
- `App.xaml.cs` — removed, lifecycle logic moves to BillboardService

---

## Task 1: Scaffold new project repository

**Files:**
- Create: `~\Projects\LISSConsulting\@PowerShell\LISSTech.Billboard\.gitignore`
- Create: `~\Projects\LISSConsulting\@PowerShell\LISSTech.Billboard\CLAUDE.md`

- [ ] **Step 1: Create directory and initialize git**

```bash
mkdir -p ~/Projects/LISSConsulting/@PowerShell/LISSTech.Billboard
cd ~/Projects/LISSConsulting/@PowerShell/LISSTech.Billboard
git init -b trunk
```

- [ ] **Step 2: Create .gitignore**

```gitignore
.vs/
**/src/**/bin/
**/tests/**/bin/
obj/
Release/
.env
.claude/
.superpowers/
*.pdb
node_modules/
```

- [ ] **Step 3: Create CLAUDE.md**

```markdown
# LISSTech.Billboard

WPF notification system for Windows endpoints, packaged as a PowerShell 5.1 module and .NET class library.

## Build

Requires: just, .NET SDK (targets .NET Framework 4.7.2).

\```bash
just              # list all recipes
just build        # build DLL + exe (Debug)
just publish      # build Release, assemble PS module in Release/
just test         # run xUnit tests
just clean        # remove Release/ and obj/
\```

## Project structure

- `src/LISSTech.Billboard/` — Class library (DLL): WPF UI, models, services, static BillboardService API
- `src/LISSTech.Billboard.Host/` — Thin console exe for ServiceUI/SYSTEM scenarios
- `tests/LISSTech.Billboard.Tests/` — xUnit tests
- `Release/LISSTech.Billboard/` — Build output: complete PS module package (gitignored)
- `LISSTech.Billboard.psd1` — PowerShell module manifest (source)
- `LISSTech.Billboard.psm1` — PowerShell module script (source)

## Code style

- C#: file-scoped namespaces, nullable enabled, latest language version
- 2-space indentation for XAML
- Conventional commits: `feat:`, `fix:`, `chore:`, etc.
- PascalCase for directory names, file names, public members

## Target

- .NET Framework 4.7.2 (pre-installed on Windows, no runtime to bundle)
- PowerShell 5.1
```

- [ ] **Step 4: Commit**

```bash
git add .gitignore CLAUDE.md
git commit -m "chore: scaffold project repository"
```

---

## Task 2: Move source files from StandardLibrary

**Files:**
- Move: all files from `LISSTech.StandardLibrary/Modules/LISSTech.Billboard/src/` → `LISSTech.Billboard/src/LISSTech.Billboard/`
- Move: all files from `LISSTech.StandardLibrary/Modules/LISSTech.Billboard/tests/` → `LISSTech.Billboard/tests/`
- Delete after move: `App.xaml`, `App.xaml.cs` (replaced by BillboardService in Task 4)

- [ ] **Step 1: Copy source tree**

```bash
SRC=~/Projects/LISSConsulting/@PowerShell/LISSTech.StandardLibrary/Modules/LISSTech.Billboard
DEST=~/Projects/LISSConsulting/@PowerShell/LISSTech.Billboard

cp -r "$SRC/src" "$DEST/src/LISSTech.Billboard"
cp -r "$SRC/tests" "$DEST/tests"
```

- [ ] **Step 2: Remove App.xaml entry point files**

These are replaced by `BillboardService.cs` in Task 4.

```bash
cd ~/Projects/LISSConsulting/@PowerShell/LISSTech.Billboard
rm src/LISSTech.Billboard/App.xaml
rm src/LISSTech.Billboard/App.xaml.cs
```

- [ ] **Step 3: Verify file structure**

```bash
find src/LISSTech.Billboard -name "*.cs" -o -name "*.xaml" -o -name "*.csproj" | sort
```

Expected output should include all source files under `src/LISSTech.Billboard/` without `App.xaml` or `App.xaml.cs`.

- [ ] **Step 4: Commit**

```bash
git add src/ tests/
git commit -m "chore: move Billboard source files from StandardLibrary"
```

---

## Task 3: Convert csproj from WinExe to Library

**Files:**
- Modify: `src/LISSTech.Billboard/LISSTech.Billboard.csproj`
- Modify: `src/LISSTech.Billboard/Polyfills.cs`
- Modify: `tests/LISSTech.Billboard.Tests/LISSTech.Billboard.Tests.csproj`

- [ ] **Step 1: Rewrite csproj as class library**

Replace `src/LISSTech.Billboard/LISSTech.Billboard.csproj` (currently named `Billboard.csproj`) with:

```xml
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <OutputType>Library</OutputType>
    <TargetFramework>net472</TargetFramework>
    <UseWPF>true</UseWPF>
    <AssemblyName>LISSTech.Billboard</AssemblyName>
    <RootNamespace>LISSTech.Billboard</RootNamespace>
    <LangVersion>latest</LangVersion>
    <Nullable>enable</Nullable>
  </PropertyGroup>
  <ItemGroup>
    <PackageReference Include="System.Text.Json" Version="8.0.5" />
  </ItemGroup>
  <ItemGroup>
    <Reference Include="System.Net.Http" />
  </ItemGroup>
  <ItemGroup>
    <Resource Include="Assets\Fonts\*.ttf" />
    <Resource Include="Assets\Illustrations\*.png" />
    <Resource Include="Assets\Brand\*.png" />
  </ItemGroup>
</Project>
```

Key changes: `OutputType` → `Library`, `AssemblyName` → `LISSTech.Billboard`, old `Billboard.csproj` renamed to `LISSTech.Billboard.csproj`.

- [ ] **Step 2: Update Polyfills.cs InternalsVisibleTo**

Replace `src/LISSTech.Billboard/Polyfills.cs`:

```csharp
// Polyfill for init-only setters on .NET Framework 4.7.2
[assembly: System.Runtime.CompilerServices.InternalsVisibleTo("LISSTech.Billboard.Tests")]
[assembly: System.Runtime.CompilerServices.InternalsVisibleTo("LISSTech.Billboard.Host")]

namespace System.Runtime.CompilerServices
{
    internal static class IsExternalInit { }
}
```

- [ ] **Step 3: Update test project reference**

Replace `tests/LISSTech.Billboard.Tests/LISSTech.Billboard.Tests.csproj`:

```xml
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFramework>net472</TargetFramework>
    <UseWPF>true</UseWPF>
    <IsPackable>false</IsPackable>
    <LangVersion>latest</LangVersion>
    <Nullable>enable</Nullable>
  </PropertyGroup>
  <ItemGroup>
    <PackageReference Include="Microsoft.NET.Test.Sdk" Version="17.*" />
    <PackageReference Include="xunit" Version="2.*" />
    <PackageReference Include="xunit.runner.visualstudio" Version="2.*" />
    <PackageReference Include="Xunit.StaFact" Version="1.*" />
  </ItemGroup>
  <ItemGroup>
    <ProjectReference Include="../../src/LISSTech.Billboard/LISSTech.Billboard.csproj" />
  </ItemGroup>
</Project>
```

- [ ] **Step 4: Verify build compiles**

```bash
cd ~/Projects/LISSConsulting/@PowerShell/LISSTech.Billboard
dotnet build src/LISSTech.Billboard/LISSTech.Billboard.csproj -nologo -v:q
```

Expected: Build succeeds (will have warnings about missing App.xaml StartupUri, which is fine since we deleted it).

- [ ] **Step 5: Verify tests compile and pass**

```bash
dotnet test tests/LISSTech.Billboard.Tests/LISSTech.Billboard.Tests.csproj --nologo -v:q
```

Expected: All existing tests pass.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "refactor: convert Billboard from WinExe to class library"
```

---

## Task 4: Add BrandingConfig and update models

**Files:**
- Create: `src/LISSTech.Billboard/Models/BrandingConfig.cs`
- Modify: `src/LISSTech.Billboard/Models/BillboardConfig.cs`
- Modify: `src/LISSTech.Billboard/Models/ButtonDefinition.cs`
- Modify: `src/LISSTech.Billboard/Models/BillboardResult.cs`
- Modify: `src/LISSTech.Billboard/Controls/NotificationCard.xaml.cs`
- Modify: `src/LISSTech.Billboard/Services/CliParser.cs`

- [ ] **Step 1: Create BrandingConfig**

Create `src/LISSTech.Billboard/Models/BrandingConfig.cs`:

```csharp
namespace LISSTech.Billboard.Models;

public sealed class BrandingConfig
{
    public string? Name { get; init; }
    public string? Logo { get; init; }
}
```

- [ ] **Step 2: Update BillboardConfig — replace MspName/MspLogo with Branding, make PipeName internal**

Replace `src/LISSTech.Billboard/Models/BillboardConfig.cs`:

```csharp
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
    public List<ButtonDefinition> Buttons { get; init; } = new();
    public string? Illustration { get; init; }
    public BrandingConfig? Branding { get; init; }

    // Used by exe host for pipe IPC — not part of public API
    internal string? PipeName { get; set; }

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
```

- [ ] **Step 3: Add Defer to ButtonDefinition**

Replace `src/LISSTech.Billboard/Models/ButtonDefinition.cs`:

```csharp
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
```

- [ ] **Step 4: Add Defer to BillboardResult, update FromButton**

Replace `src/LISSTech.Billboard/Models/BillboardResult.cs`:

```csharp
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

    [JsonPropertyName("defer")]
    public TimeSpan? Defer { get; set; }

    [JsonPropertyName("timestamp")]
    public DateTimeOffset Timestamp { get; set; } = DateTimeOffset.UtcNow;

    public static BillboardResult FromButton(ButtonDefinition button, int index) => new()
    {
        Button = button.Label,
        Value = button.Value,
        Index = index,
        Dismissed = false,
        Timeout = false,
        Defer = button.Defer
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
```

- [ ] **Step 5: Update NotificationCard.xaml.cs — read Branding instead of MspName/MspLogo**

In `src/LISSTech.Billboard/Controls/NotificationCard.xaml.cs`, update `ApplyConfig` method. Change line 105:

```csharp
// Old:
ApplyMspLogo(config.MspLogo);
// New:
ApplyMspLogo(config.Branding?.Logo);
```

Change line 108:

```csharp
// Old:
ContextFooter.Text = GetDefaultBrand(config.Type, config.MspName);
// New:
ContextFooter.Text = GetDefaultBrand(config.Type, config.Branding?.Name);
```

Change line 227 in `ApplyIllustration`:

```csharp
// Old:
PanelBrandText.Text = config.MspName?.ToUpperInvariant() ?? "LISS TECHNOLOGIES";
// New:
PanelBrandText.Text = config.Branding?.Name?.ToUpperInvariant() ?? "LISS TECHNOLOGIES";
```

- [ ] **Step 6: Update CliParser — map --msp-name/--msp-logo to BrandingConfig, add defer= parsing**

In `src/LISSTech.Billboard/Services/CliParser.cs`, the following changes are needed:

6a. Add a `ParseDefer` helper method after the `ParseEnum` method:

```csharp
private static TimeSpan ParseDefer(string value)
{
    if (string.IsNullOrWhiteSpace(value))
        throw new ArgumentException("Defer duration cannot be empty.");

    var span = value.Trim().ToLowerInvariant();
    if (span.EndsWith("m") && int.TryParse(span.Substring(0, span.Length - 1), out var minutes))
        return TimeSpan.FromMinutes(minutes);
    if (span.EndsWith("h") && int.TryParse(span.Substring(0, span.Length - 1), out var hours))
        return TimeSpan.FromHours(hours);
    if (span.EndsWith("d") && int.TryParse(span.Substring(0, span.Length - 1), out var days))
        return TimeSpan.FromDays(days);

    throw new ArgumentException($"Invalid defer duration '{value}'. Use format: 30m, 1h, 4h, 1d, 7d.");
}
```

6b. Replace the local variables `mspName` and `mspLogo` with a single `BrandingConfig? branding = null`. Wherever the parser sets `mspName` or `mspLogo` (from JSON or CLI flags), build the branding object instead:

```csharp
// After parsing all msp-name/msp-logo values:
BrandingConfig? branding = null;
if (mspName != null || mspLogo != null)
    branding = new BrandingConfig { Name = mspName, Logo = mspLogo };
```

And set `Branding = branding` on the returned `BillboardConfig` instead of `MspName = mspName, MspLogo = mspLogo`.

6c. In the CLI `--buttons` parsing loop (the `Split(';')` section), after determining `hasStyle` and extracting `value`, check for a `defer=` segment:

```csharp
// After existing style/value parsing:
TimeSpan? defer = null;
if (hasStyle && segments.Length > 3)
{
    var lastSeg = segments[segments.Length - 1].Trim();
    if (lastSeg.StartsWith("defer=", StringComparison.OrdinalIgnoreCase))
    {
        defer = ParseDefer(lastSeg.Substring(6));
        // Recalculate: style is now second-to-last
        // (segments already parsed style from the segment before defer=)
    }
}
// When defer= is the last segment, the parsing order is:
// label : value : style : defer=duration
// Since we already parsed style correctly from segments[segments.Length-1],
// we need to re-parse: check segments[segments.Length-1] for defer= FIRST,
// then check segments[segments.Length-2] for style.

// Revised logic:
var lastSegment = segments[segments.Length - 1].Trim();
TimeSpan? defer = null;
int styleIndex = segments.Length - 1;

if (lastSegment.StartsWith("defer=", StringComparison.OrdinalIgnoreCase))
{
    defer = ParseDefer(lastSegment.Substring(6));
    styleIndex = segments.Length - 2;
}

ButtonStyle parsedStyle = ButtonStyle.Ghost;
bool hasStyle = styleIndex > 1 &&
    Enum.TryParse<ButtonStyle>(segments[styleIndex].Trim(), ignoreCase: true, out parsedStyle);

int valueEnd = hasStyle ? styleIndex : (defer != null ? styleIndex + 1 : segments.Length);
var value = string.Join(":", segments, 1, valueEnd - 1).Trim();
var style = hasStyle ? parsedStyle : ButtonStyle.Ghost;
```

6d. Add `Defer = defer` to the `ButtonDefinition` construction in both the CLI and JSON parsing paths.

6e. In the JSON button parsing, add defer support:

```csharp
TimeSpan? defer = null;
if (btn.TryGetProperty("Defer", out var dp) || btn.TryGetProperty("defer", out dp))
{
    var deferStr = dp.GetString();
    if (!string.IsNullOrWhiteSpace(deferStr))
        defer = ParseDefer(deferStr);
}
buttons.Add(new ButtonDefinition { Label = label, Value = value, Style = style, Defer = defer });
```

- [ ] **Step 7: Verify build compiles**

```bash
dotnet build src/LISSTech.Billboard/LISSTech.Billboard.csproj -nologo -v:q
```

- [ ] **Step 8: Run tests — existing tests should still pass**

```bash
dotnet test tests/LISSTech.Billboard.Tests/LISSTech.Billboard.Tests.csproj --nologo -v:q
```

- [ ] **Step 9: Commit**

```bash
git add -A
git commit -m "feat: add BrandingConfig, Defer property, update models for DLL API"
```

---

## Task 5: Add defer and branding tests

**Files:**
- Create: `tests/LISSTech.Billboard.Tests/DeferParsingTests.cs`
- Modify: `tests/LISSTech.Billboard.Tests/CliParserTests.cs`

- [ ] **Step 1: Write defer parsing tests**

Create `tests/LISSTech.Billboard.Tests/DeferParsingTests.cs`:

```csharp
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
    public void CliButtons_ParsesDeferDuration(int expectedMinutes, int expectedHours, int expectedDays, string duration)
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
```

- [ ] **Step 2: Run tests to verify they pass**

```bash
dotnet test tests/LISSTech.Billboard.Tests/LISSTech.Billboard.Tests.csproj --nologo -v:q
```

Expected: All new and existing tests pass. If any fail, fix the CliParser implementation from Task 4 Step 6.

- [ ] **Step 3: Add branding test to CliParserTests**

Add to `tests/LISSTech.Billboard.Tests/CliParserTests.cs`:

```csharp
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
```

- [ ] **Step 4: Run all tests**

```bash
dotnet test tests/LISSTech.Billboard.Tests/LISSTech.Billboard.Tests.csproj --nologo -v:q
```

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "test: add defer parsing and branding tests"
```

---

## Task 6: Implement BillboardService — static API with WPF lifecycle

**Files:**
- Create: `src/LISSTech.Billboard/BillboardService.cs`

- [ ] **Step 1: Write BillboardService**

Create `src/LISSTech.Billboard/BillboardService.cs`:

```csharp
using System;
using System.Windows;
using System.Windows.Threading;
using LISSTech.Billboard.Models;
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
        EnsureApplication();

        BillboardResult? result = null;

        _app!.Dispatcher.Invoke(() =>
        {
            bool isDark = config.Theme switch
            {
                ThemeMode.Light => false,
                ThemeMode.Dark => true,
                _ => IsSystemDarkTheme()
            };

            Window window;
            if (config.Modal)
                window = new ModalWindow(config, isDark);
            else
                window = new ToastWindow(config, isDark);

            window.ShowDialog();

            if (window is ToastWindow toast)
                result = toast.Result;
            else if (window is ModalWindow modal)
                result = modal.Result;
        });

        return result ?? BillboardResult.FromDismiss();
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
```

- [ ] **Step 2: Update ModalWindow and ToastWindow to use ShowDialog instead of Show**

The windows currently use `window.Show()` (non-blocking) because the old `App.xaml.cs` managed the lifecycle. With `BillboardService`, we use `ShowDialog()` to block until the window closes. The `ToastWindow` and `ModalWindow` code-behind files do not need changes — `ShowDialog()` works with both.

However, `ToastWindow` positions itself off-screen initially (`Left = 10000`) and repositions on `ContentRendered`. This works with `ShowDialog()`. No changes needed.

Verify the build compiles:

```bash
dotnet build src/LISSTech.Billboard/LISSTech.Billboard.csproj -nologo -v:q
```

- [ ] **Step 3: Commit**

```bash
git add src/LISSTech.Billboard/BillboardService.cs
git commit -m "feat: add BillboardService static API with WPF lifecycle management"
```

---

## Task 7: Create exe host project

**Files:**
- Create: `src/LISSTech.Billboard.Host/LISSTech.Billboard.Host.csproj`
- Create: `src/LISSTech.Billboard.Host/Program.cs`

- [ ] **Step 1: Create host csproj**

Create `src/LISSTech.Billboard.Host/LISSTech.Billboard.Host.csproj`:

```xml
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <OutputType>WinExe</OutputType>
    <TargetFramework>net472</TargetFramework>
    <UseWPF>true</UseWPF>
    <AssemblyName>Billboard</AssemblyName>
    <RootNamespace>LISSTech.Billboard.Host</RootNamespace>
    <LangVersion>latest</LangVersion>
    <Nullable>enable</Nullable>
  </PropertyGroup>
  <ItemGroup>
    <ProjectReference Include="../LISSTech.Billboard/LISSTech.Billboard.csproj" />
  </ItemGroup>
</Project>
```

- [ ] **Step 2: Create Program.cs**

Create `src/LISSTech.Billboard.Host/Program.cs`:

```csharp
using System;
using System.Threading;
using System.Threading.Tasks;
using LISSTech.Billboard;
using LISSTech.Billboard.Models;
using LISSTech.Billboard.Services;

namespace LISSTech.Billboard.Host;

static class Program
{
    [STAThread]
    static int Main(string[] args)
    {
        if (CliParser.IsHelpRequested(args))
        {
            Console.WriteLine(CliParser.GetUsage());
            return 0;
        }

        BillboardConfig config;
        try
        {
            config = CliParser.Parse(args);
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine($"Billboard: {ex.Message}");
            Console.Error.WriteLine("Run 'Billboard.exe --help' for usage.");
            return 100;
        }

        BillboardResult result;
        try
        {
            result = BillboardService.Show(config);
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine($"Billboard window error: {ex}");
            return 100;
        }

        int exitCode = result.Timeout ? 2 : result.Dismissed ? 1 : 0;

        if (config.PipeName != null)
        {
            try
            {
                using var pipe = new PipeServer(config.PipeName);
                pipe.WaitForConnectionAndWriteAsync(result).GetAwaiter().GetResult();
            }
            catch (Exception ex)
            {
                Console.Error.WriteLine($"Billboard pipe error: {ex.Message}");
                exitCode = 100;
            }
        }

        return exitCode;
    }
}
```

- [ ] **Step 3: Build both projects**

```bash
dotnet build src/LISSTech.Billboard.Host/LISSTech.Billboard.Host.csproj -nologo -v:q
```

Expected: Build succeeds, produces `Billboard.exe` that references `LISSTech.Billboard.dll`.

- [ ] **Step 4: Smoke test the exe**

```bash
src/LISSTech.Billboard.Host/bin/Debug/net472/Billboard.exe --type info --title "Test" --message "Hello from exe host"
```

Expected: Toast appears, exits with code 2 (timeout).

- [ ] **Step 5: Commit**

```bash
git add src/LISSTech.Billboard.Host/
git commit -m "feat: add thin exe host for ServiceUI/SYSTEM scenarios"
```

---

## Task 8: Create justfile with build recipes

**Files:**
- Create: `justfile`

- [ ] **Step 1: Create justfile**

Create `justfile` at project root:

```just
set shell := ["pwsh", "-NoProfile", "-Command"]
set dotenv-load

release_dir := justfile_directory() / "Release/LISSTech.Billboard"

[private]
default:
    @just --list

# Build DLL + exe (Debug)
[script('pwsh', '-NoProfile')]
[extension('.ps1')]
build:
    $ErrorActionPreference = 'Stop'
    Write-Host 'Building LISSTech.Billboard...' -ForegroundColor Cyan
    & dotnet build 'src/LISSTech.Billboard/LISSTech.Billboard.csproj' -c Debug -nologo -v:q
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    & dotnet build 'src/LISSTech.Billboard.Host/LISSTech.Billboard.Host.csproj' -c Debug -nologo -v:q
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    Write-Host '  Build complete (Debug)' -ForegroundColor Green

# Build Release and assemble PS module in Release/
[script('pwsh', '-NoProfile')]
[extension('.ps1')]
publish:
    $ErrorActionPreference = 'Stop'
    $outDir = '{{ release_dir }}'
    $assemblyDir = Join-Path $outDir 'Assembly'
    $binDir = Join-Path $outDir 'Bin'

    # Clean
    if (Test-Path $outDir) { Remove-Item $outDir -Recurse -Force }
    New-Item -ItemType Directory -Path $assemblyDir -Force | Out-Null
    New-Item -ItemType Directory -Path $binDir -Force | Out-Null

    Write-Host 'Publishing LISSTech.Billboard...' -ForegroundColor Cyan

    # Build DLL
    & dotnet publish 'src/LISSTech.Billboard/LISSTech.Billboard.csproj' -c Release -o $assemblyDir -nologo -v:q
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

    # Build exe
    & dotnet publish 'src/LISSTech.Billboard.Host/LISSTech.Billboard.Host.csproj' -c Release -o $binDir -nologo -v:q
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

    # Clean up: exe's copy of the DLL and deps belong in Assembly/, not Bin/
    # Keep only Billboard.exe and Billboard.exe.config in Bin/
    Get-ChildItem $binDir -Exclude 'Billboard.exe', 'Billboard.exe.config' | Remove-Item -Force

    # Copy ServiceUI.exe to Bin/
    $serviceUI = '{{ justfile_directory() }}/vendor/ServiceUI.exe'
    if (Test-Path $serviceUI) {
        Copy-Item $serviceUI $binDir -Force
    } else {
        Write-Warning "ServiceUI.exe not found at $serviceUI — skipping"
    }

    # Copy PS module files
    Copy-Item 'LISSTech.Billboard.psd1' $outDir -Force
    Copy-Item 'LISSTech.Billboard.psm1' $outDir -Force

    $dllSize = '{0:N0} KB' -f ((Get-Item (Join-Path $assemblyDir 'LISSTech.Billboard.dll')).Length / 1KB)
    $exeSize = '{0:N0} KB' -f ((Get-Item (Join-Path $binDir 'Billboard.exe')).Length / 1KB)
    Write-Host "  LISSTech.Billboard.dll ($dllSize)" -ForegroundColor Green
    Write-Host "  Billboard.exe ($exeSize)" -ForegroundColor Green
    Write-Host "  Module assembled at: $outDir" -ForegroundColor Green

# Run xUnit tests
[script('pwsh', '-NoProfile')]
[extension('.ps1')]
test:
    $ErrorActionPreference = 'Stop'
    & dotnet test 'tests/LISSTech.Billboard.Tests/LISSTech.Billboard.Tests.csproj' --nologo -v:q
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

# Remove Release/ and obj/ directories
[script('pwsh', '-NoProfile')]
[extension('.ps1')]
clean:
    $ErrorActionPreference = 'Stop'
    @('Release', 'src/LISSTech.Billboard/obj', 'src/LISSTech.Billboard/bin',
      'src/LISSTech.Billboard.Host/obj', 'src/LISSTech.Billboard.Host/bin',
      'tests/LISSTech.Billboard.Tests/obj', 'tests/LISSTech.Billboard.Tests/bin'
    ) | ForEach-Object {
        if (Test-Path $_) {
            Remove-Item $_ -Recurse -Force
            Write-Host "  Removed $_" -ForegroundColor Yellow
        }
    }
```

- [ ] **Step 2: Create vendor directory for ServiceUI**

```bash
mkdir -p vendor
cp ~/Projects/LISSConsulting/@PowerShell/LISSTech.StandardLibrary/Bin/ServiceUI.exe vendor/
```

- [ ] **Step 3: Verify publish works**

```bash
just publish
```

Expected: `Release/LISSTech.Billboard/` contains Assembly/, Bin/, and the module files are not yet copied (psm1/psd1 don't exist yet — that's Task 9).

- [ ] **Step 4: Commit**

```bash
git add justfile vendor/ServiceUI.exe
git commit -m "chore: add justfile with build, publish, test, clean recipes"
```

---

## Task 9: Write PowerShell module — builder cmdlets and action cmdlets

**Files:**
- Create: `LISSTech.Billboard.psm1`
- Create: `LISSTech.Billboard.psd1`

- [ ] **Step 1: Write the module script**

Create `LISSTech.Billboard.psm1`:

```powershell
$script:AssemblyDir = Join-Path $PSScriptRoot 'Assembly'
$script:BinDir = Join-Path $PSScriptRoot 'Bin'
$script:BillboardDll = Join-Path $script:AssemblyDir 'LISSTech.Billboard.dll'
$script:BillboardExe = Join-Path $script:BinDir 'Billboard.exe'
$script:ServiceUIExe = Join-Path $script:BinDir 'ServiceUI.exe'

# Load the DLL assembly
Add-Type -Path $script:BillboardDll

# ── Builder Cmdlets ──────────────────────────────────────────────────────────

function New-BillboardButton {
    [CmdletBinding()]
    [OutputType([LISSTech.Billboard.Models.ButtonDefinition])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Label,

        [Parameter(Mandatory)]
        [string]$Value,

        [ValidateSet('Ghost', 'Primary', 'Danger')]
        [string]$Style = 'Ghost',

        [string]$Defer
    )

    $button = [LISSTech.Billboard.Models.ButtonDefinition]::new()
    $button.GetType().GetProperty('Label').SetValue($button, $Label)
    $button.GetType().GetProperty('Value').SetValue($button, $Value)
    $button.GetType().GetProperty('Style').SetValue($button, [LISSTech.Billboard.Models.ButtonStyle]::$Style)

    if ($PSBoundParameters.ContainsKey('Defer') -and $Defer) {
        $button.GetType().GetProperty('Defer').SetValue($button, (ConvertTo-DeferTimeSpan $Defer))
    }

    return $button
}

function New-BillboardBranding {
    [CmdletBinding()]
    [OutputType([LISSTech.Billboard.Models.BrandingConfig])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Name,

        [string]$Logo
    )

    $branding = [LISSTech.Billboard.Models.BrandingConfig]::new()
    $branding.GetType().GetProperty('Name').SetValue($branding, $Name)
    if ($PSBoundParameters.ContainsKey('Logo') -and $Logo) {
        $branding.GetType().GetProperty('Logo').SetValue($branding, $Logo)
    }

    return $branding
}

function New-BillboardNotification {
    [CmdletBinding()]
    [OutputType([LISSTech.Billboard.Models.BillboardConfig])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidateSet('Info', 'Warn', 'Alert', 'Critical', 'Question')]
        [string]$Type,

        [Parameter(Mandatory, Position = 1)]
        [string]$Title,

        [Parameter(Mandatory, Position = 2)]
        [string]$Message,

        [LISSTech.Billboard.Models.ButtonDefinition[]]$Buttons,

        [LISSTech.Billboard.Models.BrandingConfig]$Branding,

        [ValidateSet('Auto', 'Light', 'Dark')]
        [string]$Theme = 'Auto',

        [int]$Timeout,

        [switch]$Modal,

        [string]$Illustration
    )

    $buttonList = [System.Collections.Generic.List[LISSTech.Billboard.Models.ButtonDefinition]]::new()
    if ($Buttons) {
        foreach ($b in $Buttons) { $buttonList.Add($b) }
    }

    $config = [LISSTech.Billboard.Models.BillboardConfig]::new()
    $config.GetType().GetProperty('Type').SetValue($config, [LISSTech.Billboard.Models.NotificationType]::$Type)
    $config.GetType().GetProperty('Title').SetValue($config, $Title)
    $config.GetType().GetProperty('Message').SetValue($config, $Message)
    $config.GetType().GetProperty('Modal').SetValue($config, [bool]$Modal)
    $config.GetType().GetProperty('Theme').SetValue($config, [LISSTech.Billboard.Models.ThemeMode]::$Theme)
    $config.GetType().GetProperty('Buttons').SetValue($config, $buttonList)

    if ($PSBoundParameters.ContainsKey('Timeout')) {
        $config.GetType().GetProperty('Timeout').SetValue($config, [Nullable[int]]$Timeout)
    }

    if ($Branding) {
        $config.GetType().GetProperty('Branding').SetValue($config, $Branding)
    }

    if ($PSBoundParameters.ContainsKey('Illustration') -and $Illustration) {
        $illusValue = if ($Illustration -eq 'none') { $null } else { $Illustration }
        $config.GetType().GetProperty('Illustration').SetValue($config, $illusValue)
    }

    return $config
}

# ── Action Cmdlets ───────────────────────────────────────────────────────────

function Show-Billboard {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [LISSTech.Billboard.Models.BillboardConfig]$Notification,

        [switch]$AsUser,
        [switch]$PassThru
    )

    if ($AsUser -and (Test-IsSystem)) {
        $cliArgs = ConvertTo-CliArgs $Notification
        $exe, $cliArgs = Resolve-AsUserCommand $cliArgs

        $quotedArgs = $cliArgs | ForEach-Object { if ($_ -match ' ') { "`"$_`"" } else { $_ } }
        $startParams = @{ FilePath = $exe; ArgumentList = $quotedArgs; NoNewWindow = $true }

        if ($PassThru) {
            return Start-Process @startParams -PassThru
        }
        $null = Start-Process @startParams
        return
    }

    if ($PassThru) {
        Write-Warning '-PassThru is only supported with -AsUser. Showing notification synchronously.'
    }

    [LISSTech.Billboard.BillboardService]::Show($Notification)
}

function Request-Billboard {
    [CmdletBinding()]
    [OutputType([LISSTech.Billboard.Models.BillboardResult])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [LISSTech.Billboard.Models.BillboardConfig]$Notification,

        [switch]$AsUser
    )

    # Force modal for Request
    $Notification.GetType().GetProperty('Modal').SetValue($Notification, $true)

    if ($AsUser -and (Test-IsSystem)) {
        $pipeName = New-BillboardPipeName
        $Notification.GetType().GetProperty('PipeName').SetValue($Notification, $pipeName)

        $cliArgs = ConvertTo-CliArgs $Notification
        $exe, $cliArgs = Resolve-AsUserCommand $cliArgs

        $quotedArgs = $cliArgs | ForEach-Object { if ($_ -match ' ') { "`"$_`"" } else { $_ } }
        $process = Start-Process -FilePath $exe -ArgumentList $quotedArgs -NoNewWindow -PassThru

        try {
            return Read-BillboardPipe -PipeName $pipeName -TimeoutSeconds 300
        } catch {
            if (-not $process.HasExited) {
                $null = $process.WaitForExit(15000)
                if (-not $process.HasExited) { $process.Kill() }
            }
            $exitCode = $process.ExitCode
            if ($exitCode -eq 100) {
                throw "Billboard exited with error (exit code 100). Pipe read also failed: $_"
            }
            return [LISSTech.Billboard.Models.BillboardResult]::FromDismiss()
        }
    }

    return [LISSTech.Billboard.BillboardService]::Show($Notification)
}

# ── Deferral ─────────────────────────────────────────────────────────────────

function Register-BillboardDeferral {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ScriptPath,

        [Parameter(Mandatory)]
        [TimeSpan]$Delay,

        [string]$TaskNamePrefix = 'LISSTech.Billboard.Defer'
    )

    $taskName = "${TaskNamePrefix}.$([guid]::NewGuid().ToString('N').Substring(0, 8))"
    $triggerTime = (Get-Date).Add($Delay)

    $trigger = New-ScheduledTaskTrigger -Once -At $triggerTime
    $action = New-ScheduledTaskAction -Execute 'pwsh.exe' -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$ScriptPath`""
    $settings = New-ScheduledTaskSettingsSet -DeleteExpiredTaskAfter '00:05:00' -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
    $principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest

    Register-ScheduledTask -TaskName $taskName -Trigger $trigger -Action $action `
        -Settings $settings -Principal $principal -Force | Out-Null

    Write-Verbose "Deferral scheduled: $taskName at $($triggerTime.ToString('yyyy-MM-dd HH:mm:ss'))"
}

# ── Internal Helpers ─────────────────────────────────────────────────────────

function ConvertTo-DeferTimeSpan {
    [OutputType([TimeSpan])]
    param([Parameter(Mandatory)][string]$Duration)

    $d = $Duration.Trim().ToLower()
    if ($d -match '^(\d+)m$') { return [TimeSpan]::FromMinutes([int]$Matches[1]) }
    if ($d -match '^(\d+)h$') { return [TimeSpan]::FromHours([int]$Matches[1]) }
    if ($d -match '^(\d+)d$') { return [TimeSpan]::FromDays([int]$Matches[1]) }
    throw "Invalid defer duration '$Duration'. Use format: 30m, 1h, 4h, 1d, 7d."
}

function ConvertTo-CliArgs {
    [OutputType([string[]])]
    param([Parameter(Mandatory)][LISSTech.Billboard.Models.BillboardConfig]$Config)

    $args = [System.Collections.Generic.List[string]]::new()
    $args.Add('--type');    $args.Add($Config.Type.ToString().ToLower())
    $args.Add('--title');   $args.Add($Config.Title)
    $args.Add('--message'); $args.Add($Config.Message)

    if ($Config.Timeout) {
        $args.Add('--timeout'); $args.Add($Config.Timeout.ToString())
    }
    if ($Config.Modal) { $args.Add('--modal') }
    if ($Config.Theme -ne [LISSTech.Billboard.Models.ThemeMode]::Auto) {
        $args.Add('--theme'); $args.Add($Config.Theme.ToString().ToLower())
    }
    if ($Config.Branding) {
        if ($Config.Branding.Name) {
            $args.Add('--msp-name'); $args.Add($Config.Branding.Name)
        }
        if ($Config.Branding.Logo) {
            $args.Add('--msp-logo'); $args.Add($Config.Branding.Logo)
        }
    }
    if ($Config.Illustration) {
        $args.Add('--illustration'); $args.Add($Config.Illustration)
    }
    if ($Config.PipeName) {
        $args.Add('--pipe'); $args.Add($Config.PipeName)
    }
    if ($Config.Buttons.Count -gt 0) {
        $parts = foreach ($btn in $Config.Buttons) {
            $spec = "$($btn.Label):$($btn.Value):$($btn.Style.ToString().ToLower())"
            if ($btn.Defer) {
                $defer = if ($btn.Defer.TotalDays -ge 1) { "$([int]$btn.Defer.TotalDays)d" }
                    elseif ($btn.Defer.TotalHours -ge 1) { "$([int]$btn.Defer.TotalHours)h" }
                    else { "$([int]$btn.Defer.TotalMinutes)m" }
                $spec += ":defer=$defer"
            }
            $spec
        }
        $args.Add('--buttons'); $args.Add($parts -join ';')
    }

    return $args.ToArray()
}

function Test-IsSystem {
    [OutputType([bool])]
    param()
    $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    return $identity.User.Value -eq 'S-1-5-18'
}

function Resolve-AsUserCommand {
    [OutputType([object[]])]
    param([Parameter(Mandatory)][string[]]$BillboardArgs)

    if (-not (Test-IsSystem)) {
        Write-Warning '-AsUser specified but not running as SYSTEM. Launching Billboard directly.'
        return @($script:BillboardExe, $BillboardArgs)
    }

    if (-not (Test-Path $script:ServiceUIExe)) {
        throw [System.IO.FileNotFoundException]::new("ServiceUI.exe not found at '$script:ServiceUIExe'.")
    }

    $wrappedArgs = @('-process:explorer.exe', $script:BillboardExe) + $BillboardArgs
    return @($script:ServiceUIExe, $wrappedArgs)
}

function New-BillboardPipeName {
    [OutputType([string])]
    param()
    return "LISSTech.Billboard.$([guid]::NewGuid().ToString('N').Substring(0, 8))"
}

function Read-BillboardPipe {
    [OutputType([LISSTech.Billboard.Models.BillboardResult])]
    param(
        [Parameter(Mandatory)][string]$PipeName,
        [int]$TimeoutSeconds = 300
    )

    $pipe = $null
    $reader = $null
    try {
        $pipe = [System.IO.Pipes.NamedPipeClientStream]::new('.', $PipeName, [System.IO.Pipes.PipeDirection]::In)
        $pipe.Connect($TimeoutSeconds * 1000)
        $reader = [System.IO.StreamReader]::new($pipe, [System.Text.Encoding]::UTF8)
        $json = $reader.ReadToEnd()
        return $json | ConvertFrom-Json
    } finally {
        if ($reader) { $reader.Dispose() }
        if ($pipe)   { $pipe.Dispose() }
    }
}
```

- [ ] **Step 2: Write the module manifest**

Create `LISSTech.Billboard.psd1`:

```powershell
@{
    RootModule        = 'LISSTech.Billboard.psm1'
    ModuleVersion     = '1.0.0'
    GUID              = 'f3a7c2e1-8b4d-4f6a-9c5e-1d2b3a4f5e6c'
    Author            = 'Marcin Wisniowski <mwisniowski@lisstech.com>'
    CompanyName       = 'LISS Consulting, Corp.'
    Copyright         = '(c) LISS Consulting. All rights reserved.'
    Description       = 'LISSTech Billboard notification system for Windows endpoints.'
    PowerShellVersion = '5.1'
    RequiredAssemblies = @('Assembly\LISSTech.Billboard.dll')
    FunctionsToExport = @(
        'New-BillboardButton',
        'New-BillboardBranding',
        'New-BillboardNotification',
        'Show-Billboard',
        'Request-Billboard',
        'Register-BillboardDeferral'
    )
    CmdletsToExport   = @()
    VariablesToExport  = @()
    AliasesToExport    = @()
}
```

- [ ] **Step 3: Commit**

```bash
git add LISSTech.Billboard.psm1 LISSTech.Billboard.psd1
git commit -m "feat: add PowerShell module with builder cmdlets, action cmdlets, and deferral helper"
```

---

## Task 10: End-to-end smoke test

**Files:**
- No files modified — verification only

- [ ] **Step 1: Publish the module**

```bash
just publish
```

Expected: `Release/LISSTech.Billboard/` contains:
- `Assembly/LISSTech.Billboard.dll` + dependency DLLs
- `Bin/Billboard.exe`, `Billboard.exe.config`
- `LISSTech.Billboard.psd1`
- `LISSTech.Billboard.psm1`

- [ ] **Step 2: Test direct DLL path (user session)**

```powershell
Import-Module './Release/LISSTech.Billboard/LISSTech.Billboard.psd1' -Force

$branding = New-BillboardBranding 'LISS Consulting'

$buttons = @(
    New-BillboardButton 'Update Now' -Value update -Style Primary
    New-BillboardButton 'Remind in 1 Hour' -Value defer -Style Ghost -Defer 1h
)

$notification = New-BillboardNotification -Type Question `
    -Title 'Chrome Update' `
    -Message 'An update for **Google Chrome** is ready.' `
    -Buttons $buttons `
    -Branding $branding `
    -Timeout 0

$result = Request-Billboard $notification
$result | ConvertTo-Json
```

Expected: Modal appears, user clicks a button, result JSON shows correct button/value/defer.

- [ ] **Step 3: Test exe path**

```bash
Release/LISSTech.Billboard/Bin/Billboard.exe --type info --title "Test" --message "From exe host" --msp-name "LISS Consulting"
```

Expected: Toast appears, exits with code 2 (timeout).

- [ ] **Step 4: Test all 5 notification types**

```powershell
Import-Module './Release/LISSTech.Billboard/LISSTech.Billboard.psd1' -Force
$branding = New-BillboardBranding 'LISS Consulting'

foreach ($type in 'Info', 'Warn', 'Alert', 'Critical', 'Question') {
    $n = New-BillboardNotification -Type $type -Title "$type Test" -Message "Testing **$type** variant" `
        -Branding $branding -Timeout 3
    Show-Billboard $n
    Start-Sleep 1
}
Write-Host 'All variants shown.'
```

Expected: All 5 toast types display correctly with 3-second auto-dismiss.

- [ ] **Step 5: Test deferral button round-trip**

```powershell
$n = New-BillboardNotification -Type Question -Title 'Defer Test' -Message 'Pick a deferral' `
    -Buttons @(
        New-BillboardButton 'Now' -Value now -Style Primary
        New-BillboardButton '1 Hour' -Value defer -Style Ghost -Defer 1h
        New-BillboardButton 'Tomorrow' -Value defer -Style Ghost -Defer 1d
    ) -Timeout 0

$result = Request-Billboard $n
Write-Host "Value: $($result.Value)"
Write-Host "Defer: $($result.Defer)"
```

Expected: If user clicks "1 Hour", result shows `Value: defer`, `Defer: 01:00:00`. If "Tomorrow", `Defer: 1.00:00:00`.

---

## Task 11: Clean up StandardLibrary reference

**Files:**
- In `LISSTech.StandardLibrary`: remove `Modules/LISSTech.Billboard/` source files (keep reference to external Billboard Release output for WiX)

- [ ] **Step 1: Document the migration in StandardLibrary**

In the StandardLibrary repo, note that Billboard has moved to its own repository. The WiX installer should reference Billboard's `Release/` output externally. This is a manual step for the WiX project files — update component references to point to the new location.

- [ ] **Step 2: Commit in Billboard repo**

```bash
cd ~/Projects/LISSConsulting/@PowerShell/LISSTech.Billboard
git add -A
git commit -m "chore: final cleanup and verification"
```

---

Plan complete and saved to `docs/superpowers/plans/2026-04-07-billboard-dll-refactor.md`. Two execution options:

**1. Subagent-Driven (recommended)** - I dispatch a fresh subagent per task, review between tasks, fast iteration

**2. Inline Execution** - Execute tasks in this session using executing-plans, batch execution with checkpoints

Which approach?
