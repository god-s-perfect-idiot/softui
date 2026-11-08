# suigui documentation

suigui (Soft UI GUI) is a small markup language for building SoftUI-style apps quickly. It looks a bit like XML and a bit like HTMX, but without `<angle brackets>` — structure uses `{ }`, layout is flow-based, and actions live on the widgets.

## Guides

| Doc | Contents |
|-----|----------|
| [tutorial.md](tutorial.md) | First apps: Hello → Counter → Calculator |
| [language.md](language.md) | Full syntax reference |
| [widgets.md](widgets.md) | Elements and properties |
| [events.md](events.md) | A/B click handlers and assignments |
| [libs.md](libs.md) | System libraries (`ui`, `draw`, `app`, `time`) |
| [examples.md](examples.md) | Walkthrough of shipped samples |
| [roadmap.md](roadmap.md) | SoftUI embed, multitasking desktop |

## Mental model

```text
.app.sui  →  parse tree  →  widget tree  →  flow layout  →  canvas pixels
                 ↑
           click handlers mutate widget props (e.g. label.text)
```

1. Declare a tree of elements (`window`, `col`, `row`, `button`, …).
2. Use `fill` / `grow` / `gap` / `pad` instead of `x,y,w,h`.
3. Put behavior on nodes: `click="…"` or `click { … }`.
4. Assign with bare `name = value` (no `set`). Strings always use quotes.
