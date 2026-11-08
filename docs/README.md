# SoftUI documentation

SoftUI is a **portable guest operating system**: a Zig kernel/runtime compiled to WebAssembly, a SoftFS disk image, a SoftASM userspace bytecode machine, and a SoftShell CLI that draws only into SoftUI’s own framebuffer. The host (browser today) is a thin **Host ABI** shim — it never draws SoftUI text or owns SoftUI files.

This folder has two layers:

| Layer | Purpose |
|-------|---------|
| **Guides** (`guides/`) | Elaborate OS explanations — how subsystems work, why they exist, end-to-end flows |
| **Reference** (this directory) | Compact contracts — ABI tables, ISA opcodes, capability catalogs |

When behavior changes, update the matching **guide** (narrative) and **reference** (tables) together.

---

## Start here

1. [OS overview](guides/overview.md) — what SoftUI is and is not
2. [Boot path](guides/boot.md) — power-on to SoftShell prompt
3. [Filesystem persistence](guides/persistence.md) — how SoftFS survives reload

## Guides (elaborate)

| Guide | Covers |
|-------|--------|
| [overview.md](guides/overview.md) | Guest OS model, layers, independence rule, mental map |
| [boot.md](guides/boot.md) | Web boot sequence, arenas, mount, SoftShell start |
| [kernel.md](guides/kernel.md) | Tick loop, memory arenas, input queue, demos, `kinfo` |
| [persistence.md](guides/persistence.md) | SoftFS save/load, v1→v2 pack, `localStorage`, `sync` |
| [softfs-guide.md](guides/softfs-guide.md) | In-memory tree, paths, limits, image formats |
| [softshell-guide.md](guides/softshell-guide.md) | CLI, commands, txedit, chaining, FS auto-persist |
| [softasm-guide.md](guides/softasm-guide.md) | ISA, `.sox`, VM, syscalls, `run` |
| [host-abi-guide.md](guides/host-abi-guide.md) | Exports/imports, storage, keyboard, framebuffer present |
| [framebuffer-guide.md](guides/framebuffer-guide.md) | RGBA8 FB, glyph console, demos, no host text |

## Reference (compact)

| Doc | Covers |
|-----|--------|
| [architecture.md](architecture.md) | Layer diagram + phase status |
| [host-abi.md](host-abi.md) | Export/import symbol table |
| [isa.md](isa.md) | SoftASM opcodes, syscalls, `.sox` / `.sofs` layouts |
| [softfs.md](softfs.md) | SoftFS mount path (short) |
| [softshell.md](softshell.md) | Capability catalog (shipped / planned) |

C ABI mirror: [`../host-abi/host_abi.h`](../host-abi/host_abi.h).

## Maintaining these docs

- **New Host ABI symbol** → `host-abi.md` + `host-abi-guide.md` + `host_abi.h`
- **SoftFS format change** → `isa.md` (`.sofs`) + `persistence.md` + `softfs-guide.md` + `softfs.md`
- **New SoftShell command** → `softshell.md` catalog + `softshell-guide.md`
- **New SoftASM opcode/svc** → `isa.md` + `softasm-guide.md` + `softasm/isa.zig`
- **Boot / persistence behavior** → `boot.md` + `persistence.md` + `architecture.md`

Keep guides concrete: name the Zig/JS files and the Host ABI calls that implement each step.
