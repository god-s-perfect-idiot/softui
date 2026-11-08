# SoftASM guide

SoftASM is SoftUI’s portable userspace: a small bytecode ISA, an assembler that emits `.sox` executables, and an interpreter VM inside the SoftUI kernel. SoftASM programs never execute host CPU opcodes and never call browser APIs — only SoftUI syscalls (`svc`).

Opcode tables: [isa.md](../isa.md). Shared constants: `softasm/isa.zig`.

---

## Why SoftASM exists

SoftUI must stay host-independent. Shipping “native WASM for each app” would couple apps to the host CPU/ABI. SoftASM gives:

- One binary format (`.sox`) on SoftFS across hosts
- A stable syscall surface into SoftUI (framebuffer, log, demos)
- A place for future scheduling, debugging, and multi-process work

---

## Toolchain

```text
sysroot/donut.soft   ──softasm──►  bootstrap/web/donut.sox
                                      │
                                      ▼
                               pack_sofs → init.sofs
```

```bash
zig build sysroot   # assemble demos + pack init.sofs
# or
zig-out/bin/softasm sysroot/donut.soft bootstrap/web/donut.sox
```

Assembler entry: `softasm/asm_main.zig`.

---

## Machine model

| Piece | Detail |
|-------|--------|
| GPRs | `r0`–`r31` (32-bit). `r31` = SP, `r30` = LR by convention |
| PC | Byte offset into process image |
| Memory | Linear arena: `[code][rodata][bss…][…stack↑]` |
| Flags | None — compares use GPRs + `beq`/`bne` |
| Encoding | Fixed 4-byte little-endian instructions |

Process arena size: **256 KiB** (`Vm.PROCESS_ARENA`), stack region **16 KiB** at the high end. SP starts at `arena.len`.

---

## Instruction groups (conceptual)

1. **ALU** — `add` `sub` `mul` `and` `or` `xor` `shl` `shr`
2. **Move / immediates** — `mov` `li` `lih` (build 32-bit constants with `li`+`lih`)
3. **Memory** — `ld`/`st` (32-bit), `ldb`/`stb` (8-bit); address = base reg + index reg
4. **Control** — `b` `beq` `bne` `jal` `ret`
5. **Syscall** — `svc imm8`

Branch offsets are relative to the **next** instruction (PC already advanced by 4 before applying offset). Full table: [isa.md](../isa.md).

---

## Syscalls

SoftASM traps into SoftUI via `svc`. Kernel hooks in `main.zig` implement them:

| Code | Name | Typical use |
|------|------|-------------|
| 1 | `write` | Debug UTF-8 to `host_log` (fd 1) |
| 2 | `exit` | Halt process |
| 3 | `yield` | Cooperative return (future per-frame loops) |
| 10 | `fb_fill` | Rectangle `0xAARRGGBB` |
| 11 | `fb_size` | Width/height |
| 12 | `get_frame` | Animation phase |
| 13–17 | demo fills | Donut / plasma / stars / cube / fire |

There are **no SoftFS open/read/write syscalls yet**. SoftShell loads whole `.sox` files for `run`.

---

## `.sox` file format

```
offset 0:  'S''O''X''\0'
       4:  version u16 (=1)
       6:  flags u16
       8:  entry u32          # payload-relative entry PC
      12:  code_size u32
      16:  rodata_size u32
      20:  bss_size u32
      24:  reserved u32
      28:  code bytes
       …  rodata bytes
```

`Vm.load` copies code+rodata into the arena, zeroes BSS, sets PC=entry, SP=top.

---

## Running from SoftShell

```text
ls
run plasma.sox
```

Flow:

1. Resolve file on SoftFS
2. `Vm.load(sox, process_arena, hooks)`
3. `runBudget(200_000)` — stops on exit, fault, yield, or budget
4. SoftShell prints `ran plasma.sox`

Faults set VM status and a reason string; budget exhaustion leaves the process unfinished (no resume UI yet).

---

## Writing a tiny program (sketch)

```asm
.text
.entry start

start:
    li r0, 1          ; fd
    li r1, msg
    li r2, 5
    svc 1             ; write
    li r0, 0
    svc 2             ; exit

.rodata
msg: .ascii "hello"
```

Assemble to `.sox`, place on SoftFS (`pack_sofs` or SoftShell `cp` once you have bytes), then `run`.

---

## SoftASM vs SoftShell demos

| Path | Who renders |
|------|-------------|
| SoftShell `plasma` | Kernel Zig (`plasma.zig`) in SoftShell mode |
| SoftShell `run plasma.sox` | SoftASM calling `svc` demo hooks |

Same visuals, different stacks — useful for testing both the CLI modes and the syscall path.

---

## Roadmap (from SoftShell caps)

- Per-frame SoftASM with `yield` handoff
- SoftFS file syscalls
- Assembler / debugger inside SoftShell
- Multi-process `spawn` / `ps`

---

## Related

- [kernel.md](kernel.md) · [softshell-guide.md](softshell-guide.md) · [framebuffer-guide.md](framebuffer-guide.md)
- Reference: [isa.md](../isa.md)
