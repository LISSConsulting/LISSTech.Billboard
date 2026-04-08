<p align="center">
  <img src="https://img.shields.io/badge/LISS_TECH-Billboard-E53935?style=for-the-badge&labelColor=000" alt="Billboard">
</p>

<h1 align="center">Billboard</h1>
<p align="center">
  <strong>WPF notification system for Windows endpoints — toast &amp; modal, dark &amp; light, scriptable via PowerShell</strong>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/.NET_Framework-4.7.2-512BD4?style=for-the-badge&logo=dotnet&logoColor=000&labelColor=000" alt=".NET Framework 4.7.2">
  <img src="https://img.shields.io/badge/PowerShell-5.1-2671BE?style=for-the-badge&logo=powershell&logoColor=000&labelColor=000" alt="PowerShell 5.1">
  <img src="https://img.shields.io/badge/WPF-UI-4ECDC4?style=for-the-badge&labelColor=000" alt="WPF">
  <img src="https://img.shields.io/badge/Platform-Windows-FFE66D?style=for-the-badge&labelColor=000" alt="Windows">
  <img src="https://img.shields.io/badge/License-Apache_2.0-FF6B35?style=for-the-badge&labelColor=000" alt="Apache 2.0">
</p>

<p align="center">
  <a href="#-quick-start"><b>Quick Start</b></a> · <a href="#-architecture"><b>Architecture</b></a> · <a href="#-powershell-api"><b>PowerShell API</b></a> · <a href="#-notification-types"><b>Types</b></a> · <a href="#-exe-host"><b>Exe Host</b></a> · <a href="#-building"><b>Building</b></a>
</p>

---

## Quick Start

```powershell
# Import the module
Import-Module .\Release\LISSTech.Billboard\LISSTech.Billboard.psd1

# Fire-and-forget toast
Show-Billboard (New-BillboardNotification -Type Info `
    -Title 'Chrome Updated' `
    -Message 'Google Chrome has been updated to version **131.0.6778**.' `
    -Branding (New-BillboardBranding 'Contoso IT'))

