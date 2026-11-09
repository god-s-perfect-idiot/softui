# SoftUI GUI styling guidelines

OS chrome and SoftASM/framebuffer apps share one look: **webOS-inspired satin charcoal**, steel-blue interactive accents, and gold secondary highlights. Apps are **`.sox` (SoftASM)** for now — no high-level GUI SDK.

Source of truth in code: `runtime/src/demo_gfx.zig` (`COLOR_*`, `clearPlate`, `fillVGrad`). Desktop chrome: `runtime/src/gui.zig`.

## Background (default)

Every SoftUI surface starts on a **vertical gray gradient**. Do not use a flat black/gray fill for the default plate.

| Token | ARGB | Hex |
|-------|------|-----|
| `COLOR_BG_TOP` | `0xFF4A4A4A` | `#4A4A4A` |
| `COLOR_BG_BOTTOM` | `0xFF2C2C2C` | `#2C2C2C` |

Rules:

1. **Default for all UI** — bootloader, desktop, bars, and app plates use this gradient unless the frame intentionally owns a different backdrop.
2. **Override only by re-render** — SoftASM demos (plasma, fire, …) and full-bleed media may clear to their own palette each frame.
3. **Direction** — top → bottom, lighter charcoal into darker charcoal.
4. Helpers: `gfx.clearPlate(...)` or `gfx.fillVGrad(..., COLOR_BG_TOP, COLOR_BG_BOTTOM)`.

## Global brand colors

| Role | Token | Hex | Use for |
|------|-------|-----|---------|
| **Primary** | `COLOR_PRIMARY` | `#5078A0` | Selection, focus, interactive chrome, active tray items |
| **Secondary** | `COLOR_SECONDARY` | `#E8C84A` | Sparse accents (stars, badges, highlight marks) — not primary actions |

## Supporting neutrals

| Token | Hex | Role |
|-------|-----|------|
| `COLOR_FG` | `#F2F2F2` | Primary text |
| `COLOR_DIM` | `#B0B0B0` | Secondary text / metadata |
| `COLOR_BAR` | `#3D3F43` | Title / tray bar mid tone |
| `COLOR_PANEL` | `#383838` | Nested panels |
| `COLOR_BORDER` | `#1A1A1A` | Recessed dividers |

`COLOR_ACCENT` remains as an alias of `COLOR_PRIMARY` for older demo code.

## SoftASM apps

Ship UI as SoftASM sources under `sysroot/*.soft` → packed `.sox`. Paint with framebuffer syscalls / shared gfx helpers; start from `clearPlate` unless the app replaces the background for that frame.
