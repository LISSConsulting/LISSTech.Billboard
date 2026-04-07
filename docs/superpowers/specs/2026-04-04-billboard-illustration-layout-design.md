# Billboard Modal Illustration Layout — Side Panel

**Date:** 2026-04-04
**Status:** Implemented
**Scope:** Modal notifications only (toast unchanged)

## Summary

The modal layout uses a dedicated left-side column containing the illustration at full opacity with a type-colored card background baked into the PNG. The modal is 1000px wide with a 360px illustration column.

## Design

### Layout Structure

The modal NotificationCard switches from a single-column StackPanel to a two-column Grid when an illustration is available.

```
┌──────────────┬──────────────────────────────────┐
│              │ [badge] INFO   [logo]  LISS    X │
│   360px      ├──────────────────────────────────┤
│   tinted     │                                  │
│   column     │  Title text here                 │
│              │  Message body text               │
│   illus-     │  continues here...               │
│   tration    │                                  │
│   (fills     │  [  OK  ]                        │
│    column    │  [ Cancel ]                      │
│    w/10px    │                                  │
│    margin)   │  Context footer text             │
│              │                                  │
│  MSP NAME    │                                  │
└──────────────┴──────────────────────────────────┘
              1000px total (modal)
```

- **Left column:** 360px fixed width, type-colored card background (baked into PNG)
- **Right column:** `*` (takes remaining ~640px) — contains all existing card content unchanged
- **No illustration = no column.** When illustration is null, the card renders as a single column. The left column Border gets `Visibility="Collapsed"` and the Grid column width is set to `0`

### Illustration Treatment

- **Size:** No fixed width — image fills the column with 10px margin on each side
- **Stretch:** `Uniform` — fits within column, no cropping
- **Clipping:** No circular crop. The column's `ClipToBounds="True"` handles any vertical overflow naturally
- **Position:** Centered horizontally and vertically in the column
- **Opacity:** 1.0 (full)
- **Background:** Baked into PNG per theme (type-colored card background) — no frosted panel overlay
- **No border, ring, or shadow**

### Illustration Column

- **Background:** Type-colored card background, matching the `CardBg` resources in Colors.xaml (e.g., `#1C2030` for Info dark, `#F0F4FB` for Info light)
- **Corner radius:** `CornerRadius="14,0,0,14"` — matches card's rounded corners on the left edge only
- **ClipToBounds:** True
- **Brand text:** MSP name displayed at bottom of illustration column

### Type-Colored Backgrounds

Each notification type has its own tinted card background color per theme, defined in Colors.xaml. These are baked into the illustration PNGs during the SVG-to-PNG conversion pipeline.

### Context Footer

A `--brand` context footer text area replaces the static "LISS TECHNOLOGIES" watermark. The footer text is dynamically generated based on notification type and `--msp-name` value (e.g., "Sent by your organization" / "Contact your IT helpdesk").

### MSP Branding

- `--msp-name <text>` — MSP/organization name woven into context footer text and displayed on illustration panel
- `--msp-logo <path>` — Logo image file path or URL (PNG, JPG, ICO), displayed in header

## Scope

### Files Changed

| File | Change |
|------|--------|
| `NotificationCard.xaml` | Two-column Grid layout (360px illustration column + content column) |
| `NotificationCard.xaml.cs` | `ApplyIllustration()` populates illustration column; context footer and MSP branding logic |
| `ModalWindow.xaml` | Modal width updated to 1000px |
| `BillboardConfig.cs` | Added `MspName` and `MspLogo` properties |
| `CliParser.cs` | Added `--msp-name` and `--msp-logo` flag parsing |
| `Colors.xaml` | Type-colored card background resources (`CardBg`) |
| `Buttons.xaml` | Type-colored primary button styles |

### Behavior

- **Modal with illustration:** Two-column layout with side panel
- **Modal without illustration:** Single-column layout (current behavior preserved)
- **Toast (any):** Current layout unchanged — illustration continues as faint watermark overlay if present
- **All 5 notification types** (Info, Warn, Alert, Critical, Question) use type-colored card backgrounds
- **Both themes** (Dark/Light) supported — background baked into PNG per theme
- **Type-colored primary buttons** — primary button color matches notification type

## Constraints

- No WPF-UI dependency
- Target framework: net472 (not net8.0)
- Illustrations are PNG resources with baked-in type-colored backgrounds (SVG source files live in `tests/illustrations-svg/`)
