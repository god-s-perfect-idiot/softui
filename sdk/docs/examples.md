# Examples

All samples live in `sdk/examples/` and load in the web preview.

## `hello.sui`

Teaches:

- `app` / `window` / `col`
- `#id` on a label
- B-style `click { }` updating `msg.text`

## `counter.sui`

Teaches:

- `row` + `grow` for equal buttons
- Numeric `+` / `-` on label text
- Reset via assignment to `"0"`

## `calculator.sui`

Teaches:

- Mixing **A** one-liners and **B** blocks
- `align="end"` display label
- Grid-like pad via stacked `row`s (no pixel grid required)

Digit append uses string concatenation:

```sui
click="display.text = display.text + '7'"
```

Clear resets with a block:

```sui
click {
  display.text = "0"
}
```

## Making your own

1. Copy `hello.sui`.
2. Add `row` / `col` structure.
3. Give interactive labels an `#id`.
4. Attach `click` handlers.
5. Run in the preview.
