# SoftUI kernel / runtime

The SoftUI “kernel” is the Zig freestanding runtime in `runtime/src/main.zig` plus supporting modules. It is not a Unix clone: there is one address space (WASM linear memory), cooperative SoftASM bursts, and a SoftShell that is part of the kernel image rather than a separate userspace process.

---

## Responsibilities

| Concern | Module / location |
|---------|-------------------|
| Exports / Host ABI | `main.zig` |
| Framebuffer fill helpers | `main.zig` |
| SoftFS instance + persist | `main.zig` + `softfs.zig` |
| SoftShell wiring | `main.zig` + `softshell.zig` |
| SoftASM load/run | `softasm_vm.zig` |
| Keyboard queue | `input.zig` |
| Glyph console | `console.zig` + `font.zig` |
| Demo renderers | `donut.zig`, `plasma.zig`, `stars.zig`, `cube.zig`, `fire.zig` |
| Text editor | `txedit.zig` (driven by SoftShell) |

---

## The tick

`softui_tick(now_ns)` is SoftUI’s heartbeat:

1. Record boot timestamp on first tick
2. Increment `frame_count`
3. Ensure SoftFS mounted / attached to SoftShell
4. `shell.tick(frame)` — drain input, blink cursor / editor
5. `shell.draw(fb, …)` — paint console, txedit, or fullscreen demo
6. `host_present()` on wasm32

Nothing preemptive runs between ticks. SoftASM `run` executes a **budget** of instructions (200 000) synchronously inside the SoftShell command that invoked it, then returns to the CLI.

---

## SoftShell as kernel surface

SoftShell is compiled into SoftUI. It can:

- Mutate SoftFS directly (pointers into kernel `Fs`)
- Call demo renderers
- Fill rectangles on the FB
- Report `kinfo` / `mem` / `ticks` / `svc`
- Request persist via `on_fs_sync`

This is intentional for Phase 3: SoftShell is both the UX and a kernel debugger console. Future multi-process SoftASM may move more logic into `.sox` files; SoftShell’s `caps` catalog tracks that roadmap.

---

## Memory model

```
WASM linear memory
├── Zig globals (framebuffer, disk_blob, Fs, shell, arenas, …)
├── SoftFS node table + 512 KiB heap
├── disk_blob[2 MiB]          # packed SoftFS image cache
├── alloc_arena[2 MiB]        # softui_alloc bump
└── process_arena[256 KiB]    # one SoftASM image + stack
```

There is no page table, no mmap, no malloc across the Host ABI (except SoftUI’s own bump `softui_alloc` for host→guest copies). SoftFS allocates file bytes with a bump heap inside `Fs` (no free coalescing — deletes mark nodes unused but do not reclaim heap holes until remount/pack+mount cycle rebuilds from packed data).

**Implication:** many create/rewrite cycles without remount can exhaust `DATA_HEAP` even if logical file sizes are small. `df` shows `heap_used`. A persist + remount (or reboot of the whole SoftUI page after sync) rebuilds a compact heap from packed file contents.

---

## Input path

```
Browser keydown
  → softui.js mapKey / modsOf
  → softui_push_key(key, mods)
  → input.push (ring, cap 64, drop oldest)
  → softui_tick → SoftShell.handleKey / txedit.handleKey
```

Keys are SoftUI codes (ASCII or `0x100+` specials). Modifiers: bit0 shift, bit1 ctrl, bit2 alt, bit3 meta. SoftShell uses Ctrl for txedit (`^O` save, `^X` exit).

---

## SoftASM integration

`run <file.sox>`:

1. SoftFS `find` / resolve file bytes
2. `Vm.load` into `process_arena`
3. Install `KernelHooks` (write→`host_log`, fb_*, demos)
4. `runBudget(200_000)`
5. Print `ran <name>`

Long-running SoftASM that `yield`s each frame is **planned**; today demos are either SoftShell modes (kernel renderers) or short SoftASM bursts.

---

## Persistence hook

At CLI start:

```zig
shell.on_fs_sync = shellFsSync; // → persistFs()
```

`persistFs` packs SoftFS into `disk_blob` and calls `host_storage_write`. See [persistence.md](persistence.md).

---

## Kernel-visible SoftShell commands

| Command | Shows / does |
|---------|----------------|
| `kinfo` / `sysinfo` | frame, boot_ns, fb size, session (0=CLI 1=GUI), alloc, disk, process arena |
| `mem` | same memory summary |
| `ticks` | frame counter |
| `svc` | SoftASM syscall list (documentation in shell) |
| `fb clear` / `fb fill` | poke framebuffer |
| `reboot` | reinit SoftShell session (FS kept) |
| `capabilities` | shipped vs planned |

---

## Panic

`pub fn panic` logs via `host_log` and spins. There is no host alert dialog — check the browser console.

---

## Related

- [boot.md](boot.md) · [softshell-guide.md](softshell-guide.md) · [softasm-guide.md](softasm-guide.md)
- Reference: [architecture.md](../architecture.md) · [softshell.md](../softshell.md) kernel section
