# SoftUI

Portable guest OS. Zig kernel/runtime compiles to WASM; a tiny Web bootstrap implements Host ABI and blits SoftUI's framebuffer to a canvas. Default boot is the **SoftShell CLI** (SoftUI-rendered text — no host UI).

## Quick start

```bash
zig build serve
```

Open [http://127.0.0.1:8080/](http://127.0.0.1:8080/).

```bash
zig build wasm      # softui.wasm + assemble/pack sysroot
zig build sysroot   # init.sox + init.sofs only
```

## Layout

- `runtime/` — Zig kernel, SoftASM VM, SoftFS, framebuffer
- `softasm/` — ISA + assembler (`softasm` → `.sox`)
- `sysroot/init.soft` — SoftASM source for boot `init.sox`
- `bootstrap/web/` — Host ABI JS + canvas + `init.sofs`
- `tools/` — `serve.zig`, `pack_sofs.zig`
- `host-abi/` — C ABI header
- `docs/` — architecture, Host ABI, SoftASM ISA, SoftFS

SoftUI never calls browser/OS APIs except through Host ABI. Userspace binaries are **`.sox`**.
