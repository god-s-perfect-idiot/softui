# Boot path

This guide walks SoftUI from “host start” to a session (GUI desktop or SoftShell), naming every Host ABI call and kernel state transition.

---

## Actors

| Actor | Code |
|-------|------|
| Host bootstrap | e.g. `bootstrap/web/softui.js` (any host implements the same ABI) |
| SoftUI kernel | `runtime/src/main.zig` |
| SoftUI bootloader / desktop | `runtime/src/gui.zig` |
| SoftFS | `runtime/src/softfs.zig` |
| SoftShell | `runtime/src/softshell.zig` |

---

## Sequence

```
  Host                         softui runtime
  ────                         ──────────────
  instantiate + Host ABI imports
       │
  load disk image (host policy)
  softui_alloc(len)
  copy bytes into guest memory
  softui_mount_disk(ptr, len) ──────► disk_blob filled
       │
  softui_start(w, h) ───────────────► set fb dims
                                       mount SoftFS
                                       enter SoftUI bootloader
       │
  frame loop:
    softui_push_key(...)   (host keyboard → guest queue)
    softui_tick(now_ns) ────────────► bootloader | desktop | SoftShell
                                       host_present()
    blit softui_fb_* → host surface
```

Session choice is **not** a Host ABI concern. SoftUI draws the bootloader; hosts only push keys and blit pixels.

---

## SoftUI bootloader

On `softui_start`, SoftUI shows a guest-drawn chooser:

- **GUI** (default highlight) or **CLI**
- Arrows move selection (resets the 10s timer)
- Enter confirms
- After **10 seconds** with no confirm, SoftUI enters **GUI** (timeout always means GUI)

### GUI session

- Desktop chrome with tiles (Shell, demos)
- Launch takes the full framebuffer
- Escape (empty SoftShell line / leave demo) returns to the desktop

### CLI session

- SoftShell as the root UI (same REPL as before)

---

## Host responsibilities (portable)

Every bootstrap must implement the same contract:

1. Provide `host_log`, `host_present`, `host_storage_write`
2. Mount a SoftFS blob via `softui_alloc` + `softui_mount_disk`
3. Call `softui_start(width, height)`
4. Each frame: optional `softui_push_key`, then `softui_tick(now_ns)`, then blit `softui_fb_*`

Hosts must **not** select GUI/CLI via URL query, path, argv flags wired into SoftUI, or other platform-only side channels. That would make one bootstrap diverge from another.

Web-specific details (canvas, `localStorage`, `fetch`) stay inside the Web bootstrap’s Host ABI implementation — SoftUI never observes them.

---

## Memory arenas at boot

| Arena | Size | Role |
|-------|------|------|
| Framebuffer | up to 1920×1080×4 | RGBA8 pixels |
| `disk_blob` | 2 MiB | Last mounted / packed SoftFS image |
| `alloc_arena` | 2 MiB | `softui_alloc` bump allocator |
| SoftFS heap | 512 KiB inside `Fs` | File payloads |
| Process arena | 256 KiB | SoftASM `.sox` load + stack |

---

## Related

- [persistence.md](persistence.md) — disk choice and save path
- [kernel.md](kernel.md) — what happens inside each tick
- [host-abi-guide.md](host-abi-guide.md) — full ABI glossary
- Reference: [architecture.md](../architecture.md)
