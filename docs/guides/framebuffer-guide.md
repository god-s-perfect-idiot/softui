# Framebuffer & SoftUI console

SoftUI’s entire visual identity is an RGBA8 framebuffer SoftUI itself paints. The host only copies pixels to a canvas (or native window). There is no host text, no CSS for the CLI, no `<pre>` terminal.

---

## Framebuffer geometry

| Property | Web default | Kernel max |
|----------|-------------|------------|
| Size | Viewport CSS box × `devicePixelRatio` (via Host ABI) | 1920×1080 |
| Format | RGBA8 | RGBA8 |
| Stride | `width * 4` | same |
| Color in SoftASM | `0xAARRGGBB` in regs; FB stores R,G,B,A bytes |

`softui_start(w, h)` sets the initial size. Hosts call `softui_resize(w, h)` when the display viewport changes; SoftUI keeps session/stage and reflows GUI + console. SoftShell console computes columns/rows from glyph cell size.

Exports: `softui_fb_ptr`, `softui_fb_width`, `softui_fb_height`, `softui_fb_stride`, `softui_resize`.

---

## Who draws what

| Layer | Draws |
|-------|-------|
| SoftShell console (`console.zig`) | Glyph cells, cursor blink, scrollback |
| SoftShell demos | Fullscreen effects via `donut`/`plasma`/… Zig modules |
| SoftASM `svc fb_*` | Rect fills / demo hooks into the same FB |
| SoftShell `fb fill` / `fb clear` | Direct rectangle poke |
| `txedit` | Editor chrome + text lines as glyphs |
| Host | **Never** glyphs — only blit |

---

## Glyph console

SoftUI ships a tiny bitmap font (`font.zig`). Console:

- Cell width = glyph width; row pitch **16 px** (padding around glyph height)
- Up to 240×120 cells (clamped to FB)
- Scrollback in fixed line buffers
- Colors: fg / bg / cursor (`color` command); defaults near `#d7e0ea` on `#0b0e12`

Drawing path each tick (shell mode): clear/paint dirty lines → glyphs → cursor.

Independence rule reminder: replacing SoftUI glyphs with `ctx.fillText` would make SoftUI a web app, not a guest OS.

---

## Demo renderers

Kernel modules write every pixel of the FB while SoftShell mode is a demo:

| Command | Module | Idea |
|---------|--------|------|
| `donut` | `donut.zig` | Spinning ASCII-ish torus lighting |
| `plasma` | `plasma.zig` | Classic plasma field |
| `stars` | `stars.zig` | Starfield |
| `cube` | `cube.zig` | Rotating shaded cube |
| `fire` | `fire.zig` | Fire effect |

Any key exits to SoftShell. SoftASM can call the same effects through `svc` 13–17.

---

## SoftASM graphics

```text
svc 11        ; fb_size → r0,r1
svc 10        ; fb_fill x y w h color
svc 12        ; get_frame for animation
svc 14        ; fb_plasma phase
```

Colors are `0xAARRGGBB` in registers; kernel expands into RGBA bytes in the buffer.

---

## Present path (Web)

```
softui_tick
  → shell.draw → pixels in WASM memory
  → host_present()
JS:
  → Uint8Array view at softui_fb_ptr
  → imageData.set → putImageData
```

SoftUI does not wait for vsync acknowledgment; the browser rAF loop is the pacing source.

---

## Design constraints

1. **One composition** for promotional hosts later; SoftShell itself is a working surface, not a marketing landing page.
2. **No host overlays** on SoftUI content (no HTML badges on the canvas).
3. Future SoftUI GPU / accel still writes SoftUI-owned pixels — never host widgets for SoftUI chrome.

---

## Related

- [kernel.md](kernel.md) · [softshell-guide.md](softshell-guide.md) · [softasm-guide.md](softasm-guide.md) · [host-abi-guide.md](host-abi-guide.md)
