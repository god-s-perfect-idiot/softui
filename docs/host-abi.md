# SoftUI Host ABI

Stable contract between bootstrap and SoftUI runtime. Phase 1 uses a flat WASM export/import surface (no struct pointers across the JS boundary).

## SoftUI exports (WASM)

| Symbol | Signature | Role |
|--------|-----------|------|
| `softui_start` | `(width: u32, height: u32) -> i32` | Init kernel; allocate framebuffer; return 0 on success |
| `softui_tick` | `(now_ns: u64) -> i32` | Run one frame; return 0 on success |
| `softui_fb_ptr` | `() -> u32` | Byte offset of RGBA8 framebuffer in WASM memory |
| `softui_fb_width` | `() -> u32` | Framebuffer width in pixels |
| `softui_fb_height` | `() -> u32` | Framebuffer height in pixels |
| `softui_fb_stride` | `() -> u32` | Bytes per row (width * 4 for Phase 1) |
| `softui_alloc` | `(size: u32) -> u32` | Allocate bytes in WASM arena; returns pointer or 0 |
| `softui_mount_disk` | `(ptr: u32, len: u32) -> i32` | Mount SoftFS blob copied into WASM memory |
| `softui_push_key` | `(key: u32, mods: u32) -> void` | Push keyboard event into SoftUI queue |
| `softui_set_boot_mode` | `(mode: u32) -> void` | `0` = CLI (default), `1` = GUI (later) |

Framebuffer format: **RGBA8**, tightly packed (`stride = width * 4`). SoftUI draws all text into this buffer; host never renders glyphs.

Executables use the **`.sox`** extension (SoftUI executable).

## Host imports (WASM → JS)

Phase 1 imports are minimal stubs so the runtime stays freestanding-capable:

| Symbol | Signature | Role |
|--------|-----------|------|
| `host_log` | `(ptr: u32, len: u32) -> void` | Optional debug UTF-8 log (bootstrap may no-op) |
| `host_present` | `() -> void` | Notify bootstrap that the framebuffer is ready (bootstrap still blits after `tick`) |

## Storage / input (Phase 2+)

Reserved for later Host ABI revision:

- Block storage: `host_storage_read` / `host_storage_write` / `host_storage_sync`
- Input: bootstrap pushes events via `softui_push_event` before `tick`
- Network: opaque socket IDs

C header mirror: [`../host-abi/host_abi.h`](../host-abi/host_abi.h).
