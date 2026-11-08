# SoftFS guide

SoftFS is SoftUI’s guest filesystem: a mutable tree in SoftUI RAM, initialized from a packed `.sofs` image, and optionally packed back out for host persistence.

Short reference: [softfs.md](../softfs.md). Persistence deep dive: [persistence.md](persistence.md). On-disk layouts: [isa.md](../isa.md).

---

## Design goals

1. **No host paths** — SoftUI never `open()`s the browser filesystem; only blobs via Host ABI.
2. **Small & explicit** — fixed node table and heap; failures are `NoSpace` / `Exists`, not silent growth.
3. **Shell-friendly** — absolute/relative paths, `.` / `..`, directories, CRUD commands.
4. **Persistable** — `pack` produces SoftFS v2 that round-trips the tree.

---

## Runtime structure

```zig
Fs {
  nodes: [128]Node,   // index 0 = ROOT "/"
  heap:  [512 KiB]u8, // file bytes
  heap_used: u32,
  cwd: u16,           // node index
  node_count: u16,
}
```

Each `Node`:

| Field | Meaning |
|-------|---------|
| `name` / `name_len` | Basename (not full path), ≤ 31 chars |
| `kind` | `file` or `dir` |
| `parent` | Parent node index (`ROOT` for top-level) |
| `used` | Slot occupied |
| `data_off` / `data_len` / `data_cap` | Heap span for files |

Directories ignore data fields. Root is always node `0`, name `"/"`, parent self.

---

## Paths

`resolve(path)`:

- Empty → cwd
- Leading `/` → start at root; else start at cwd
- Components split on `/`; `.` skipped; `..` walks parent
- Missing component → `null`

`resolveParent(path)` returns `{ parent_idx, basename }` for create/rename targets.

Examples SoftShell accepts:

```text
/donut.sox
notes
./a/../b
/home/sam/todo
```

Nested paths require parent directories to exist (`mkdir` first) unless a future `mkdir -p` lands (not shipped).

---

## Operations (API)

| API | SoftShell | Notes |
|-----|-----------|-------|
| `createFile` | `touch`, `write`, `cp`, txedit | Fails if name exists |
| `mkdir` | `mkdir` | Empty dir |
| `writeFile` | `write`, `append`, txedit | Grows heap if capacity exceeded |
| `unlink` | `rm`, `rmdir` | Dirs must be empty; not recursive |
| `rename` | `mv` | Prevents dir cycles |
| `copyFile` | `cp` | File only; new heap copy |
| `fileData` / `find` | `cat`, `run`, … | `find` resolves path → bytes |
| `df` | `df` | nodes + heap usage |
| `cwdPath` | prompt / `pwd` | Formats absolute path |
| `mount` / `pack` | boot / persist | See persistence guide |

---

## Image formats

### v1 — factory (`init.sofs`)

Built by `tools/pack_sofs.zig` during `zig build sysroot`:

```
pack_sofs bootstrap/web/init.sofs \
  donut.sox=… plasma.sox=… stars.sox=… cube.sox=… fire.sox=…
```

Only **flat files** under `/`. Sufficient for shipping demos.

### v2 — live pack

Produced whenever SoftUI persists. Includes directories (including empty ones) with parent indices. Mount requires BFS parent-before-child order (guaranteed by `pack`).

After the first save, Web boots v2 forever until `localStorage` is cleared.

---

## Limits and sharp edges

| Limit | Value | Effect |
|-------|-------|--------|
| Nodes | 128 | Includes root; ~127 user entries |
| Name length | 31 | Basename only |
| File heap | 512 KiB | Shared; no compaction until remount from pack |
| Disk arena | 2 MiB | Max packed image SoftUI can hold |
| `rm -r` | planned | Must `rm` files then `rmdir` |

`writeFile` that outgrows `data_cap` allocates a **new** heap region and leaves the old region orphaned until remount — expected with the bump allocator.

---

## SoftASM and SoftFS

SoftASM does not yet have open/read/write syscalls into SoftFS. SoftShell `run` loads a whole file into the process arena. Future syscalls would go through kernel hooks into the same `Fs` instance.

---

## Inspecting SoftFS from SoftShell

```text
pwd
ls
tree
stat donut.sox
cat notes
hexdump notes
wc notes
df
sync
```

`stat` prints kind, node index, parent, size or child count.

---

## Related

- [persistence.md](persistence.md) — save/load pipeline
- [softshell-guide.md](softshell-guide.md) — commands that mutate SoftFS
- Reference: [isa.md](../isa.md) · [softfs.md](../softfs.md)
