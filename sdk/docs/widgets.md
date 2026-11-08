# Widgets

All widgets are elements in the suigui tree. Layout is flow-first via parents (`row` / `col`).

## `window`

Root application surface with a title bar.

| Attr | Type | Notes |
|------|------|-------|
| `title` | string | Title bar text |
| `fill` | flag | Use full canvas (recommended) |

Children are laid out in the content area below the title bar (column by default).

## `col`

Vertical stack.

| Attr | Notes |
|------|-------|
| `gap` | Vertical spacing |
| `pad` | Padding |
| `fill` / `grow` | Expand in parent |

## `row`

Horizontal stack. Same spacing attrs as `col`. Children with `grow` share leftover width.

## `label`

Readout text.

| Attr | Notes |
|------|-------|
| `#id` | Required if handlers update it |
| `text` | Display string |
| `align` | `start`, `center`, `end` |
| `grow` | Take leftover space (useful for displays) |

Handlers assign `id.text = …`.

## `button`

Clickable control.

| Attr | Notes |
|------|-------|
| `text` | Caption |
| `grow` | Share row/col space |
| `click` | A string or B block |

## `field`

Single-line text field (preview).

| Attr | Notes |
|------|-------|
| `text` | Current value |
| `placeholder` | Dim hint when empty |

## `box`

Plain panel / spacer region. Useful as a flexible render area with `grow` / `fill` / `scroll` (scroll visual TBD).

## Styling notes

The preview uses SoftUI-inspired colors (dark panel, blue accent). SoftUI guest hosting will match SoftUI chrome tokens.
