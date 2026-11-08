# suigui SDK

High-level GUI language for SoftUI apps. Write nested markup with **flow layout** and simple event handlers — no SoftASM, no Zig, no per-pixel coordinates.

This folder is **self-contained**. Preview apps in the browser with Node’s built-in HTTP server.

## Quick start

```bash
cd sdk
node tools/serve.mjs
# or, without Node:
python tools/serve.py
```

Open [http://127.0.0.1:8765/web/](http://127.0.0.1:8765/web/).

Pick an example, edit the source, press **Run** (or Ctrl+Enter).

## Hello

```sui
app "Hello"

window title="Hello" fill {
  col gap=16 pad=24 fill {
    label #msg text="Hello from suigui" align="center"
    button text="Wave" click {
      msg.text = "Hello, SoftUI"
    }
  }
}
```

## Layout

| Path | Role |
|------|------|
| `lang/` | Lexer, parser, interpreter |
| `runtime/` | Canvas widgets, flow layout, system libs |
| `web/` | Browser preview shell |
| `examples/` | hello, counter, calculator |
| `docs/` | Full language + widget documentation |
| `tools/serve.mjs` | Static server |

## Documentation

Start at [docs/README.md](docs/README.md).

## SoftUI bridge

Today the SDK runs on a JS canvas host. SoftUI will later host the same `.sui` apps as guest sessions under the hybrid desktop (see [docs/roadmap.md](docs/roadmap.md)).
