# System libraries

suigui apps talk to a small **system lib** surface. In the web preview these are JS bindings (`runtime/libs.js`). SoftUI will reimplement the same names against the guest framebuffer.

## `ui`

Widget tree, focus, and hit-testing are provided by the runtime automatically. You normally declare widgets in markup instead of calling `ui` directly.

## `draw`

Low-level drawing (for advanced apps / future escape hatches):

| Call | Role |
|------|------|
| `draw.clear(color)` | Clear surface |
| `draw.fill(x, y, w, h, color)` | Rectangle |
| `draw.text(str, x, y, color)` | Glyph text |

v1 examples use widgets only; `draw` is available to the host bridge.

## `app`

| Call | Role |
|------|------|
| `app.title(name)` | Set window/app title |
| `app.quit()` | Request close (preview: no-op / status) |

The `app "Name"` header and `window title="…"` cover most cases.

## `time`

| Call | Role |
|------|------|
| `time.now()` | Epoch ms |
| `time.clock()` | `"HH:MM"` local clock string |

Useful later for status bars and clocks in SoftUI hybrid chrome.

## Design rule

Prefer **markup + handlers** for UI. Reach for libs when you need host services (time, future fs, etc.).
