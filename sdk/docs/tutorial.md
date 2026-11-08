# Tutorial

## 0. Run the preview

```bash
cd sdk
node tools/serve.mjs
```

Open http://127.0.0.1:8765/web/

## 1. Hello

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

What this does:

- `app "Hello"` names the program.
- `window … fill { }` is the root surface (title bar + content).
- `col` stacks children vertically with `gap` and `pad`.
- `#msg` gives the label an id so handlers can write `msg.text = …`.
- `click { … }` is a **B-style** handler block.

Press **Run**, then click **Wave**.

## 2. Counter

```sui
app "Counter"

window title="Counter" fill {
  col gap=16 pad=24 fill {
    label #count text="0" align="center" grow

    row gap=8 {
      button grow text="-" click {
        count.text = count.text - 1
      }
      button grow text="+" click {
        count.text = count.text + 1
      }
    }
  }
}
```

Notes:

- `row` places the buttons side by side.
- `grow` on buttons shares horizontal space equally.
- `+` / `-` coerce numeric-looking strings so counters work.

## 3. Calculator (A + B styles)

Digit keys use **A-style** one-liners (single-quoted chars inside the double-quoted attr):

```sui
button grow text="7" click="display.text = display.text + '7'"
```

Clear uses a **B-style** block (cleaner when you need double quotes):

```sui
button grow text="C" click {
  display.text = "0"
}
```

Open `examples/calculator.sui` in the preview to explore the full pad.

## 4. Edit and iterate

1. Change label text or add another button in the editor.
2. Press **Run** (or Ctrl+Enter).
3. If something is wrong, the status line shows `message at line:col`.

Next: [language.md](language.md) for the full grammar.
