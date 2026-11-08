/** Evaluate expressions and run A/B event handlers against the widget tree. */

import { lex } from "./lexer.js";
import { parse as parseProgram } from "./parser.js";

function evalExpr(node, env) {
  switch (node.kind) {
    case "number":
      return node.value;
    case "string":
      return node.value;
    case "ref":
      return env.get(node.path);
    case "unary":
      if (node.op === "minus") return -Number(evalExpr(node.expr, env));
      throw new Error(`Unknown unary ${node.op}`);
    case "binary": {
      const l = evalExpr(node.left, env);
      const r = evalExpr(node.right, env);
      if (node.op === "plus") {
        const nl = Number(l);
        const nr = Number(r);
        const lNum = typeof l === "number" || (typeof l === "string" && /^-?\d+(\.\d+)?$/.test(l.trim()));
        const rNum = typeof r === "number" || (typeof r === "string" && /^-?\d+(\.\d+)?$/.test(r.trim()));
        if (lNum && rNum && Number.isFinite(nl) && Number.isFinite(nr)) return nl + nr;
        return String(l) + String(r);
      }
      if (node.op === "minus") return Number(l) - Number(r);
      if (node.op === "star") return Number(l) * Number(r);
      if (node.op === "slash") return Number(l) / Number(r);
      throw new Error(`Unknown op ${node.op}`);
    }
    default:
      throw new Error(`Bad expr kind ${node.kind}`);
  }
}

/** Parse a single expression or assignment statement from a string (style A). */
function parseHandlerSource(source) {
  // Reuse program parser machinery by wrapping — simpler: lex + mini parse
  const tokens = lex(source.trim());
  let pos = 0;
  const cur = () => tokens[pos];
  const at = (t) => cur().type === t;
  const eat = (t) => {
    if (cur().type !== t) throw new Error(`Expected ${t} in handler`);
    return tokens[pos++];
  };

  function parseExpr() {
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
    if (at("number")) return { kind: "number", value: eat("number").value };
    if (at("string")) return { kind: "string", value: eat("string").value };
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
    throw new Error(`Bad token in handler: ${cur().type}`);
  }

  if (!at("ident")) throw new Error("Handler must be an assignment");
  const parts = [eat("ident").value];
  while (at("dot")) {
    eat("dot");
    parts.push(eat("ident").value);
  }
  eat("eq");
  const value = parseExpr();
  if (!at("eof")) throw new Error("Unexpected trailing tokens in handler");
  return { kind: "assign", path: parts, value };
}

export function createEnv(idIndex) {
  return {
    get(path) {
      if (path.length === 0) return undefined;
      const id = path[0];
      const widget = idIndex.get(id);
      if (!widget) throw new Error(`Unknown id '${id}'`);
      if (path.length === 1) return widget;
      let cur = widget;
      for (let i = 1; i < path.length; i++) {
        const key = path[i];
        if (cur && cur.props && key in cur.props) cur = cur.props[key];
        else if (cur && key in cur) cur = cur[key];
        else throw new Error(`Unknown property '${path.join(".")}'`);
      }
      return cur;
    },
    set(path, value) {
      if (path.length < 2) throw new Error("Cannot assign to bare id");
      const id = path[0];
      const widget = idIndex.get(id);
      if (!widget) throw new Error(`Unknown id '${id}'`);
      const prop = path[path.length - 1];
      if (path.length > 2) {
        throw new Error(`Nested assign not supported: ${path.join(".")}`);
      }
      widget.props[prop] = value;
      if (prop === "text") widget.text = String(value);
    },
  };
}

export function runAssign(stmt, env) {
  const v = evalExpr(stmt.value, env);
  env.set(stmt.path, v);
}

export function runEvent(handler, env) {
  if (!handler) return;
  if (handler.style === "A") {
    const stmt = parseHandlerSource(handler.source);
    runAssign(stmt, env);
    return;
  }
  if (handler.style === "B") {
    for (const stmt of handler.body) runAssign(stmt, env);
    return;
  }
}

export { parseProgram, evalExpr };
