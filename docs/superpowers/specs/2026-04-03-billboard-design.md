# LISSTech.Billboard — Design Spec

## Overview

A WPF-based notification system for displaying toast notifications and modal dialogs to Windows users. Ships as a compiled exe (`Billboard.exe`) with a PowerShell module wrapper (`LISSTech.Billboard`). Designed for managed IT environments where notifications are triggered from SYSTEM context via ServiceUI.

## Goals

- Show polished, branded toast notifications and modal dialogs to end users
- Support 5 severity types: info, warn, alert, critical, question
- Return structured responses from interactive dialogs via named pipe
- Auto-detect system light/dark theme, with manual override
- Single self-contained exe — no .NET runtime installation required on target

## Build

- **Target:** .NET Framework 4.7.2 (`net472`)
- **DPI:** Per-Monitor DPI aware (WPF device-independent pixels throughout — all sizes in spec are DIPs)
- **Project:** C# WPF project in this repo, built via `dotnet publish` and integrated into `justfile`
- **NuGet deps:** `System.Text.Json` (for JSON parsing), `System.IO.Pipes` (built-in)
- **No WPF-UI dependency** — all controls and theming are custom

The exe is pre-installed on endpoints via the MSI, so the warm cache is always primed for script invocations.

## Architecture

```
PowerShell Module (LISSTech.Billboard)
  │
  ├── Show-Billboard    (fire-and-forget toast or modal)
  │     └── launches Billboard.exe [via ServiceUI if SYSTEM]
  │
  └── Request-Billboard (modal, waits for response)
        ├── launches Billboard.exe --pipe {guid} [via ServiceUI if SYSTEM]
        ├── Billboard.exe creates named pipe, PowerShell connects as client
        ├── reads JSON result from pipe
        └── returns PSCustomObject
```

### Components

| Component | Technology | Responsibility |
|-----------|-----------|----------------|
| `Billboard.exe` | C# / .NET 4.7.2 / WPF | Renders toast/modal windows, handles user interaction, creates named pipe server, writes result |
| `LISSTech.Billboard.psd1` | PowerShell module manifest | Exports cmdlets, declares dependency on Billboard.exe |
| `LISSTech.Billboard.dll` | C# binary module | Implements `Show-Billboard` and `Request-Billboard` cmdlets, named pipe client, ServiceUI integration |

### IPC Flow

**Fire-and-forget (Show-Billboard):**
1. PowerShell builds CLI flags from parameters
2. Launches `Billboard.exe` (or via `ServiceUI.exe -process:explorer.exe Billboard.exe` if running as SYSTEM)
3. Returns immediately — no pipe, no waiting

**Interactive (Request-Billboard):**
1. PowerShell generates a GUID, launches `Billboard.exe --pipe LISSTech.Billboard.{guid}` (via ServiceUI if SYSTEM)
2. Billboard.exe creates named pipe server `\\.\pipe\LISSTech.Billboard.{guid}` in the user's session (default security — no ACL needed)
3. PowerShell connects as pipe client (retry loop, 100ms interval, 30s timeout). SYSTEM can connect to any user-session pipe — no ACL gymnastics.
4. User interacts with modal
5. Billboard.exe writes JSON result to pipe, closes pipe, exits
6. PowerShell reads result, returns `PSCustomObject`

**Why Billboard.exe is the pipe server:** When running from SYSTEM (session 0), creating a pipe that the user session can write to requires explicit ACL configuration. Flipping the direction avoids this entirely — Billboard.exe creates the pipe in the user's session with default permissions, and SYSTEM (which has full access) connects as client.

**SYSTEM detection:** The PowerShell module checks `[System.Security.Principal.WindowsIdentity]::GetCurrent().IsSystem`. If true, it prefixes the launch command with `ServiceUI.exe -process:explorer.exe`.

**ServiceUI stdin limitation:** ServiceUI does not forward stdin to the child process. The PowerShell module always uses CLI flags mode when launching via ServiceUI, never `--json` stdin. JSON stdin mode is available for direct (non-ServiceUI) invocations.

**ServiceUI not found:** If running as SYSTEM and ServiceUI.exe is not found on PATH or in the StandardLibrary Bin folder, the cmdlets throw a terminating error.

### Error Handling

