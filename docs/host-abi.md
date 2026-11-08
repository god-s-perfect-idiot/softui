# SoftUI Host ABI

Stable contract between bootstrap and SoftUI runtime. Phase 1 uses a flat WASM export/import surface (no struct pointers across the JS boundary).

**Guide:** [guides/host-abi-guide.md](guides/host-abi-guide.md) (philosophy, storage, keyboard, checklists).

## SoftUI exports (WASM)

| Symbol | Signature | Role |
|--------|-----------|------|
| `softui_start` | `(width: u32, height: u32) -> i32` | Init kernel; allocate framebuffer; return 0 on success |
| `softui_resize` | `(width: u32, height: u32) -> i32` | Change FB to host viewport size; keep session/stage |
| `softui_tick` | `(now_ns: u64) -> i32` | Run one frame; return 0 on success |
| `softui_fb_ptr` | `() -> u32` | Byte offset of RGBA8 framebuffer in WASM memory |
| `softui_fb_width` | `() -> u32` | Framebuffer width in pixels |
| `softui_fb_height` | `() -> u32` | Framebuffer height in pixels |
| `softui_fb_stride` | `() -> u32` | Bytes per row (width * 4 for Phase 1) |
| `softui_alloc` | `(size: u32) -> u32` | Allocate bytes in WASM arena; returns pointer or 0 |
| `softui_mount_disk` | `(ptr: u32, len: u32) -> i32` | Mount SoftFS blob copied into WASM memory |
| `softui_persist` | `() -> i32` | Pack live SoftFS and call `host_storage_write` |
| `softui_push_key` | `(key: u32, mods: u32) -> void` | Push keyboard event into SoftUI queue |
| `softui_push_pointer` | `(x: u32, y: u32, buttons: u32, kind: u32) -> void` | Pointer in FB coords (`kind`: 0=move, 1=down, 2=up; `buttons` bit0=primary) |

Framebuffer format: **RGBA8**, tightly packed (`stride = width * 4`). SoftUI draws all text into this buffer; host never renders glyphs.

Boot/session UX (bootloader chooser, GUI desktop, SoftShell CLI) is **SoftUI-owned**. Hosts must not select GUI vs CLI via URL query, path, env, or other platform-only side channels — that would break cross-bootstrap parity.

Executables use the **`.sox`** extension (SoftUI executable).

## Host imports (WASM → JS)

Phase 1 imports are minimal stubs so the runtime stays freestanding-capable:

| Symbol | Signature | Role |
|--------|-----------|------|
| `host_log` | `(ptr: u32, len: u32) -> void` | Optional debug UTF-8 log (bootstrap may no-op) |
| `host_present` | `() -> void` | Notify bootstrap that the framebuffer is ready (bootstrap still blits after `tick`) |
| `host_storage_write` | `(ptr: u32, len: u32) -> void` | Persist SoftFS image bytes (Web: `localStorage`) |

## Storage / input (later)

- Input: bootstrap pushes events via `softui_push_event` before `tick`
- Network: opaque socket IDs

Web bootstrap loads `localStorage['softui.sofs']` when present, otherwise `init.sofs`. Clear that key to restore the factory image.

C header mirror: [`../host-abi/host_abi.h`](../host-abi/host_abi.h).
