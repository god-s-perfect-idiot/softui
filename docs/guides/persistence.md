# SoftFS persistence

**SoftFS is durable across SoftUI boots.** Edits made in SoftShell (or `txedit`) are packed into a SoftFS v2 image and handed to the host; the next boot remounts that image instead of the factory `init.sofs`.

This guide explains the full save/load path, formats, failure modes, and how to reset.

---

## Why persistence is a Host ABI concern

SoftUI is freestanding WASM. It has no direct access to browser `localStorage`, IndexedDB, or a real block device. Durable storage is therefore:

1. SoftUI **packs** the live tree into bytes in its own `disk_blob` arena.
2. SoftUI calls **`host_storage_write(ptr, len)`** (WASM import).
3. The bootstrap decides *where* those bytes live (today: `localStorage['softui.sofs']` as base64).

On boot the reverse happens in JS *before* SoftUI starts: load bytes → copy into WASM via `softui_alloc` → `softui_mount_disk` → SoftUI `mount` parses the image.

SoftUI never “opens a file on the host.” It only speaks blobs through the ABI.

---

## End-to-end: first boot vs later boots

### First visit (no saved disk)

```
fetch("./init.sofs")          # SoftFS v1 factory image
  → softui_alloc + copy
  → softui_mount_disk
  → softui_start
       → fs.mount(v1)         # flat files under /
       → SoftShell prompt
```

Factory image is built by `zig build sysroot` / `pack_sofs` and contains the demo `.sox` files (`donut.sox`, `plasma.sox`, …).

### After you change the filesystem

Any mutating SoftShell command (or successful `txedit` save, or explicit `sync`, or page `beforeunload`) runs:

```
persistFs()
  → fs.pack(disk_blob)        # SoftFS v2 tree serialization
  → disk_len = packed size
  → host_storage_write(...)   # JS → localStorage
```

### Next visit

```
localStorage['softui.sofs']   # SoftFS v2 (preferred)
  → softui_mount_disk
  → softui_start
       → fs.mount(v2)         # directories + files restored
```

If the persisted blob is missing, truncated, bad magic, or fails `mount`, the bootstrap falls back to `init.sofs` (and clears a bad `localStorage` entry).

---

## What is saved (and what is not)

| Saved in SoftFS image | Not saved |
|-----------------------|-----------|
| File names, directory tree | SoftShell scrollback / prompt line |
| File contents | Current working directory (cwd resets to `/`) |
| Empty directories | SoftASM process state / registers |
| Demo `.sox` files (unless you `rm` them) | Framebuffer pixels, demo mode |
| | Keyboard queue, colors (console colors are session UI) |

Persistence is **the filesystem**, not a full VM snapshot.

---

## When SoftUI writes to the host

| Trigger | Path |
|---------|------|
| SoftShell `touch` `mkdir` `rm` `rmdir` `mv` `cp` `write` `append` | `SoftShell.persistFs` → `on_fs_sync` → `persistFs` in `main.zig` |
| SoftShell `sync` | Same, plus prints `synced` |
| `txedit` Ctrl-O / Ctrl-S success | Action `.saved` → `persistFs` |
| Page unload | JS `beforeunload` → `softui_persist()` export |

There is no background dirty-bit flusher on a timer; saves are event-driven. Unload coverage reduces loss if the last mutation somehow skipped a sync (normal mutations already sync immediately).

---

## Pack and mount internals

### Live SoftFS (RAM)

Defined in `runtime/src/softfs.zig`:

- Up to **128** nodes (`MAX_NODES`), including root `/`
- File names ≤ **31** bytes (`MAX_NAME`)
- File payload heap **512 KiB** (`DATA_HEAP`)
- Nodes form a parent-pointer tree; cwd is a node index

Mutations update this tree only. Nothing is durable until `pack`.

### SoftFS v1 (factory)

Flat table — every entry is a file under `/`:

```
SOFS | version=1 | file_count
entries[i]: name[32] | data_offset u32 | size u32     (40 bytes each)
data region…
```

`mountV1` creates each file with `createFile(ROOT, name, bytes)`.

### SoftFS v2 (persisted sessions)

Tree-capable image produced by `Fs.pack`:

```
SOFS | version=2 | node_count
entries[i]: name[32] | parent u16 | kind u8 | pad u8 | offset u32 | size u32
            (44 bytes; parent 0xFFFF = child of root)
data region…   # only file payloads, concatenated in BFS order
```

Pack walks the tree **BFS from root’s children** so parents always appear before children. Directories get `kind=1` and zero size/offset; files get `kind=0` and a data-region offset.

