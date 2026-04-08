# LISSTech.Billboard

WPF notification system for Windows endpoints, packaged as a PowerShell 5.1 module and .NET class library.

## Build

Requires: just, .NET SDK (targets .NET Framework 4.7.2).

```bash
just              # list all recipes
just build        # build DLL + exe (Debug)
just publish      # build Release, assemble PS module in Release/
just test         # run xUnit tests
just clean        # remove Release/ and obj/
```

## Project structure

- `src/LISSTech.Billboard/` — Class library (DLL): WPF UI, models, services, static BillboardService API
- `src/LISSTech.Billboard.Host/` — Thin console exe for ServiceUI/SYSTEM scenarios
- `tests/LISSTech.Billboard.Tests/` — xUnit tests
- `Release/LISSTech.Billboard/` — Build output: complete PS module package (gitignored)
- `LISSTech.Billboard.psd1` — PowerShell module manifest (source)
- `LISSTech.Billboard.psm1` — PowerShell module script (source)
- `vendor/` — Third-party binaries (ServiceUI.exe)

## Code style

- C#: file-scoped namespaces, nullable enabled, latest language version
- 2-space indentation for XAML
- Conventional commits: `feat:`, `fix:`, `chore:`, etc.
- PascalCase for directory names, file names, public members

## Target

- .NET Framework 4.7.2 (pre-installed on Windows, no runtime to bundle)
- PowerShell 5.1

## Illustrations

- Sourced from [Storyset](https://storyset.com) (Rafiki style), free license with attribution
- Each type has dark and light variants: `{name}.png` and `{name}-light.png`
- Illustration PNG backgrounds must match the card's `CardBg` color for that type (defined in `Themes/Colors.xaml`), e.g. `Critical.CardBg.Dark` = `#261C1E`, `Critical.CardBg.Light` = `#FBF0F1`
- Pack URIs in the DLL must use the fully-qualified form: `pack://application:,,,/LISSTech.Billboard;component/Assets/...` (short-form resolves to the host exe, not the DLL)

## Git

- Main branch: `trunk`