| Scenario | Show-Billboard | Request-Billboard |
|----------|---------------|-------------------|
| Billboard.exe not found | Write-Error, return | Throw terminating error |
| Billboard.exe crashes | Silent (fire-and-forget) | Throw terminating error with exit code |
| Pipe connect timeout (30s) | N/A | Throw terminating error (Billboard.exe may have failed to start) |
| Pipe read timeout (5 min) | N/A | Return timeout result object |
| Billboard.exe exits code 100 | Silent | Throw terminating error with stderr message |
| ServiceUI not found (SYSTEM) | Throw terminating error | Throw terminating error |

## CLI Interface

### Flags mode

```
Billboard.exe --type info --title "Update Available" --message "New version ready" --timeout 10
Billboard.exe --type question --title "Restart?" --message "Save work" --buttons "Restart Now:restart:primary;Later:defer:ghost" --modal --pipe LISSTech.Billboard.a1b2c3
Billboard.exe --theme dark --type critical --title "Security Alert" --message "Account locked" --modal
```

| Flag | Type | Default | Description |
|------|------|---------|-------------|
| `--type` | string | required | `info`, `warn`, `alert`, `critical`, `question` (case-insensitive) |
| `--title` | string | required | Heading text |
| `--message` | string | required | Body text (supports basic markdown: **bold**, *italic*, bullet lists, links) |
| `--timeout` | int | per-type | See Timeout Defaults table. Explicit `--timeout` overrides default, even for critical/question. |
| `--modal` | flag | false | Show as centered modal with dimmed backdrop instead of bottom-right toast |
| `--buttons` | string | — | Semicolon-separated `Label:value:style` pairs (style optional, defaults to `ghost`). E.g. `"Restart Now:restart:primary;Later:defer:ghost"`. Default for question: `OK:ok:primary;Cancel:cancel:ghost` |
| `--pipe` | string | — | Named pipe name (not full path — omit `\\.\pipe\` prefix). If omitted, no IPC — exit code only. |
| `--theme` | string | `auto` | `auto` (follow system), `light`, `dark` (case-insensitive) |
| `--msp-name` | string | — | MSP/organization name woven into context footer text and displayed on illustration panel |
| `--msp-logo` | string | — | Logo image file path or URL (PNG, JPG, ICO), displayed in header |
| `--json` | flag | false | Read JSON config from stdin. Flags override JSON values when both present. |

`--pipe` and `--modal` are orthogonal. You can have a modal without a pipe (fire-and-forget modal via `Show-Billboard -Modal`), or a pipe without `--modal` (not typical, but allowed).

### JSON stdin mode

```bash
echo '{ ... }' | Billboard.exe --json
```

The `--json` flag reads a JSON object from stdin:

```json
{
  "type": "question",
  "title": "Restart Now?",
  "message": "Updates are installed and require a restart.\n\n- All apps will be **closed automatically**\n- Estimated time: **2-3 minutes**",
  "modal": true,
  "timeout": 0,
  "theme": "auto",
  "pipe": "LISSTech.Billboard.a1b2c3",
  "buttons": [
    { "label": "Restart Now", "value": "restart", "style": "primary" },
    { "label": "Remind Me Later", "value": "defer", "style": "ghost" }
  ]
}
```

All string values (type, theme, style) are case-insensitive. Flags override JSON values when both are present (useful for debugging).

**Note:** JSON stdin mode is not available when launched via ServiceUI (stdin is not forwarded). The PowerShell module always uses flags mode for ServiceUI launches.

### Exit codes

| Code | Meaning |
|------|---------|
| 0 | Button clicked (any button) or toast auto-dismissed normally |
| 1 | Dismissed by user (close button or clicked outside modal) |
| 2 | Timed out |
| 100 | Error (invalid args, pipe failure, etc.) |

When `--pipe` is provided, the specific button details are in the pipe JSON result. Exit codes are intentionally simple to avoid breakage with variable button counts.

### Named pipe result

JSON written to pipe when interaction completes:

```json
{
  "button": "Restart Now",
  "value": "restart",
  "index": 0,
  "dismissed": false,
  "timeout": false,
  "timestamp": "2026-04-03T15:47:23.000Z"
}
```

Dismissed/timeout:
```json
{
  "button": null,
  "value": null,
  "index": -1,
  "dismissed": true,
  "timeout": false,
  "timestamp": "2026-04-03T15:47:30.000Z"
}
```

## PowerShell Cmdlets

### Show-Billboard

Fire-and-forget. Launches toast (or modal with `-Modal`) and returns immediately. Does not support `Question` type — use `Request-Billboard` for interactive dialogs.

```powershell
Show-Billboard -Type Info -Title "Update Available" -Message "New version ready to install."
Show-Billboard -Type Critical -Title "Security Alert" -Message "Account locked."
Show-Billboard -Type Warn -Title "Disk Space" -Message "Less than **10 GB** remaining."
Show-Billboard -Type Alert -Title "Maintenance" -Message "Restart at **11 PM**." -Modal
```

**Parameters:**

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `-Type` | string | Yes | — | `Info`, `Warn`, `Alert`, `Critical`. No `Question` — use `Request-Billboard`. |
| `-Title` | string | Yes | — | Heading text |
| `-Message` | string | Yes | — | Body text (basic markdown) |
| `-Timeout` | int | No | per-type | See Timeout Defaults. Override with explicit value. |
| `-Modal` | switch | No | false | Show as centered modal instead of bottom-right toast |
| `-Theme` | string | No | `Auto` | `Auto`, `Light`, `Dark` |

**Returns:** Nothing.

### Request-Billboard

Shows a modal dialog and waits for the user's response. Returns a structured result.

```powershell
$result = Request-Billboard -Title "Restart Now?" -Message "Save your work first." -Buttons @(
    @{ Label = "Restart Now"; Value = "restart"; Style = "Primary" }
    @{ Label = "Remind Me Later"; Value = "defer"; Style = "Ghost" }
)

if ($result.Value -eq "restart") {
    Restart-Computer -Force
}
```

```powershell
# Critical modal with custom buttons
$result = Request-Billboard -Type Critical -Title "Security Alert" `
    -Message "Unauthorized access detected." `
    -Buttons @(
        @{ Label = "Lock Workstation"; Value = "lock"; Style = "Danger" }
        @{ Label = "Dismiss"; Value = "dismiss"; Style = "Ghost" }
    )
```

**Parameters:**

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `-Type` | string | No | `Question` | `Question`, `Info`, `Warn`, `Alert`, `Critical` |
| `-Title` | string | Yes | — | Heading text |
| `-Message` | string | Yes | — | Body text (basic markdown) |
| `-Buttons` | hashtable[] | No | OK/Cancel | Array of button definitions. Each: `Label` (required), `Value` (required), `Style` (optional: `Primary`, `Danger`, `Ghost` — default `Ghost`) |
| `-Timeout` | int | No | 0 | 0 = wait forever (default for modals). Explicit value overrides. |
| `-Theme` | string | No | `Auto` | `Auto`, `Light`, `Dark` |

**Button styles:** `Primary` (blue fill), `Danger` (red fill), `Ghost` (outline). Case-insensitive in CLI/JSON, PascalCase convention in PowerShell.

**Returns:** `PSCustomObject` — or throws terminating error on launch/pipe failure.

```powershell
# Result object
$result.Button    # "Restart Now" (label of clicked button)
$result.Value     # "restart" (value of clicked button)
$result.Index     # 0 (button index)
$result.Dismissed # $false
$result.Timeout   # $false
$result.Timestamp # [datetime]
```

## Visual Design

### Toast (bottom-right, primary monitor)

- 420 DIPs wide, 14 DIP border-radius
- Glass background: Acrylic (Win 11), solid fallback (Win 10)
- Colored header bar with Lucide icon badge, uppercase type label, "LISS" wordmark, close button
- Body: 18 DIP Inter bold title, 15 DIP Inter regular message
- 2 DIP border colored per severity type
- Slide-in animation from right
- Stacks vertically when multiple toasts shown
- Positioned on the **primary monitor**, bottom-right, above the taskbar

### Modal (centered, primary monitor)

- 1000 DIPs wide, 16 DIP border-radius
- Dimmed backdrop with blur
- 48 DIP icon badge, uppercase type label, 22 DIP title
- Divider line
- Body text with markdown support
- Full-width stacked buttons
- Type-colored card backgrounds per notification type
- Type-colored primary buttons per notification type
- 360px illustration side panel (when illustration available) with baked-in type-colored background PNG
- Context footer text with MSP branding (`--msp-name`)
- MSP logo support (`--msp-logo`)
- Scale-in animation
- Centered on the **primary monitor**

### Glass Effect

Acrylic backdrop for both light and dark themes on Windows 11 (more reliable than Mica for borderless floating windows). On Windows 10, falls back to solid background.

### Color Palette

| Type | Dark badge | Light badge | Border (dark) | Border (light) |
|------|-----------|-------------|---------------|----------------|
| Info | `#1863DC` | `#1863DC` | `rgba(24,99,220,0.4)` | `rgba(24,99,220,0.2)` |
| Warn | `#FCE100` text `#0A0A0F` | `#B47A00` text `#FFF` | `rgba(252,225,0,0.35)` | `rgba(180,122,0,0.2)` |
| Alert | `#FF8C00` text `#0A0A0F` | `#C46200` text `#FFF` | `rgba(255,140,0,0.4)` | `rgba(196,98,0,0.2)` |
| Critical | `#FF4141` text `#FFF` | `#C42B30` text `#FFF` | `rgba(255,65,65,0.45)` | `rgba(196,43,48,0.2)` |
| Question | `#0056A7` text `#FFF` | `#1863DC` text `#FFF` | `rgba(24,99,220,0.35)` | `rgba(24,99,220,0.2)` |

### Button Styles

Primary buttons are type-colored — the fill color matches the notification type's accent color rather than a single fixed blue.

| Style | Dark | Light |
|-------|------|-------|
| Primary | Type-colored fill (matches notification type accent) | Type-colored fill (matches notification type accent) |
| Danger | `#E03E3E` fill, `#B02020` border | `#C42B30` fill, `#A02025` border |
| Ghost | `rgba(255,255,255,0.05)` fill, `rgba(255,255,255,0.15)` border | `rgba(0,0,0,0.03)` fill, `rgba(0,0,0,0.12)` border |

Hover: brightness increase. Press: brightness decrease + slight opacity reduction. (WPF `Trigger` on `IsMouseOver`/`IsPressed`.)

### Typography

| Element | Font | Weight | Size |
|---------|------|--------|------|
| Type label (header) | Inter | 800 | 13 DIP, uppercase, 2.5 DIP spacing |
| Title | Inter | 700 | 18 DIP (toast), 22 DIP (modal) |
| Body | Inter | 400 | 15 DIP, line-height 1.75 |
| Button | Inter | 700 | 15 DIP, uppercase, 1 DIP spacing |
| Brand watermark | Inter | 700 | 10 DIP, uppercase, 2.5 DIP spacing |

Inter font (Regular, SemiBold, Bold, ExtraBold) bundled as embedded resources in the exe (~300 KB). Not installed system-wide — loaded from the assembly at runtime via pack URI.

### Markdown Support (body text)

Subset only:
- `**bold**` → bold
- `*italic*` → italic
- `- item` → bullet list (single level only)
- `[text](url)` → hyperlink (opens default browser)

No nesting (e.g., `**bold *and italic***`), no code blocks, headers, tables, or images. Use a simple regex-based parser, not a full markdown library.

### Icons (Lucide)

| Type | Icon name |
|------|-----------|
| Info | `info` |
| Warn | `triangle-alert` |
| Alert | `bell-ring` |
| Critical | `octagon-x` |
| Question | `circle-help` |
| Close | `x` |

Icons ship as embedded XAML path data in the exe — no runtime icon loading.

### Timeout Defaults

These are the defaults when no explicit `--timeout` / `-Timeout` is provided. An explicit value always overrides, even for critical/question.

| Type | Default timeout | Can auto-dismiss? |
|------|----------------|-------------------|
| Info | 10s | Yes |
| Warn | 10s | Yes |
| Alert | 15s | Yes |
| Critical | 0 (persist) | No by default — requires click. Override with explicit timeout. |
| Question | 0 (persist) | No by default — requires click. Override with explicit timeout. |

## Packaging

- `Billboard.exe` ships in `Bin/` alongside other standard binaries
- `LISSTech.Billboard.psd1` and `.psm1` ship in `Modules/LISSTech.Billboard/`
- Inter font embedded as assembly resources (~300 KB)
- Lucide icons embedded as XAML path data (no external icon files)
- Module manifest declares dependency on `LISSTech.StandardLibrary` (for ServiceUI.exe path)
- Justfile gets `billboard` recipe for `dotnet publish` with self-contained/R2R flags

## Platform Support

| OS | Glass effect | Solid fallback |
|----|-------------|----------------|
| Windows 11 | Acrylic (both themes) | — |
| Windows 10 | — | Solid dark/light background |

Both look correct — Win 10 just lacks the translucency effect.

## Future Considerations (not in v1)

- Progress bar toast (for long-running operations)
- Text input field in modals
- Custom icon support (pass path to .ico/.png)
- Toast grouping/replacing (update existing toast by ID)
- Sound on critical/question
- Multi-monitor support (currently primary monitor only)