`mountV2` recreates nodes in table order, resolving `parent` pack indices to live SoftFS node indices.

Reference layout: [isa.md](../isa.md) (`.sofs` section).

### Size budget

Packed size ≈ `8 + node_count×44 + sum(file sizes)`. SoftUI’s disk arena is **2 MiB** (`DISK_ARENA_SIZE` in `main.zig`). Web `localStorage` typically allows a few MiB per origin — SoftFS’s 512 KiB heap fits comfortably when base64-encoded (~4/3 expansion).

---

## Host side (Web)

File: `bootstrap/web/softui.js`

| Piece | Behavior |
|-------|----------|
| `STORAGE_KEY` | `"softui.sofs"` |
| `loadPersistedDisk()` | `atob` → bytes; requires magic `SOFS` |
| `savePersistedDisk(memory, ptr, len)` | copy WASM bytes → `btoa` → `localStorage` |
| `host_storage_write` | import bound to `savePersistedDisk` |
| Boot preference | persisted disk if valid, else `fetch("./init.sofs")` |
| Mount failure | if source was localStorage → remove key, remount factory |
| `beforeunload` | `softui_persist()` if exported |

Other hosts (future native) would implement the same import against a real file or block device without SoftUI changes.

---

## Kernel API surface

| Symbol | Side | Role |
|--------|------|------|
| `softui_mount_disk(ptr, len)` | export | Copy host-provided blob into `disk_blob`, mark mounted |
| `softui_persist()` | export | `pack` + `host_storage_write` |
| `host_storage_write(ptr, len)` | import | Host durable write |
| SoftShell `on_fs_sync` | internal | Hook wired to `persistFs` at CLI start |

Implementation: `runtime/src/main.zig` (`persistFs`, `mountFsIfNeeded`, exports).

---

## SoftShell operator view

```text
softui:/> write notes hello persistence
softui:/> sync
synced
softui:/> ls
  [file] notes 18b
  ...
```

Reload the page. `notes` should still exist. `pwd` starts at `/` again.

```text
softui:/> help fs
...
  sync                 persist SoftFS to host
```

---

## Resetting to factory disk

In the browser console (same origin as SoftUI):

```js
localStorage.removeItem("softui.sofs");
location.reload();
```

Or SoftShell-delete everything and `sync` — that also persists an empty-ish tree; clearing `localStorage` is the clean factory restore.

---

## Failure modes and diagnostics

| Symptom | Likely cause | What SoftUI / bootstrap does |
|---------|--------------|------------------------------|
| Changes vanish on reload | `host_storage_write` failed (quota, private mode) | JS `console.warn`; SoftUI still has RAM copy until exit |
| Boot uses factory demos after edits | Persisted blob missing or cleared | Expected after reset |
| `softfs mount failed` in `host_log` | Corrupt image | Bootstrap may fall back to `init.sofs` |
| `softfs pack failed` | Packed size > disk arena | Mutation stayed in RAM; host not updated |
| `sync not wired` | SoftShell started without `on_fs_sync` | Should not happen on normal Web boot |

Watch the browser console for `[softui] mounting disk from localStorage|init.sofs` and `[softui] softfs synced`.

---

## Design choices (intentional)

1. **Immediate persist on mutation** — toy OS scale; avoids lost work without a journal.
2. **v2 for saves, v1 for factory** — packer tool stays simple; live tree needs directories.
3. **Host owns media** — SoftUI stays portable; only the blob format is SoftUI’s contract.
4. **No cwd in the image** — cwd is session state; always boot at `/`.
5. **Whole-image rewrite** — no incremental journal yet (catalog: SoftFS journaling **planned**).

---

## Related source map

| File | Role |
|------|------|
| `runtime/src/softfs.zig` | `mount` / `mountV1` / `mountV2` / `pack` |
| `runtime/src/main.zig` | `persistFs`, `softui_persist`, mount, shell hook |
| `runtime/src/softshell.zig` | `persistFs`, `cmdSync`, mutation hooks |
| `runtime/src/txedit.zig` | `.saved` after successful write |
| `bootstrap/web/softui.js` | load/save `localStorage`, Host ABI import |
| `tools/pack_sofs.zig` | Builds factory SoftFS **v1** `init.sofs` |
| `host-abi/host_abi.h` | C declarations |

---

## Related guides

- [softfs-guide.md](softfs-guide.md) — tree semantics and limits
- [boot.md](boot.md) — where persistence slots into boot
- [host-abi-guide.md](host-abi-guide.md) — storage import contract
- Reference: [softfs.md](../softfs.md) · [isa.md](../isa.md) · [host-abi.md](../host-abi.md)
