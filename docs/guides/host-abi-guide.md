# Host ABI guide

The Host ABI is the **only** contract between SoftUI and the outside world. SoftUI is freestanding Zig → WASM; the bootstrap (JS today) implements imports and calls exports. No DOM text, no host fonts, no direct `localStorage` from Zig — only this surface.

Compact symbol table: [host-abi.md](../host-abi.md). C header: [`host-abi/host_abi.h`](../../host-abi/host_abi.h).

---

## Philosophy

1. **Flat integers** — pointers are `u32` offsets into WASM memory; no struct crossing.
2. **SoftUI owns pixels** — host blits an RGBA8 buffer SoftUI filled.
3. **SoftUI owns files** — host stores opaque SoftFS blobs SoftUI packed.
4. **Host owns devices** — keyboard, canvas size, durable media, clocks.

A new host (native GLFW, embedded LCD, …) reimplements the same imports/exports without changing SoftShell or SoftASM apps.

---

## SoftUI → host (imports)

| Import | SoftUI uses it to… | Web implementation |
|--------|--------------------|--------------------|
| `host_log(ptr, len)` | Debug UTF-8 (kernel + SoftASM `write`) | `console.log` |
| `host_present()` | Signal FB ready after tick | no-op (JS blits anyway) |
| `host_storage_write(ptr, len)` | Persist SoftFS image | base64 → `localStorage['softui.sofs']` |
| `host_time_wall_ms()` | Wall clock (Clock demo) | `Date.now()` as `u64` |
| `host_time_tz_min()` | Local TZ minutes east of UTC | `-getTimezoneOffset()` |
| `host_audio_queue(...)` | Queue PCM s16le (Music) | Web Audio `AudioBufferSourceNode` |
| `host_audio_stop()` | Stop audio | close `AudioContext` |
| `host_image_decode(...)` | PNG/JPEG → RGBA8 | `createImageBitmap` (async; `-2` pending) |
| `host_sui_paint(...)` | Paint `.sui` into SoftUI FB | vendored suigui SDK → OffscreenCanvas |

Imports are declared `extern` in `main.zig` and provided under WASM module `env` by `softui.js`.

---

## Host → SoftUI (exports)

### Lifecycle

| Export | When |
|--------|------|
| `softui_mount_disk(ptr, len)` | After copying disk bytes into WASM |
| `softui_start(w, h)` | Once; allocates logical FB, mounts SoftFS, enters SoftUI bootloader |
| `softui_resize(w, h)` | When host viewport changes; updates FB geometry, keeps session |
| `softui_tick(now_ns)` | Every animation frame |
| `softui_persist()` | Unload / explicit flush |

Session choice (GUI vs CLI) is SoftUI-owned via the guest bootloader. Do not drive it from host URL/query/env.

### Framebuffer query

| Export | Returns |
|--------|---------|
| `softui_fb_ptr` | Byte offset of RGBA8 buffer |
| `softui_fb_width` / `_height` / `_stride` | Geometry (`stride = width * 4`) |

Host copies `[ptr, ptr + stride*height)` into an `ImageData` (or native texture).

### Memory / input

| Export | Role |
|--------|------|
| `softui_alloc(size)` | Bump allocate in SoftUI arena (8-byte aligned); `0` on OOM |
| `softui_push_key(key, mods)` | Enqueue keyboard event |
| `softui_push_pointer(x, y, buttons, kind)` | Pointer in FB coords (GUI hit-test + SoftUI OSK); `kind` 0=move/1=down/2=up |

Web hosts should size SoftUI from `clientWidth/Height × devicePixelRatio` (clamped to SoftUI max) and call `softui_resize` on viewport changes. SoftUI chrome is device-agnostic: wrappers only translate keyboard/pointer and size — no host HTML overlays for SoftUI UX.

Typical disk mount:

```text
ptr = softui_alloc(len)
copy host bytes → memory[ptr..]
softui_mount_disk(ptr, len)
```

---

## Keyboard encoding

Bootstrap maps browser `KeyboardEvent` → SoftUI codes:

| Key | Code |
|-----|------|
| Printable | Unicode / ASCII code unit |
| Enter / BS / Tab / Esc | 13 / 8 / 9 / 27 |
| Arrows | `0x100`–`0x103` |
| Home / End / Delete | `0x104`–`0x106` |

Mods bitmask: shift=1, ctrl=2, alt=4, meta=8.

SoftUI does not see raw DOM events — only these integers.

---

## Storage contract

```
SoftUI pack(SoftFS) → bytes in disk_blob
host_storage_write(ptr, len)
        │
        ▼
   host media (localStorage / file / block)
        │
        ▼  (next boot)
   softui_mount_disk → SoftUI mount
```

Semantics:

- SoftUI may call `host_storage_write` often (after each FS mutation).
- Host should replace the previous SoftFS image atomically if possible.
- Host must not interpret SoftFS internals (except optional magic check).
- SoftUI must tolerate hosts that no-op storage (session-only FS).

Details: [persistence.md](persistence.md).

---

## Frame present contract

After SoftUI fills the FB during `tick`, it calls `host_present()`. The Web bootstrap currently ignores it and always blits after `tick` returns — safe duplication. A native host might vsync on `host_present` only.

Framebuffer format: **RGBA8**, tightly packed, origin top-left. SoftUI draws glyphs with its own font bitmap (`font.zig`).

---

## Adding a Host ABI feature (checklist)

1. Declare in `host-abi/host_abi.h`
2. Document in `docs/host-abi.md` **and** this guide
3. `extern` or `export` in `runtime/src/main.zig`
4. Implement in `bootstrap/web/softui.js` (and future hosts)
5. If it affects SoftFS / boot, update [persistence.md](persistence.md) / [boot.md](boot.md)

Never reach for DOM APIs from Zig “just this once” — that breaks the guest OS model.

---

## Related

- [boot.md](boot.md) · [persistence.md](persistence.md) · [framebuffer-guide.md](framebuffer-guide.md)
- Reference: [host-abi.md](../host-abi.md)
