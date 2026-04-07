# Billboard DLL Refactor Design

**Date:** 2026-04-07
**Status:** Draft
**Supersedes:** 2026-04-04-billboard-powershell-module-design.md (partially — the .psm1 approach changes)

## Goal

Convert Billboard from a standalone WPF executable into a .NET class library (DLL) that serves as both a reusable .NET assembly and the engine behind a PowerShell 5.1 module. Retain a thin executable host for SYSTEM-context scenarios where ServiceUI must launch a process in the user's desktop session.

Move the project out of `LISSTech.StandardLibrary` into its own repository at `~\Projects\LISSConsulting\@PowerShell\LISSTech.Billboard\`.

## Constraints

- .NET Framework 4.7.2 (pre-installed on Windows, no runtime to bundle)
- PowerShell 5.1 (ships with Windows)
- Must support SYSTEM → user-session notification via ServiceUI
- Must support multiple calls per PowerShell process (reusable WPF Application)

## Architecture

### Project Structure

```
LISSTech.Billboard\
├── src\
│   └── LISSTech.Billboard\
│       ├── LISSTech.Billboard.csproj       ← Library (DLL)
│       ├── BillboardService.cs             ← Static public API
│       ├── Models\
│       ├── Services\
│       ├── Views\
│       ├── Controls\
│       ├── Themes\
│       ├── Helpers\
│       └── Assets\
│   └── LISSTech.Billboard.Host\
│       ├── LISSTech.Billboard.Host.csproj  ← WinExe (thin exe)
│       └── Program.cs
├── tests\
│   └── LISSTech.Billboard.Tests\
├── Release\                                 ← Complete PS module package
│   └── LISSTech.Billboard\
│       ├── LISSTech.Billboard.psd1
│       ├── LISSTech.Billboard.psm1
│       ├── Assembly\
│       │   ├── LISSTech.Billboard.dll
│       │   └── (dependency DLLs)
│       └── Bin\
│           ├── Billboard.exe
│           └── ServiceUI.exe
├── LISSTech.Billboard.psd1                  ← Source manifests
├── LISSTech.Billboard.psm1
├── justfile
├── CLAUDE.md
└── .gitignore
```

### Artifacts

| Artifact | Type | Purpose |
|----------|------|---------|
| `LISSTech.Billboard.dll` | Class library | WPF UI engine, public API, all models and services |
| `Billboard.exe` | Console WinExe | Thin CLI host for ServiceUI. Parses args, calls DLL, writes pipe, exits |
| `LISSTech.Billboard.psm1` | Script module | Builder cmdlets, user-vs-SYSTEM routing, deferral helper |
| `LISSTech.Billboard.psd1` | Module manifest | PowerShell module metadata |

## Public C# API

### BillboardService

```csharp
namespace LISSTech.Billboard;

public static class BillboardService
{
    /// <summary>
    /// Show a Billboard notification. Blocks until the window is closed.
    /// Creates a WPF Application on first call; reuses it on subsequent calls.
    /// Must be called from an STA thread (PowerShell 5.1 is STA by default).
    /// </summary>
    public static BillboardResult Show(BillboardConfig config);
}
```

Single method. `config.Modal` determines toast vs. modal. Manages the WPF Application singleton and Dispatcher internally.

### WPF Application Lifecycle

1. On first call, check `Application.Current`
2. If null, create a new `Application` and load resource dictionaries (Colors, Typography, Buttons, Icons)
3. Create `ModalWindow` or `ToastWindow` based on `config.Modal`
4. Run the Dispatcher until the window closes
5. Return `BillboardResult`
6. On subsequent calls, the Application already exists — just create a new window

### Models

#### BillboardConfig

```csharp
namespace LISSTech.Billboard.Models;

public sealed class BillboardConfig
{
    public NotificationType Type { get; set; }
    public string Title { get; set; }
    public string Message { get; set; }
    public int? Timeout { get; set; }
    public bool Modal { get; set; }
    public ThemeMode Theme { get; set; }
    public List<ButtonDefinition> Buttons { get; set; }
    public string Illustration { get; set; }
    public BrandingConfig Branding { get; set; }

