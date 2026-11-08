/** suigui parser — element trees, A+B events, bare assignments. */

import { lex, LexError } from "./lexer.js";

export class ParseError extends Error {
  constructor(message, line, col) {
    super(`${message} at ${line}:${col}`);
    this.line = line;
    this.col = col;
    this.name = "ParseError";
  }
}

const EVENT_NAMES = new Set(["click", "change", "key"]);
const FLAG_NAMES = new Set(["fill", "grow", "scroll"]);

export function parse(source) {
  const tokens = lex(source);
  let pos = 0;

  const cur = () => tokens[pos];
  const at = (type) => cur().type === type;
  const peekType = (n = 0) => tokens[pos + n]?.type;

  function eat(type) {
    const t = cur();
    if (t.type !== type) {
      throw new ParseError(`Expected ${type}, got ${t.type}`, t.line, t.col);
    }
    pos++;
    return t;
  }

  function parseExpr() {
    return parseAdd();
  }

  function parseAdd() {
    let left = parseMul();
    while (at("plus") || at("minus")) {
      const op = eat(cur().type).type;
      const right = parseMul();
      left = { kind: "binary", op, left, right };
    }
    return left;
  }

  function parseMul() {
    let left = parseUnary();
    while (at("star") || at("slash")) {
      const op = eat(cur().type).type;
      const right = parseUnary();
      left = { kind: "binary", op, left, right };
    }
    return left;
  }

  function parseUnary() {
    if (at("minus")) {
      eat("minus");
      return { kind: "unary", op: "minus", expr: parseUnary() };
    }
    return parsePrimary();
  }

  function parsePrimary() {
    const t = cur();
    if (at("number")) {
      eat("number");
      return { kind: "number", value: t.value };
    }
    if (at("string")) {
      eat("string");
      return { kind: "string", value: t.value };
    }
    if (at("lparen")) {
      eat("lparen");
      const e = parseExpr();
      eat("rparen");
      return e;
    }
    if (at("ident")) {
      const parts = [eat("ident").value];
      while (at("dot")) {
        eat("dot");
        parts.push(eat("ident").value);
      }
      return { kind: "ref", path: parts };
    }
    throw new ParseError(`Unexpected token in expression: ${t.type}`, t.line, t.col);
  }

  function parseStatement() {
    const t = cur();
    if (!at("ident")) {
      throw new ParseError("Expected statement", t.line, t.col);
    }
    // Lookahead: ident (.ident)* =
    let look = 0;
    if (peekType(look) !== "ident") {
      throw new ParseError("Expected assignment", t.line, t.col);
    }
    look++;
    while (peekType(look) === "dot" && peekType(look + 1) === "ident") look += 2;
    if (peekType(look) !== "eq") {
      throw new ParseError("Expected '=' in assignment", t.line, t.col);
    }
    const parts = [eat("ident").value];
    while (at("dot")) {
      eat("dot");
      parts.push(eat("ident").value);
    }
    eat("eq");
    const value = parseExpr();
    return { kind: "assign", path: parts, value, line: t.line, col: t.col };
  }

  function parseAttrValue() {
    const t = cur();
    if (at("string")) return eat("string").value;
    if (at("number")) return eat("number").value;
    if (at("ident")) return eat("ident").value;
    throw new ParseError("Expected attribute value", t.line, t.col);
  }

  function parseElement() {
    const nameTok = eat("ident");
    const tag = nameTok.value;
    const attrs = {};
    const events = {};
    const children = [];

    // Attributes / flags / events until `{` or next element / eof / `}`
    while (true) {
      if (at("hashid")) {
        attrs.id = eat("hashid").value;
        continue;
      }
      if (!at("ident")) break;

      const name = cur().value;
      const next = peekType(1);

      if (EVENT_NAMES.has(name) && next === "eq") {
        eat("ident");
        eat("eq");
        const src = eat("string").value;
        events[name] = { style: "A", source: src };
        continue;
      }
      if (EVENT_NAMES.has(name) && next === "lbrace") {
        eat("ident");
        eat("lbrace");
        const stmts = [];
        while (!at("rbrace") && !at("eof")) {
          stmts.push(parseStatement());
        }
        eat("rbrace");
        events[name] = { style: "B", body: stmts };
        continue;
      }

      if (next === "eq") {
        eat("ident");
        eat("eq");
        attrs[name] = parseAttrValue();
        continue;
      }

      // Only known flag names may appear bare. Any other bare ident ends the
      // attribute list so the next element (e.g. `row`) is not swallowed as a flag.
      if (FLAG_NAMES.has(name)) {
        eat("ident");
        if (name === "grow" && attrs.grow === undefined) attrs.grow = 1;
        else attrs[name] = true;
        continue;
      }

      break;
    }

    if (at("lbrace")) {
      eat("lbrace");
      while (!at("rbrace") && !at("eof")) {
        if (at("ident")) {
          // Nested element (not assignment — assignments only inside event blocks)
          children.push(parseElement());
        } else {
          throw new ParseError(`Unexpected token in element body: ${cur().type}`, cur().line, cur().col);
        }
      }
      eat("rbrace");
    }

    return {
      kind: "element",
      tag,
      attrs,
      events,
      children,
      line: nameTok.line,
      col: nameTok.col,
    };
  }

  // Program: app "Name" then root elements
  let appName = "App";
  if (at("ident") && cur().value === "app") {
    eat("ident");
    if (at("string")) appName = eat("string").value;
    else if (at("ident")) appName = eat("ident").value;
    else throw new ParseError('Expected app name string', cur().line, cur().col);
  }

  const roots = [];
  while (!at("eof")) {
    if (!at("ident")) {
      throw new ParseError(`Unexpected token ${cur().type}`, cur().line, cur().col);
    }
    roots.push(parseElement());
  }

  return { kind: "program", appName, roots };
}

export function parseSafe(source) {
  try {
    return { ok: true, ast: parse(source) };
  } catch (e) {
    if (e instanceof LexError || e instanceof ParseError) {
      return { ok: false, error: e.message, line: e.line, col: e.col };
    }
    throw e;
  }
}
