# SoftUI OS overview

SoftUI is a **guest operating system** that runs inside a host process. Today the host is a web page; tomorrow it could be a native window. SoftUI always owns the same things: kernel tick, SoftFS, SoftASM VM, SoftShell, and every pixel of its framebuffer.

This guide is the map of the system. Deep dives live in sibling guides.

---

## What SoftUI is

| SoftUI owns | Meaning |
|-------------|---------|
| Kernel / runtime | Zig freestanding code compiled to `softui.wasm` |
| SoftFS | In-memory filesystem mounted from a disk blob |
| SoftASM | Portable userspace bytecode + interpreter VM |
| SoftShell | Default CLI; text drawn as SoftUI glyphs |
| Framebuffer | RGBA8 pixel buffer SoftUI fills every tick |

| SoftUI does **not** own | Handled by |
|-------------------------|------------|
| Window / canvas | Host bootstrap |
| Real keyboard hardware | Host maps keys → `softui_push_key` |
| Durable disk media | Host stores SoftFS bytes (`localStorage` on Web) |
| Host CPU instructions for apps | SoftASM only — no JIT of host machine code |

---

## The independence rule

SoftUI must never:

- Draw text with DOM / Canvas `fillText` / host fonts
- Open host filesystem paths directly from the kernel
- Call Win32 / POSIX UI APIs

All host contact goes through the **Host ABI**: a small set of WASM imports SoftUI calls, and WASM exports the bootstrap calls. See [host-abi-guide.md](host-abi-guide.md).

If you can delete the host UI chrome and SoftUI still looks like SoftUI (same glyphs, same CLI, same files), the rule is holding.

---

## Layer cake

```
┌─────────────────────────────────────────────────────────┐
│  Browser (or future native host)                        │
│    canvas blit · keyboard · localStorage / disk file    │
└──────────────────────────┬──────────────────────────────┘
                           │ Host ABI
┌──────────────────────────▼──────────────────────────────┐
│  softui.wasm  (Zig freestanding runtime)                │
│  ┌─────────────┐  ┌──────────┐  ┌────────────────────┐  │
│  │ SoftShell   │  │ SoftFS   │  │ SoftASM VM         │  │
│  │ + Console   │◄─┤ tree+heap│◄─┤ .sox processes     │  │
│  └──────┬──────┘  └────▲─────┘  └─────────▲──────────┘  │
│         │              │ pack/mount       │ load/run    │
│         │         disk_blob arena         │             │
│         ▼              │                  │             │
│  RGBA8 framebuffer ◄───┴──────────────────┘             │
└─────────────────────────────────────────────────────────┘
```

Reading tip: SoftShell and SoftASM never talk to the browser. They mutate SoftFS / pixels; the kernel packs SoftFS and asks the host to store bytes.

---

## Mental model for each subsystem

### Kernel (`runtime/src/main.zig`)

One long-lived “machine”: framebuffer, arenas, SoftFS instance, SoftShell, SoftASM VM slot. Each animation frame the host calls `softui_tick`; SoftShell drains the keyboard queue, updates demos/editor, and redraws glyphs into the FB. See [kernel.md](kernel.md).

### SoftFS (`runtime/src/softfs.zig`)

A fixed-capacity tree in SoftUI RAM (128 nodes, 512 KiB file heap). Boot mounts a packed `.sofs` blob. Edits stay in RAM until **pack** writes SoftFS v2 back into the disk arena and the host persists it. See [softfs-guide.md](softfs-guide.md) and [persistence.md](persistence.md).

### SoftShell (`runtime/src/softshell.zig`)

CLI session / Shell tile UI: a REPL with cwd-aware prompt, SoftFS commands, demos, `run`, and `txedit`. It is not a host `<textarea>` — every character is a SoftUI glyph. Boot opens the SoftUI bootloader first (GUI default). See [softshell-guide.md](softshell-guide.md) and [boot.md](boot.md).

### SoftASM (`softasm/` + `runtime/src/softasm_vm.zig`)

Apps are `.sox` files on SoftFS. SoftShell `run` loads one into a process arena and interprets a budget of instructions. Syscalls (`svc`) bounce into kernel hooks (log, fb fill, demos). See [softasm-guide.md](softasm-guide.md).

### Host bootstrap (`bootstrap/web/`)

Fetches WASM + factory disk (or restored disk), mounts, starts, then forever: push keys → tick → copy FB to canvas. Implements `host_log`, `host_present`, `host_storage_write`. See [boot.md](boot.md).

---

## Artifacts you will see on disk

| Artifact | Role |
|----------|------|
| `softui.wasm` | The entire SoftUI kernel + SoftShell + VM |
| `init.sofs` | Factory SoftFS v1 image (demo `.sox` files) |
| `*.sox` | SoftASM executables (also packed into `init.sofs`) |
| `localStorage['softui.sofs']` | Web-persisted SoftFS v2 after the first save |
| `host_abi.h` | C mirror of the Host ABI |

---

## Lifecycle in one paragraph

Host loads WASM → optionally restores a saved SoftFS image → `softui_mount_disk` → `softui_start` mounts SoftFS and enters the SoftUI bootloader → each frame SoftUI draws bootloader/desktop/SoftShell → FS mutations pack SoftFS v2 and call `host_storage_write` → on next page load the saved image mounts instead of factory `init.sofs`.

---

## Related

- Reference: [architecture.md](../architecture.md)
- Capability roadmap: [softshell.md](../softshell.md)
- Next: [boot.md](boot.md) · [persistence.md](persistence.md)