    // Internal: used by exe host for pipe IPC
    internal string PipeName { get; set; }

    public int EffectiveTimeout { get; }  // computed, same logic as today
}
```

`MspName` and `MspLogo` move into `BrandingConfig`. `PipeName` becomes internal — only the exe host needs it.

#### BrandingConfig

```csharp
namespace LISSTech.Billboard.Models;

public sealed class BrandingConfig
{
    public string Name { get; set; }
    public string Logo { get; set; }  // file path or URL
}
```

#### ButtonDefinition

```csharp
namespace LISSTech.Billboard.Models;

public sealed class ButtonDefinition
{
    public string Label { get; set; }
    public string Value { get; set; }
    public ButtonStyle Style { get; set; }
    public TimeSpan? Defer { get; set; }
}
```

`Defer` is optional. When present, it indicates this button represents a deferral action. The value is passed through to `BillboardResult.Defer`.

#### BillboardResult

```csharp
namespace LISSTech.Billboard.Models;

public sealed class BillboardResult
{
    public string Button { get; set; }      // clicked button label
    public string Value { get; set; }       // clicked button value
    public int Index { get; set; }          // clicked button index
    public bool Dismissed { get; set; }     // close button or backdrop
    public bool Timeout { get; set; }       // auto-dismissed
    public TimeSpan? Defer { get; set; }    // deferral duration if applicable
    public DateTimeOffset Timestamp { get; set; }

    public static BillboardResult FromButton(ButtonDefinition button, int index);
    public static BillboardResult FromDismiss();
    public static BillboardResult FromTimeout();
}
```

#### Enums

```csharp
public enum NotificationType { Info, Warn, Alert, Critical, Question }
public enum ButtonStyle { Ghost, Primary, Danger }
public enum ThemeMode { Auto, Light, Dark }
```

### Visibility

| Type | Visibility |
|------|-----------|
| `BillboardService` | public |
| `BillboardConfig` | public |
| `BrandingConfig` | public |
| `ButtonDefinition` | public |
| `BillboardResult` | public |
| Enums | public |
| `ModalWindow` | internal |
| `ToastWindow` | internal |
| `NotificationCard` | internal |
| `CliParser` | internal |
| `PipeServer` | internal |
| `MarkdownParser` | internal |
| `LogoService` | internal |
| `ScreenHelper` | internal |

## Exe Host

`LISSTech.Billboard.Host` — minimal WinExe project referencing the DLL.

```csharp
// Program.cs (~50 lines)
static class Program
{
    [STAThread]
    static int Main(string[] args)
    {
        if (CliParser.IsHelpRequested(args)) { /* print usage, return 0 */ }

        BillboardConfig config;
        try { config = CliParser.Parse(args); }
        catch (Exception ex) { /* print error, return 100 */ }

        var result = BillboardService.Show(config);

        // Write result to pipe if --pipe specified
        if (config.PipeName != null) { /* PipeServer write */ }

        // Exit codes: 0=clicked, 1=dismissed, 2=timeout, 100=error
        return result.Timeout ? 2 : result.Dismissed ? 1 : 0;
    }
}
```

`CliParser` remains internal to the DLL — the exe references the DLL and calls it directly (via `InternalsVisibleTo` or by keeping CliParser in the Host project).

### CLI Defer Format

`--buttons "Restart Now:restart:primary;Remind in 1 Hour:defer:ghost:defer=1h"`

The defer duration is specified as a `defer=<duration>` segment after style. The `defer=` prefix disambiguates it from button values that contain colons (e.g., URLs). Supported duration formats: `30m`, `1h`, `4h`, `1d`, `7d`. The parser checks the last segment for the `defer=` prefix before checking for a style name.

## PowerShell Module

### Exported Functions

| Function | Purpose |
|----------|---------|
| `New-BillboardButton` | Create a `ButtonDefinition` with tab-completable parameters |
| `New-BillboardBranding` | Create a `BrandingConfig` for MSP name/logo |
| `New-BillboardNotification` | Create a `BillboardConfig` — the complete notification spec |
| `Show-Billboard` | Fire-and-forget notification. Optional `-PassThru` for process handle |
| `Request-Billboard` | Modal notification that returns `BillboardResult` |
| `Register-BillboardDeferral` | Create a one-shot scheduled task to re-run a script after a delay |

### Builder Cmdlets

```powershell
New-BillboardButton [-Label] <string> -Value <string>
    [-Style {Ghost | Primary | Danger}]
    [-Defer <string>]  # "30m", "1h", "4h", "1d", "7d"

