# SoftFS (reference)

In-memory filesystem SoftUI mounts at boot from a Host ABI disk blob. Mutations pack back to SoftFS v2 and persist through `host_storage_write`.

**Guides:** [softfs-guide.md](guides/softfs-guide.md) (tree, limits, APIs) · [persistence.md](guides/persistence.md) (save/load end-to-end).

## Mount path (Web)

1. Bootstrap loads `localStorage['softui.sofs']` if present, else fetches `init.sofs`.
2. Calls `softui_alloc(len)` for a writable WASM buffer.
3. Copies bytes into WASM memory.
4. Calls `softui_mount_disk(ptr, len)`.
5. Kernel parses SoftFS into a mutable tree (v1 flat or v2 directories).
6. SoftShell mutations / `sync` / page unload call `softui_persist` → `host_storage_write`.

## Layout

See [isa.md](isa.md). **v1** (factory `init.sofs`): flat files under `/`. **v2** (persisted sessions): directory tree with parent indices.

## Limits (runtime)

| Resource | Cap |
|----------|-----|
| Nodes | 128 (incl. root) |
| Basename | 31 bytes |
| File heap | 512 KiB |
| Disk arena (packed image) | 2 MiB |

Source: `runtime/src/softfs.zig`, `runtime/src/main.zig`.
