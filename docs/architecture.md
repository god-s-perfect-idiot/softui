# SoftUI Architecture

SoftUI is a portable guest operating system. It owns its kernel, SoftASM userspace, SoftFS, SoftShell CLI, and framebuffer renderer. It never calls host OS or browser APIs directly.

A thin bootstrap on each platform implements a fixed **Host ABI**. The first host is the Web bootstrap (`bootstrap/web`), which loads `softui.wasm` and blits SoftUI's RGBA8 framebuffer to a canvas.

## Layers

```
Browser / host process
  └── Bootstrap (JS) — Host ABI only (blit + keyboard + disk blob)
        └── softui runtime (Zig → WASM)
              ├── Kernel (tick, SoftFS, SoftASM VM)
              ├── SoftShell CLI (default boot)
              ├── SoftUI text console (glyph framebuffer)
              └── Software / SoftUI GPU framebuffer
```

## Boot path (Web)

1. Localhost server serves `index.html`, `softui.js`, `softui.wasm`, `init.sofs`.
2. JS instantiates WASM, mounts SoftFS, optional `softui_set_boot_mode`.
3. `softui_start` → **SoftShell CLI** (default).
4. Each frame: JS may push keys; `softui_tick` runs SoftShell + draws SoftUI framebuffer.
5. JS copies RGBA to canvas only — no host text/UI widgets.

## Independence rule

SoftUI must not use DOM text, host fonts, Win32, POSIX UI, etc. See [host-abi.md](host-abi.md).

## Phase status

- **Phase 1:** WASM tick + Host ABI framebuffer
- **Phase 2:** SoftASM VM, `.sox`, SoftFS
- **Phase 3:** SoftShell CLI boot, SoftUI text, keyboard Host ABI

ISA: [isa.md](isa.md). SoftFS: [softfs.md](softfs.md). SoftShell: [softshell.md](softshell.md).
