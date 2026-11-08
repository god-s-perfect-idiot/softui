# Events

suigui keeps interactivity on the element — similar spirit to HTMX, but local (no HTTP).

## Styles

### A — attribute string

```sui
button text="+" click="count.text = count.text + 1"
```

Use single-quoted string literals inside the double-quoted attribute when needed:

```sui
click="display.text = display.text + '7'"
```

### B — block

```sui
button text="Reset" click {
  count.text = "0"
}
```

Use B whenever the body needs `"double quotes"` or multiple statements.

## Assignment rules

```sui
target.prop = expression
```

- No `set` keyword.
- `target` is a widget `#id`.
- v1 supports one property level (`display.text`).

## What runs

1. Pointer hit-tests widgets.
2. On press, the runtime runs the widget’s `click` handler.
3. Assignments update props.
4. The tree re-layouts and repaints.

## Errors at runtime

Unknown ids (`msg.text = …` without `#msg`) show in the preview status line.