# Modal that waits for user response
$result = Request-Billboard (New-BillboardNotification -Type Question `
    -Title 'Restart Required' `
    -Message 'A security update requires a restart.' `
    -Buttons @(
        New-BillboardButton 'Restart Now' -Value restart -Style Primary
        New-BillboardButton 'Remind in 4 Hours' -Value defer -Style Ghost -Defer 4h
    ) `
    -Branding (New-BillboardBranding 'Contoso IT') `
    -Modal)

$result.Value  # "restart" or "defer"
```

---

## Architecture

```
┌──────────────────────────────────────────────────────┐
│  PowerShell Module (.psm1)                           │
│  New-Billboard* · Show-Billboard · Request-Billboard │
└──────────┬──────────────────────────────┬────────────┘
           │ direct DLL call              │ -AsUser (SYSTEM)
           ▼                              ▼
┌─────────────────────┐    ┌──────────────────────────┐
│ LISSTech.Billboard  │    │ Billboard.exe            │
│ .dll                │    │ (thin host)              │
│                     │    │                          │
│ BillboardService    │    │ CLI args → Show()        │
│ .Show(config)       │    │ result → named pipe      │
│                     │    │ exit code 0/1/2/100      │
│ WPF windows, models,│    └──────────┬───────────────┘
│ themes, resources   │               │ ServiceUI.exe
└─────────────────────┘               │ (user session)
                                      ▼
                                 User's desktop
```

| Layer | Description |
|-------|-------------|
| **PowerShell module** | Builder cmdlets (`New-Billboard*`) and action cmdlets (`Show-Billboard`, `Request-Billboard`). Calls the DLL directly in user sessions. |
| **DLL** (`LISSTech.Billboard.dll`) | Class library with all WPF UI, models, services, and the static `BillboardService.Show()` API. |
| **Exe host** (`Billboard.exe`) | Thin wrapper for SYSTEM/ServiceUI scenarios. Parses CLI args, calls `BillboardService.Show()`, returns result via named pipe. |

---

## PowerShell API

### Builder Cmdlets

| Cmdlet | Description |
|--------|-------------|
| `New-BillboardButton` | Create a button with label, value, style, and optional defer duration |
| `New-BillboardBranding` | Set organization name and logo |
| `New-BillboardNotification` | Build a notification config from type, title, message, buttons, branding, theme |

### Action Cmdlets

| Cmdlet | Description |
|--------|-------------|
| `Show-Billboard` | Display a notification (fire-and-forget). Use `-AsUser` from SYSTEM context. |
| `Request-Billboard` | Display and wait for user response. Returns `BillboardResult` with button, value, defer. |
| `Register-BillboardDeferral` | Schedule a re-show via Windows Task Scheduler after a defer duration. |

### Parameters

```powershell
# Button styles: Primary, Ghost, Danger
New-BillboardButton 'OK' -Value ok -Style Primary

# Defer durations: 30m, 1h, 4h, 1d, 7d
New-BillboardButton 'Later' -Value defer -Style Ghost -Defer 4h

# Notification types: Info, Warn, Alert, Critical, Question
# Themes: Auto, Light, Dark
# Timeout: seconds (0 = no timeout)
New-BillboardNotification -Type Critical -Title '...' -Message '...' `
    -Theme Dark -Timeout 0 -Modal
```

### Result Object

```json
{
  "Button": "Restart Now",
  "Value": "restart",
  "Index": 0,
  "Dismissed": false,
  "Timeout": false,
  "Defer": "04:00:00",
  "Timestamp": "2026-04-07T23:41:07Z"
}
```

---

## Notification Types

| Type | Default Timeout | Use Case |
|------|:-:|-------------|
| **Info** | 10s | Software updates, policy changes, FYI notices |
| **Warn** | 10s | Low disk space, certificate expiry, non-urgent issues |
| **Alert** | 15s | Password expiring, compliance deadlines |
| **Critical** | none | Security incidents, endpoint protection disabled |
| **Question** | none | Restart required, user decision needed |

Each type has its own color scheme, badge icon, and illustration (dark + light variants).

---

## Exe Host

For SYSTEM/ServiceUI scenarios where the notification must appear in the user's desktop session:

```bash
# Basic toast
Billboard.exe --type info --title "Update" --message "New version available"

# Modal with buttons and pipe for IPC
Billboard.exe --type question --title "Restart?" --message "Save work" \
  --buttons "Restart Now:restart:primary;Later:defer:ghost:defer=4h" \
  --modal --pipe Billboard.abc123

# Exit codes: 0=button clicked, 1=dismissed, 2=timeout, 100=error
```

The PowerShell module handles this automatically with `-AsUser`:

```powershell
# From a SYSTEM-context script (e.g., Intune remediation)
Show-Billboard $notification -AsUser
$result = Request-Billboard $notification -AsUser
```

---

## Building

Requires: [just](https://github.com/casey/just), .NET SDK (targets .NET Framework 4.7.2).

```bash
just              # list all recipes
just build        # build DLL + exe (Debug)
just publish      # build Release, assemble PS module in Release/
just test         # run xUnit tests (81 tests)
just smoke        # visual smoke test — 20 variants (5 types × 2 modes × 2 themes)
just clean        # remove Release/ and obj/
```

### Module Output

```
Release/LISSTech.Billboard/
├── Assembly/
│   ├── LISSTech.Billboard.dll
│   └── (dependency DLLs)
├── Bin/
│   ├── Billboard.exe
│   └── ServiceUI.exe
├── LISSTech.Billboard.psd1
└── LISSTech.Billboard.psm1
```

---

## Project Structure

```
LISSTech.Billboard/
├── src/
│   ├── LISSTech.Billboard/           # Class library (DLL)
│   │   ├── BillboardService.cs       #   Static Show() API
│   │   ├── Models/                   #   BillboardConfig, ButtonDefinition, BrandingConfig
│   │   ├── Services/                 #   CliParser, PipeServer, MarkdownParser
│   │   ├── Controls/                 #   NotificationCard (WPF UserControl)
│   │   ├── Views/                    #   ToastWindow, ModalWindow
│   │   ├── Themes/                   #   Colors, Typography, Buttons (XAML)
│   │   └── Assets/                   #   Fonts, illustrations, brand logo
│   └── LISSTech.Billboard.Host/      # Thin exe host
│       └── Program.cs                #   CLI → BillboardService.Show() → pipe
├── tests/
│   └── LISSTech.Billboard.Tests/     # xUnit tests
├── vendor/                           # ServiceUI.exe
├── LISSTech.Billboard.psm1           # PowerShell module script
├── LISSTech.Billboard.psd1           # PowerShell module manifest
└── justfile                          # Build recipes
```

---

<p align="center">
  <img src="https://img.shields.io/badge/.NET_Framework-4.7.2-512BD4?style=for-the-badge&labelColor=000" alt=".NET 4.7.2">
  <img src="https://img.shields.io/badge/PowerShell-5.1-2671BE?style=for-the-badge&labelColor=000" alt="PS 5.1">
  <img src="https://img.shields.io/badge/WPF-Notifications-4ECDC4?style=for-the-badge&labelColor=000" alt="WPF">
  <br/>
  <sub><strong>LISS Consulting, Corp.</strong></sub>
</p>
