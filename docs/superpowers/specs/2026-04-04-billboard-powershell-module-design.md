# LISSTech.Billboard PowerShell Module — Design Spec

## Overview

A PowerShell module wrapping `Billboard.exe` — the WPF notification system. Provides two cmdlets: `Show-Billboard` (fire-and-forget) and `Request-Billboard` (interactive, returns structured result via named pipe). Supports launching into the user's desktop session from SYSTEM context via ServiceUI.

Compatible with PowerShell 5.1 and PowerShell 7+.

## Module Structure

```
Modules/LISSTech.Billboard/
├── Bin/
│   ├── Billboard.exe       # WPF notification app
│   └── ServiceUI.exe       # Session 0 → user session launcher
├── LISSTech.Billboard.psd1 # Module manifest
├── LISSTech.Billboard.psm1 # Module implementation
└── Tests/
    └── LISSTech.Billboard.Tests.ps1  # Pester 6 tests
```

Standalone module — not nested in `LISSTech.StandardLibrary`. All binaries located relative to `$PSScriptRoot\Bin\`.

## Cmdlets

### Show-Billboard (fire-and-forget)

```powershell
Show-Billboard
    -Type <string>           # Required. info, warn, alert, critical, question
    -Title <string>          # Required. Heading text
    -Message <string>        # Required. Body text (supports markdown)
    [-Timeout <int>]         # Override default per-type timeout (seconds). 0 = persist
    [-Modal]                 # Show as centered modal instead of bottom-right toast
    [-Theme <string>]        # auto (default), light, dark
    [-Buttons <hashtable[]>] # @(@{Label="OK"; Value="ok"; Style="Primary"}, ...)
    [-Illustration <string>] # Illustration name or "none"
    [-MspName <string>]      # Organization name for footer branding
    [-MspLogo <string>]      # Logo file path or URL
    [-AsUser]                # Launch via ServiceUI into user session
    [-PassThru]              # Return the Process object
```

**Returns:** Nothing by default. With `-PassThru`, returns `System.Diagnostics.Process`.

Launches `Billboard.exe` and returns immediately. Does not set up a named pipe. The caller does not wait for the notification to be dismissed.

### Request-Billboard (interactive, returns result)

```powershell
Request-Billboard
    -Type <string>           # Required. info, warn, alert, critical, question
    -Title <string>          # Required. Heading text
    -Message <string>        # Required. Body text (supports markdown)
    [-Timeout <int>]         # Override default per-type timeout (seconds). 0 = persist
    [-Theme <string>]        # auto (default), light, dark
    [-Buttons <hashtable[]>] # @(@{Label="OK"; Value="ok"; Style="Primary"}, ...)
    [-Illustration <string>] # Illustration name or "none"
    [-MspName <string>]      # Organization name for footer branding
    [-MspLogo <string>]      # Logo file path or URL
    [-AsUser]                # Launch via ServiceUI into user session