New-BillboardBranding [-Name] <string>
    [-Logo <string>]  # file path or URL

New-BillboardNotification [-Type] {Info | Warn | Alert | Critical | Question}
    [-Title] <string>
    [-Message] <string>
    [-Buttons <ButtonDefinition[]>]
    [-Branding <BrandingConfig>]
    [-Theme {Auto | Light | Dark}]
    [-Timeout <int>]
    [-Modal]
    [-Illustration <string>]
```

### Action Cmdlets

```powershell
Show-Billboard [-Notification] <BillboardConfig>
    [-AsUser]     # Launch via ServiceUI (SYSTEM → user session)
    [-PassThru]   # Return process handle instead of waiting

Request-Billboard [-Notification] <BillboardConfig>
    [-AsUser]     # Launch via ServiceUI + read result from pipe
    # Always modal. Returns BillboardResult.
```

### Routing Logic

```
Request-Billboard called
  ├── Not SYSTEM (or no -AsUser) → [LISSTech.Billboard.BillboardService]::Show($config)
  │   Direct in-process call, returns BillboardResult
  │
  └── SYSTEM + -AsUser → ServiceUI.exe → Billboard.exe --pipe <name> ...
      PS connects as pipe client, reads JSON, returns BillboardResult
```

### Deferral Helper

```powershell
Register-BillboardDeferral -ScriptPath <string> -Delay <TimeSpan>
    [-TaskNamePrefix <string>]  # default: "LISSTech.Billboard.Defer"
```

Creates a one-shot Windows Scheduled Task:
- Task name: `LISSTech.Billboard.Defer.<random-suffix>`
- Trigger: one-time, current time + Delay
- Action: run the specified script as SYSTEM
- Auto-delete after execution

### Usage Example

```powershell
Import-Module LISSTech.Billboard

$branding = New-BillboardBranding 'LISS Consulting' -Logo '\\server\share\logo.png'

$buttons = @(
    New-BillboardButton 'Update Now' -Value update -Style Primary
    New-BillboardButton 'Remind in 1 Hour' -Value defer -Style Ghost -Defer 1h
    New-BillboardButton 'Remind Tomorrow' -Value defer -Style Ghost -Defer 1d
)

$notification = New-BillboardNotification -Type Question `
    -Title 'Google Chrome Update' `
    -Message 'An update for **Google Chrome** is ready to install. Please save your work and close Chrome.' `
    -Buttons $buttons `
    -Branding $branding `
    -Timeout 0

$result = Request-Billboard $notification -AsUser

if ($result.Defer) {
    Register-BillboardDeferral -ScriptPath $MyInvocation.ScriptName -Delay $result.Defer
    exit 0
}

if ($result.Value -eq 'update') {
    Install-ChromeUpdate
}
```

## Migration from LISSTech.StandardLibrary

1. Create new repo at `~\Projects\LISSConsulting\@PowerShell\LISSTech.Billboard\`
2. Move source files from `Modules\LISSTech.Billboard\` preserving git history where practical
3. Refactor csproj from WinExe to Library, create Host project
4. Update `LISSTech.StandardLibrary` WiX installer to reference Billboard's `Release\` output
5. Remove Billboard source from StandardLibrary (keep only the WiX component reference)

## Testing

- Existing xUnit tests (CliParser, MarkdownParser, LogoService, PipeServer) migrate as-is
- Add `BillboardService.Show()` integration tests (require STA thread via `Xunit.StaFact`)
- PowerShell Pester tests for builder cmdlets and parameter validation
- Visual test script for manual UI verification of all variants
