# Language reference

File extension: `.sui`  
Name: **suigui**

## Program

```sui
app "Name"

window title="Name" fill {
  /* elements */
}
```

- `app` takes a quoted string (required style for the display name).
- One or more root elements follow (usually a single `window`).

## Comments

```sui
// line comment
/* block comment */
```

## Elements

```text
tag attrs? { children? }
```

Examples:

```sui
label #msg text="Hi"
button grow text="OK" click { msg.text = "OK" }
col gap=8 pad=12 fill { /* … */ }
```

- Leaf nodes may omit `{ }`.
- Children are nested elements inside braces.
- Nesting is brace-delimited (indentation is cosmetic only).

## Attributes

| Form | Meaning |
|------|---------|
| `name="string"` | String property (always quote strings) |
| `name=12` | Number |
| `fill` `grow` `scroll` | Boolean flags (`grow` defaults to weight 1) |
| `grow=2` | Flex grow weight |
| `#id` | Shorthand for `id="id"` |

String values **must** use quotes: `title="Calculator"`, `text="0"`.

## Flow layout attributes

| Attr | Role |
|------|------|
| `fill` | Occupy available space in the parent |
| `grow` / `grow=N` | Share leftover space in a `row` or `col` |
| `gap=N` | Space between children |
| `pad=N` | Inner padding |
| `align="start\|center\|end"` | Alignment |
| `w=N` `h=N` | Optional size hints (not required) |

Primary containers: `row` (horizontal), `col` (vertical).

## Events (A + B)

**A — inline expression string**

```sui
button text="7" click="display.text = display.text + '7'"
```

**B — brace block** (preferred when the body needs `"…"`):

```sui
button text="C" click {
  display.text = "0"
}
```

Event names in v1: `click` (more later: `change`, `key`).

## Assignments

No `set` keyword:

```sui
display.text = "0"
count.text = count.text + 1
```

Left side is `id.property`. Right side is an expression.

## Expressions

- Numbers: `1`, `3.14`
- Strings: `"hello"`, `'x'` (either quote style inside expressions)
- Refs: `display.text`
- Operators: `+ - * /` and parentheses
- `+` adds numerically when both sides look like numbers; otherwise concatenates strings

## Errors

Lexer/parser errors include `at line:col`. Fix the marked location and Run again.