```

**Returns:** `PSCustomObject` with the following properties:

```powershell
@{
    Button    = "Restart Now"          # Label of clicked button, or $null if dismissed
    Value     = "restart"              # Value of clicked button, or $null if dismissed
    Index     = 0                      # 0-based button index, or -1 if dismissed
    Dismissed = $false                 # $true if user dismissed or timed out
    Timeout   = $false                 # $true if auto-timeout (Dismissed is also $true)
    Timestamp = [DateTimeOffset]       # UTC timestamp of interaction
}
```

Always implies `-Modal`. Always creates a named pipe for IPC. The cmdlet blocks until the user interacts with the notification (or it times out).

## Argument Building

Both cmdlets share internal argument-building logic. Parameters map to CLI flags:

| Parameter | CLI Flag |
|-----------|----------|
| `-Type` | `--type <value>` |
| `-Title` | `--title <value>` |
| `-Message` | `--message <value>` |
| `-Timeout` | `--timeout <value>` |
| `-Modal` | `--modal` |
| `-Theme` | `--theme <value>` |
| `-Buttons` | `--buttons "Label:Value:Style;..."` |
| `-Illustration` | `--illustration <value>` |
| `-MspName` | `--msp-name <value>` |
| `-MspLogo` | `--msp-logo <value>` |

`Request-Billboard` additionally appends `--modal` and `--pipe <name>`.

The module always uses CLI flags mode (never `--json`) because ServiceUI does not forward stdin.

## Buttons Serialization

The `-Buttons` parameter accepts an array of hashtables:

```powershell
-Buttons @(
    @{ Label = "Restart Now"; Value = "restart"; Style = "Primary" }
    @{ Label = "Later"; Value = "defer"; Style = "Ghost" }
)
```

Serialized to the CLI format: `"Restart Now:restart:primary;Later:defer:ghost"`

`Style` is optional and defaults to `Ghost` if omitted.

## Named Pipe IPC (Request-Billboard)

1. Generate pipe name: `LISSTech.Billboard.<8-char-guid-prefix>` (e.g., `LISSTech.Billboard.a1b2c3d4`)
2. Launch `Billboard.exe` with `--pipe <name>` and `--modal`
3. Create `System.IO.Pipes.NamedPipeClientStream` and connect with ~15s timeout (allows for ServiceUI launch + window animation)
4. Read full JSON response via `System.IO.StreamReader`
5. Deserialize with `ConvertFrom-Json`
6. Return as `PSCustomObject`

**Billboard.exe is the pipe server.** It creates the pipe in the user's session with default permissions. PowerShell (even running as SYSTEM) connects as a client. No ACL configuration needed — this is the reason the pipe direction was designed this way.

### Error Handling

- Billboard.exe exits before pipe connects → return result based on exit code (1=dismissed, 2=timeout)
- Pipe connection times out → throw terminating error
- Billboard.exe not found → throw terminating error
- ServiceUI not found (when `-AsUser`) → throw terminating error

## -AsUser / ServiceUI

When `-AsUser` is specified:

1. **Check if running as SYSTEM** — Compare current identity SID to `S-1-5-18`. If not SYSTEM, write a warning and launch Billboard directly (ignore the flag).
2. **Locate ServiceUI** — `$PSScriptRoot\Bin\ServiceUI.exe`. Throw if not found.
3. **Wrap the command** — Instead of launching `Billboard.exe` directly:
   ```
   ServiceUI.exe -process:explorer.exe "C:\...\Bin\Billboard.exe" --type info --title "..." ...
   ```
4. **Pipe IPC is unchanged** — Billboard.exe creates the pipe in the user session; SYSTEM connects as client.

## Exit Codes

When using `Show-Billboard` without `-PassThru`, exit codes are not surfaced. With `-PassThru`, the caller can check `$process.ExitCode` after waiting.

`Request-Billboard` uses the pipe for structured results. Exit codes serve as fallback:

| Code | Meaning |
|------|---------|
| 0 | Button clicked or toast auto-dismissed |
| 1 | User dismissed (close, Escape, backdrop) |
| 2 | Timed out |
| 100 | Error |

## Testing (Pester 6)

### Unit Tests (no exe needed)

- Parameter validation — missing required params throw errors
- Argument builder — each parameter correctly maps to CLI flags
- Buttons hashtable → `Label:Value:Style;...` serialization
- `-AsUser` prepends ServiceUI to command when running as SYSTEM
- `-AsUser` when not SYSTEM writes warning and falls through
- Pipe name generation format is valid
- `-Modal` flag forwarding
- `Request-Billboard` always adds `--modal` and `--pipe`
- `-PassThru` returns process object type

### Integration Tests (tagged `@Integration`)

Require `Billboard.exe` and a desktop session. Skipped in headless/CI environments.

- `Show-Billboard` with `-PassThru` returns a live process
- `Request-Billboard` with a short timeout returns a timeout result via pipe
- Exit code mapping (0, 1, 2, 100)

## Usage Examples

### Simple toast notification

```powershell
Show-Billboard -Type Info -Title "Update Available" -Message "A new version is ready to install."
```

### Critical modal from SYSTEM context

```powershell
Show-Billboard -Type Critical -Title "Security Alert" `
    -Message "Your account has been locked due to suspicious activity." `
    -Modal -AsUser
```

### Interactive question with response

```powershell
$result = Request-Billboard -Type Question `
    -Title "Restart Required" `
    -Message "Windows updates have been installed. Restart now?" `
    -Buttons @(
        @{ Label = "Restart Now"; Value = "restart"; Style = "Primary" }
        @{ Label = "Remind Me Later"; Value = "defer"; Style = "Ghost" }
    )

if ($result.Value -eq 'restart') {
    Restart-Computer -Force
}
```

### Branded notification with MSP logo

```powershell
Show-Billboard -Type Info `
    -Title "Maintenance Window" `
    -Message "Scheduled maintenance begins at **10:00 PM** tonight." `
    -MspName "Acme IT Services" `
    -MspLogo "C:\ProgramData\AcmeIT\logo.png" `
    -AsUser
```
