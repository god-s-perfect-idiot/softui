# SoftShell guide

SoftShell is SoftUI’s interactive CLI: the default boot experience. Every character of the prompt, output, and editor is drawn by SoftUI into the RGBA framebuffer — never by the host.

Capability catalog (shipped/planned): [softshell.md](../softshell.md).

---

## What SoftShell is

| SoftShell is | SoftShell is not |
|--------------|------------------|
| Part of the SoftUI kernel image | A separate `.sox` process (yet) |
| A SoftFS client with full CRUD | A host terminal emulator |
| A SoftASM launcher (`run`) | A full Unix shell (no pipes/vars yet) |
| A kernel inspection surface | Bound to DOM text widgets |

Modes: `shell` | `txedit` | fullscreen demos (`donut`, `plasma`, `stars`, `cube`, `fire`). Leaving a demo: any key returns to the shell.

---

## Session lifecycle

1. `softui_start` → `startCli` wires callbacks and `SoftShell.start`
2. Banner + `softui:/> ` prompt
3. Each tick: pop keys → line edit / dispatch → redraw console
4. FS mutations call `persistFs` → host storage (see [persistence.md](persistence.md))
5. SoftShell `reboot` re-inits console/prompt; SoftFS untouched

---

## Line editing and chaining

- Enter runs the line; SoftShell tokenizes on whitespace
- `;` sequences commands: `mkdir a; cd a; touch f`
- No history / tab completion yet (planned in catalog)

Prompt embeds cwd: `softui:/a> `.

---

## Filesystem commands

| Command | Behavior | Persists? |
|---------|----------|-----------|
| `pwd` `cd` `ls` `tree` | Navigate / list | no |
| `cat` `hexdump`/`hd` `stat` `wc` `df` | Inspect | no |
| `touch` `mkdir` `rm` `rmdir` `mv` `cp` | Mutate tree | **yes** |
| `write`/`printf` `append` | Create/overwrite/append text | **yes** |
| `sync` | Force pack + `host_storage_write` | **yes** |
| `txedit`/`nano`/`edit` | Editor; save with ^O/^S | **on save** |

`help fs` prints the in-shell summary.

---

## Apps and demos

### `txedit`

Nano-like editor over SoftFS:

- `txedit notes` opens or creates
- Arrow keys move; printable inserts
- `^O` / `^S` save → SoftFS write → SoftShell `.saved` → persist
- `^X` exit (confirms if dirty)

Path length currently capped like SoftFS basenames (editor stores a short path buffer).

### `color`

Sets SoftShell console fg/bg (`#RRGGBB`, `fg`, `bg`, `reset`). Session-only — not SoftFS.

### Kernel demos

`donut` `plasma` `stars` `cube` `fire` switch SoftShell into a fullscreen SoftUI renderer mode (not SoftASM). SoftASM equivalents exist as `.sox` demos on SoftFS for `run`.

---

## SoftASM from SoftShell

```text
run donut.sox
```

Loads the file from SoftFS, interprets up to 200 000 instructions, returns. See [softasm-guide.md](softasm-guide.md).

---

## Kernel inspection

```text
kinfo
mem
ticks
svc
fb clear 0xFF0B0E12
fb fill 10 10 100 50 0xFF50B4FF
capabilities
```

`kinfo` is filled via `on_refresh_kinfo` from `main.zig` (live arena / disk sizes).

---

## Callbacks SoftShell expects

Wired in `main.zig` `startCli`:

| Hook | Purpose |
|------|---------|
| `on_donut` … `on_fire` | Demo renderers |
| `on_run_sox` | SoftASM load/run |
| `on_fb_fill` | Rectangle poke |
| `on_reboot_shell` | Re-`start` shell |
| `on_refresh_kinfo` | Fill `KernelInfo` |
| `on_fs_sync` | Persist SoftFS |

If `on_fs_sync` is null, `sync` prints `sync not wired` and mutations skip host write.

---

## Related

- [persistence.md](persistence.md) · [softfs-guide.md](softfs-guide.md) · [framebuffer-guide.md](framebuffer-guide.md)
- Reference: [softshell.md](../softshell.md)
