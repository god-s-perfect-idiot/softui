# SoftASM ISA (v0)

SoftASM is SoftUI's portable userspace bytecode. SoftUI interprets it; apps never execute host CPU instructions or host syscalls.

**Guide:** [guides/softasm-guide.md](guides/softasm-guide.md). SoftFS image layouts below pair with [guides/persistence.md](guides/persistence.md).

## Machine model

- 32 GPRs `r0`–`r31` (32-bit)
- `pc` — program counter (byte offset into process image)
- `sp` is `r31` by convention; `lr` is `r30` for `jal`/`ret`
- Linear process address space: loaded `.sox` image + BSS + stack
- Compare results go to a GPR (no flags register)

## Instruction encoding

All instructions are **4 bytes, little-endian**:

| Bits | Field |
|------|-------|
| 31–24 | opcode |
| 23–16 | A (usually `rd` or `rs1`) |
| 15–8 | B (usually `rs1`/`rs2` or imm hi) |
| 7–0 | C (usually `rs2` or imm lo) |

### Opcodes

| Op | Mnemonic | Form | Meaning |
|----|----------|------|---------|
| 0x01 | `add` | A=rd B=rs1 C=rs2 | rd = rs1 + rs2 |
| 0x02 | `sub` | | rd = rs1 - rs2 |
| 0x03 | `mul` | | rd = rs1 * rs2 |
| 0x04 | `and` | | rd = rs1 & rs2 |
| 0x05 | `or` | | rd = rs1 \| rs2 |
| 0x06 | `xor` | | rd = rs1 ^ rs2 |
| 0x07 | `shl` | | rd = rs1 << (rs2 & 31) |
| 0x08 | `shr` | | rd = rs1 >> (rs2 & 31) |
| 0x10 | `mov` | A=rd B=rs1 | rd = rs1 |
| 0x11 | `li` | A=rd, imm16=B<<8\|C | rd = imm16 (zero-extended) |
| 0x16 | `lih` | A=rd, imm16 | rd = imm16 << 16 |
| 0x12 | `ld` | A=rd B=base C=idx | rd = mem32[rs1+rs2] |
| 0x13 | `st` | A=rs B=base C=idx | mem32[rs1+rs2] = rd |
| 0x14 | `ldb` | | rd = mem8[rs1+rs2] |
| 0x15 | `stb` | | mem8[rs1+rs2] = rd |
| 0x20 | `b` | imm16=B<<8\|C | pc += sext(imm16) |
| 0x21 | `beq` | A=rs1 B=rs2 C=off8 | if rs1==rs2: pc += sext(off8) |
| 0x22 | `bne` | | if rs1!=rs2: pc += sext(off8) |
| 0x23 | `jal` | A=rd, imm16 | rd = pc+4; pc += sext(imm16) |
| 0x24 | `ret` | A=rs | pc = rs |
| 0x30 | `svc` | C=imm8 | SoftUI syscall |

`pc` advances by 4 after each instruction unless a branch/svc changes it. Branch offsets are relative to the **next** instruction (PC already advanced).

## Syscalls (`svc`)

Arguments in `r0`…; result in `r0` (and `r1` when noted).

| Code | Name | Args | Notes |
|------|------|------|-------|
| 1 | `write` | r0=fd, r1=ptr, r2=len | fd 1 → kernel debug log |
| 2 | `exit` | r0=code | halt process |
| 3 | `yield` | | return to kernel until next tick |
| 10 | `fb_fill` | r0=x, r1=y, r2=w, r3=h, r4=color | color `0xAARRGGBB` |
| 11 | `fb_size` | | r0=width, r1=height |
| 12 | `get_frame` | | r0=frame_count |
| 13 | `fb_donut` | r0=phase_a, r1=phase_b | Render spinning torus (mod 1024 = one turn) |
| 14 | `fb_plasma` | r0=phase | Classic plasma color field (mod 1024) |
| 15 | `fb_stars` | r0=phase | 3D starfield travel |
| 16 | `fb_cube` | r0=phase | Rotating shaded cube (mod 1024 = one turn) |
| 17 | `fb_fire` | r0=phase | Doom-style fire |

## Artifact: `.sox`

SoftUI executable (little-endian):

| Offset | Field |
|--------|-------|
| 0 | magic `SOX\0` |
| 4 | version `u16` (=1) |
| 6 | flags `u16` |
| 8 | entry `u32` (byte offset from start of image payload) |
| 12 | code_size `u32` |
| 16 | rodata_size `u32` |
| 20 | bss_size `u32` |
| 24 | reserved `u32` |
| 28 | code bytes |
| 28+code | rodata bytes |

Process image layout after load: `[code][rodata][bss…]` with stack at the high end of the process arena.

## Artifact: `.sofs`

SoftUI filesystem image.

### v1 (flat, factory `init.sofs`)

| Field | Meaning |
|-------|---------|
| magic `SOFS` | |
| version `u16` (=1) | |
| file_count `u16` | |
| entries[file_count] | name[32], offset `u32`, size `u32` (40 bytes) |
| data… | file payloads; offset is from start of data region |

### v2 (tree, packed by SoftFS `pack`)

| Field | Meaning |
|-------|---------|
| magic `SOFS` | |
| version `u16` (=2) | |
| node_count `u16` | |
| entries[node_count] | name[32], parent `u16` (`0xFFFF` = root), kind `u8` (0=file,1=dir), pad `u8`, offset `u32`, size `u32` (44 bytes) |
| data… | file payloads; offset is from start of data region |

Entries are BFS-ordered so parents appear before children.
