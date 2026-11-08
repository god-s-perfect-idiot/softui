# SoftUI

Portable guest OS. Zig kernel/runtime compiles to WASM; a tiny Web bootstrap implements Host ABI and blits SoftUI's framebuffer to a canvas. Boot opens a SoftUI **bootloader** (GUI default, or SoftShell CLI); all pixels are SoftUI-drawn — no host UI.

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
- `sysroot/` — SoftASM demo sources (`.soft`)
- `bootstrap/web/` — Host ABI JS + canvas + `init.sofs`
- `tools/` — `serve.zig`, `pack_sofs.zig`
- `host-abi/` — C ABI header
- `docs/` — [OS guides + reference](docs/README.md)

SoftUI never calls browser/OS APIs except through Host ABI. Userspace binaries are **`.sox`**. SoftFS edits persist via Host ABI (`localStorage` on Web) — see [docs/guides/persistence.md](docs/guides/persistence.md).

## Documentation

| Start | Link |
|-------|------|
| Docs index | [docs/README.md](docs/README.md) |
| OS overview | [docs/guides/overview.md](docs/guides/overview.md) |
| Filesystem persistence | [docs/guides/persistence.md](docs/guides/persistence.md) |
| SoftShell caps | [docs/softshell.md](docs/softshell.md) |