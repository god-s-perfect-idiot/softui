# SoftShell capability catalog

SoftShell is SoftUI’s CLI scripting / REPL. All text is SoftUI-framebuffer glyphs — never host UI.

Legend: **[shipped]** available now · **[planned]** roadmap · **[kernel]** can inspect or mutate SoftUI kernel state

---

## Filesystem (SoftFS)

Mutable in-memory FS mounted from `init.sofs`. Edits persist for the session (Host ABI disk sync later).

| Capability | Command / API | Status |
|------------|---------------|--------|
| List directory | `ls [path]` | **[shipped]** |
| Tree walk | `tree [path]` | **[shipped]** |
| Print working dir | `pwd` | **[shipped]** |
| Change directory | `cd <path>` | **[shipped]** |
| Read text | `cat <path>` | **[shipped]** |
| Hex dump | `hexdump` / `hd <path>` | **[shipped]** |
| Metadata | `stat <path>` | **[shipped]** |
| Word/line count | `wc <path>` | **[shipped]** |
| Create empty file | `touch <path>` | **[shipped]** |
| Create directory | `mkdir <path>` | **[shipped]** |
| Delete file | `rm <path>` | **[shipped]** |
| Delete empty dir | `rmdir <path>` | **[shipped]** |
| Rename / move | `mv <src> <dst>` | **[shipped]** |
| Copy file | `cp <src> <dst>` | **[shipped]** |
| Write / overwrite | `write` / `printf <path> <text…>` | **[shipped]** |
| Append | `append <path> <text…>` | **[shipped]** |
| Space usage | `df` | **[shipped]** |
| Absolute + relative paths, `.` / `..` | path resolver | **[shipped]** |
| Command chaining | `cmd; cmd` | **[shipped]** |
| Persist SoftFS to host blob | `sync` / Host ABI storage write | **[planned]** |
| Recursive `rm -r` | `rm -r` | **[planned]** |
| Permissions / owners | `chmod` `chown` | **[planned]** |
| Links | `ln` | **[planned]** |
| Mount extra images | `mount` | **[planned]** |
| SoftFS journaling | — | **[planned]** |

---

## Shell / scripting

| Capability | Notes | Status |
|------------|-------|--------|
| Interactive REPL | line editor, prompt with cwd | **[shipped]** |
| `echo` `clear` `help` | basics | **[shipped]** |
| `;` sequencing | `mkdir a; cd a; touch f` | **[shipped]** |
| Capability overview | `capabilities` / `caps` | **[shipped]** |
| Variables / env | `set` `export` `$VAR` | **[planned]** |
| Conditionals / loops | `if` `while` `for` | **[planned]** |
| Functions | `fn name …` | **[planned]** |
| Script files | `source script.shsoft` | **[planned]** |
| Pipes / redirects | `\|` `>` `>>` | **[planned]** |
| Globbing | `*.sox` | **[planned]** |
| History / tab complete | arrows, Tab | **[planned]** |
| Job control | `bg` `fg` Ctrl-C | **[planned]** |

---

## SoftASM / processes

| Capability | Command | Status |
|------------|---------|--------|
| Run `.sox` | `run <file.sox>` | **[shipped]** (burst) |
| Donut / plasma / stars / cube / fire demos | SoftShell commands | **[shipped]** |
| List SoftASM svc table | `svc` | **[shipped]** |
| Long-running SoftASM takeover | yield + input handoff | **[planned]** |
| Assemble from SoftShell | `asm` | **[planned]** |
| SoftASM debugger | `break` `step` `regs` | **[planned]** **[kernel]** |
| Spawn / kill process | `spawn` `kill` | **[planned]** **[kernel]** |
| Scheduler inspect | `ps` `nice` | **[planned]** **[kernel]** |

---

## Kernel / SoftUI surface **[kernel]**

Direct SoftUI runtime inspection and limited mutation from SoftShell.

| Capability | Command | Status |
|------------|---------|--------|
| Kernel + display info | `kinfo` / `sysinfo` | **[shipped]** |
| Arena / disk / process memory | `mem` | **[shipped]** |
| Frame counter | `ticks` | **[shipped]** |
| Framebuffer fill | `fb fill x y w h color` | **[shipped]** |
| Framebuffer clear | `fb clear [color]` | **[shipped]** |
| Reinit shell session | `reboot` | **[shipped]** |
| Boot mode | `softui_set_boot_mode` (Host ABI); shell setter | **[planned]** |
| Peek/poke SoftUI heap | `peek` `poke` addr | **[planned]** **[kernel]** |
| Dump SoftASM VM state | `vm` | **[planned]** **[kernel]** |
| Input queue inspect | `input` | **[planned]** **[kernel]** |
| Force present / vsync stats | `fps` | **[planned]** |
| Panic SoftUI (debug) | `panic` | **[planned]** **[kernel]** |
| Hot-reload SoftFS image | `remount` | **[planned]** **[kernel]** |
| Allocator diagnostics | `leak` `arena` | **[planned]** **[kernel]** |
| Log buffer / dmesg | `dmesg` | **[planned]** **[kernel]** |

---

## Graphics / console

| Capability | Status |
|------------|--------|
| SoftUI glyph console | **[shipped]** |
| SoftUI demos (`donut` `plasma` `stars` `cube` `fire`) | **[shipped]** |
| SoftUI GPU text / accel path | **[planned]** (still SoftUI-owned pixels) |
| GUI boot chrome | **[planned]** (Phase 4; opt-in) |
| Windowing | deferred by design |

---

## Networking / time / devices

| Capability | Status |
|------------|--------|
| Host ABI time (tick clock) | **[shipped]** (internal) |
| Wall clock / sleep | **[planned]** |
| Sockets via Host ABI | **[planned]** |
| Clipboard Host ABI | **[planned]** |

---

## Example session

```
softui:/> ls
softui:/> mkdir demos
softui:/> cd demos
softui:/demos> write note.txt hello from SoftShell
softui:/demos> cat note.txt
softui:/demos> append note.txt more lines
softui:/demos> wc note.txt
softui:/demos> cd ..
softui:/> tree
softui:/> kinfo
softui:/> mem
softui:/> df
softui:/> donut
```
