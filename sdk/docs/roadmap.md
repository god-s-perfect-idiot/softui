# Roadmap

## Done (SDK v1)

- Brace markup without `<tags>`
- A+B event handlers, bare assignments, quoted strings
- Flow layout: `row` / `col` / `fill` / `grow` / `gap` / `pad`
- Web canvas preview + examples + docs

## Next — SoftUI hybrid shell

- Desktop home + status bar + bottom tray
- Real multitasking: concurrent app sessions, background ticks, tray focus switch
- Home returns to desktop without killing apps; Close ends one session

## Then — suigui on SoftUI

- In-guest (or bridged) suigui runtime against SoftUI framebuffer
- Ship Calculator / Files / Settings as `.sui` apps
- SoftFS packing of `.sui` sources or bytecode
- Same system lib names (`ui`, `draw`, `app`, `time`) on the guest

## Later

- `change` / `key` events, richer fields
- `scroll` viewports, lists
- Declarative verb sugar (`click-set`, `click-append`) as optional HTMX-like attrs
- SoftASM emit path (optional; interpret-first remains default)
