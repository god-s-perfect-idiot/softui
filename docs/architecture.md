# SoftUI Architecture

SoftUI is a portable guest operating system. It owns its kernel, SoftASM userspace, SoftFS, SoftShell CLI, and framebuffer renderer. It never calls host OS or browser APIs directly.

A thin bootstrap on each platform implements a fixed **Host ABI**. The first host is the Web bootstrap (`bootstrap/web`), which loads `softui.wasm` and blits SoftUI's RGBA8 framebuffer to a canvas.

**Elaborate guides:** start at [guides/overview.md](guides/overview.md). Full index: [README.md](README.md).

## Layers

```
Browser / host process
  └── Bootstrap (JS) — Host ABI only (blit + keyboard + disk blob)
        └── softui runtime (Zig → WASM)
              ├── Kernel (tick, SoftFS, SoftASM VM)
              ├── SoftUI bootloader + GUI desktop
              ├── SoftShell CLI (chooser / Shell tile)
              ├── SoftUI text console (glyph framebuffer)
              └── Software / SoftUI GPU framebuffer
```

## Boot path (Web)

1. Localhost server serves `index.html`, `softui.js`, `softui.wasm`, `init.sofs`.
2. JS instantiates WASM, mounts SoftFS from `localStorage` (if saved) or `init.sofs`.
3. `softui_start` → **SoftUI bootloader** (GUI/CLI chooser; GUI default; 10s timeout → GUI).
4. Each frame: host may push keys; `softui_tick` runs bootloader / desktop / SoftShell and draws SoftUI framebuffer.
5. FS mutations pack SoftFS v2 and call `host_storage_write` (Web: `localStorage`).
6. JS copies RGBA to canvas only — no host text/UI widgets.

Deep dive: [guides/boot.md](guides/boot.md) · [guides/persistence.md](guides/persistence.md).

## Independence rule

SoftUI must not use DOM text, host fonts, Win32, POSIX UI, etc. See [host-abi.md](host-abi.md) and [guides/host-abi-guide.md](guides/host-abi-guide.md).

## Phase status

- **Phase 1:** WASM tick + Host ABI framebuffer
- **Phase 2:** SoftASM VM, `.sox`, SoftFS
- **Phase 3:** SoftShell CLI, SoftUI text, keyboard Host ABI (+ SoftFS persistence)
- **Phase 4:** SoftUI bootloader + GUI desktop chrome (viewport auto-scale, dual keyboard/pointer UX; windowing still deferred)

## Reference map

| Topic | Reference | Guide |
|-------|-----------|-------|
| Host ABI | [host-abi.md](host-abi.md) | [guides/host-abi-guide.md](guides/host-abi-guide.md) |
| SoftASM ISA | [isa.md](isa.md) | [guides/softasm-guide.md](guides/softasm-guide.md) |
| SoftFS | [softfs.md](softfs.md) | [guides/softfs-guide.md](guides/softfs-guide.md) · [guides/persistence.md](guides/persistence.md) |
| SoftShell caps | [softshell.md](softshell.md) | [guides/softshell-guide.md](guides/softshell-guide.md) |
| Kernel / FB | — | [guides/kernel.md](guides/kernel.md) · [guides/framebuffer-guide.md](guides/framebuffer-guide.md) |
