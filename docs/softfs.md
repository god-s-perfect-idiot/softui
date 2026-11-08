# SoftFS (v0)

Minimal initrd-style image SoftUI mounts at boot. No host filesystem APIs — only a blob provided through Host ABI.

## Mount path (Web)

1. Bootstrap fetches `init.sofs` as an `ArrayBuffer`.
2. Calls `softui_alloc(len)` for a writable WASM buffer.
3. Copies bytes into WASM memory.
4. Calls `softui_mount_disk(ptr, len)`.
5. Kernel parses SoftFS, loads `init.sox`, and runs it on the SoftASM VM.

## Layout

See [isa.md](isa.md) for the on-disk header. Phase 2 supports flat named files only (no directories).
