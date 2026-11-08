/** Widget tree, flow layout (row/col), hit-testing, paint. */

import { drawText, measureText, GLYPH_H } from "./font.js";
import { createEnv, runEvent } from "../lang/interpreter.js";

const COLORS = {
  bg: "#0b0e12",
  panel: "#141a22",
  bar: "#10161e",
  fg: "#d7e0ea",
  dim: "#7a8796",
  accent: "#50b4ff",
  button: "#1a3048",
  buttonHover: "#243d5c",
  border: "#2a3544",
};

const BAR_H = 36;

function num(v, fallback = 0) {
  if (v === true || v === false || v == null) return fallback;
  const n = Number(v);
  return Number.isFinite(n) ? n : fallback;
}

function growOf(attrs) {
  if (attrs.grow === true) return 1;
  if (attrs.grow === false || attrs.grow == null) return 0;
  return Math.max(0, num(attrs.grow, 0));
}

export function buildTree(ast) {
  const idIndex = new Map();

  function fromElement(el, parent) {
    const attrs = { ...el.attrs };
    const node = {
      tag: el.tag,
      attrs,
      events: el.events || {},
      props: {
        text: attrs.text != null ? String(attrs.text) : "",
        title: attrs.title != null ? String(attrs.title) : "",
        placeholder: attrs.placeholder != null ? String(attrs.placeholder) : "",
        align: attrs.align != null ? String(attrs.align) : "start",
      },
      text: attrs.text != null ? String(attrs.text) : "",
      children: [],
      parent: parent || null,
      x: 0,
      y: 0,
      w: 0,
      h: 0,
      hover: false,
    };
    if (attrs.id) idIndex.set(String(attrs.id), node);
    for (const child of el.children || []) {
      node.children.push(fromElement(child, node));
    }
    return node;
  }

  const roots = ast.roots.map((r) => fromElement(r, null));
  return { appName: ast.appName, roots, idIndex };
}

function isRow(node) {
  return node.tag === "row";
}

function isCol(node) {
  return node.tag === "col" || node.tag === "window";
}

/** Minimum content size before grow/fill. */
function measure(node) {
  const pad = num(node.attrs.pad, 0);
  const gap = num(node.attrs.gap, 0);
  const hintW = node.attrs.w != null ? num(node.attrs.w) : null;
  const hintH = node.attrs.h != null ? num(node.attrs.h) : null;

  if (node.tag === "label") {
    const m = measureText(node.props.text || " ");
    return { w: hintW ?? m.w + pad * 2, h: hintH ?? Math.max(GLYPH_H + 8, m.h + pad * 2) };
  }
  if (node.tag === "button") {
    const m = measureText(node.props.text || " ");
    return {
      w: hintW ?? Math.max(48, m.w + 24),
      h: hintH ?? Math.max(40, m.h + 16),
    };
  }
  if (node.tag === "field") {
    return { w: hintW ?? 160, h: hintH ?? 36 };
  }
  if (node.tag === "box" || node.tag === "spacer") {
    return { w: hintW ?? 0, h: hintH ?? 0 };
  }

  if (isRow(node)) {
    let w = pad * 2;
    let h = 0;
    node.children.forEach((c, i) => {
      const s = measure(c);
      w += s.w + (i ? gap : 0);
      h = Math.max(h, s.h);
    });
    return { w: hintW ?? w, h: hintH ?? h + pad * 2 };
  }

  // col / window / default stack
  let w = 0;
  let h = pad * 2;
  node.children.forEach((c, i) => {
    const s = measure(c);
    h += s.h + (i ? gap : 0);
    w = Math.max(w, s.w);
  });
  return { w: hintW ?? w + pad * 2, h: hintH ?? h };
}

/**
 * Place `node` into box (x,y,w,h).
 * Grow/fill children expand along the main axis.
 */
function place(node, x, y, w, h) {
  node.x = x;
  node.y = y;
  node.w = w;
  node.h = h;

  const pad = num(node.attrs.pad, 0);
  const gap = num(node.attrs.gap, 0);
  const kids = node.children;
  if (!kids.length) return;

  const innerX = x + pad;
  const innerY = y + (node.tag === "window" ? BAR_H + pad : pad);
  const innerW = Math.max(0, w - pad * 2);
  const innerH = Math.max(0, h - (node.tag === "window" ? BAR_H : 0) - pad * 2);

  const dir = isRow(node) ? "row" : "col";
  const measures = kids.map((c) => measure(c));
  const grows = kids.map((c) => growOf(c.attrs) + (c.attrs.fill ? 1 : 0));
  const totalGrow = grows.reduce((a, b) => a + b, 0);

  if (dir === "row") {
    let fixed = gap * Math.max(0, kids.length - 1);
    kids.forEach((_, i) => {
      if (grows[i] === 0) fixed += measures[i].w;
    });
    const rest = Math.max(0, innerW - fixed);
    let cx = innerX;
    kids.forEach((c, i) => {
      const cw = grows[i] > 0 && totalGrow > 0 ? (rest * grows[i]) / totalGrow : measures[i].w;
      const ch = c.attrs.fill ? innerH : measures[i].h;
      let cy = innerY;
      const align = String(c.attrs.align || c.props.align || "start");
      if (align === "center") cy = innerY + (innerH - ch) / 2;
      if (align === "end") cy = innerY + innerH - ch;
      place(c, cx, cy, cw, Math.min(Math.max(ch, measures[i].h), innerH) || measures[i].h);
      // Prefer stretching cross-axis for buttons/fields in a tall row
      if (c.tag === "button" || c.tag === "field") {
        place(c, cx, innerY + (innerH - measures[i].h) / 2, cw, measures[i].h);
      }
      cx += cw + gap;
    });
  } else {
    let fixed = gap * Math.max(0, kids.length - 1);
    kids.forEach((_, i) => {
      if (grows[i] === 0) fixed += measures[i].h;
    });
    const rest = Math.max(0, innerH - fixed);
    let cy = innerY;
    kids.forEach((c, i) => {
      const ch = grows[i] > 0 && totalGrow > 0 ? (rest * grows[i]) / totalGrow : measures[i].h;
      // Main-axis children that are rows/cols usually take full width
      const stretchX = isRow(c) || isCol(c) || c.attrs.fill || growOf(c.attrs) > 0;
      const cw = stretchX ? innerW : Math.min(measures[i].w, innerW);
      let cx = innerX;
      const align = String(c.attrs.align || c.props.align || "start");
      if (!stretchX) {
        if (align === "center") cx = innerX + (innerW - cw) / 2;
        if (align === "end") cx = innerX + innerW - cw;
      }
      place(c, cx, cy, stretchX ? innerW : cw, ch);
      cy += ch + gap;
    });
  }
}

export function layoutTree(roots, viewportW, viewportH) {
  for (const root of roots) {
    if (root.tag === "window" || root.attrs.fill) {
      place(root, 0, 0, viewportW, viewportH);
    } else {
      const m = measure(root);
      place(root, 0, 0, Math.min(m.w, viewportW), Math.min(m.h, viewportH));
    }
  }
}

function roundRect(ctx, x, y, w, h, r) {
  const rr = Math.min(r, w / 2, h / 2);
  ctx.beginPath();
  ctx.moveTo(x + rr, y);
  ctx.arcTo(x + w, y, x + w, y + h, rr);
  ctx.arcTo(x + w, y + h, x, y + h, rr);
  ctx.arcTo(x, y + h, x, y, rr);
  ctx.arcTo(x, y, x + w, y, rr);
  ctx.closePath();
}

export function paintTree(ctx, roots, viewportW, viewportH) {
  ctx.fillStyle = COLORS.bg;
  ctx.fillRect(0, 0, viewportW, viewportH);

  function paint(node) {
    if (node.tag === "window") {
      ctx.fillStyle = COLORS.bg;
      ctx.fillRect(node.x, node.y, node.w, node.h);
      ctx.fillStyle = COLORS.bar;
      ctx.fillRect(node.x, node.y, node.w, BAR_H);
      ctx.fillStyle = COLORS.border;
      ctx.fillRect(node.x, node.y + BAR_H - 1, node.w, 1);
      drawText(ctx, node.props.title || "Window", node.x + 12, node.y + 11, COLORS.accent);
      for (const c of node.children) paint(c);
      return;
    }

    if (node.tag === "button") {
      ctx.fillStyle = node.hover ? COLORS.buttonHover : COLORS.button;
      roundRect(ctx, node.x, node.y, node.w, node.h, 6);
      ctx.fill();
      ctx.strokeStyle = COLORS.border;
      ctx.lineWidth = 1;
      roundRect(ctx, node.x + 0.5, node.y + 0.5, node.w - 1, node.h - 1, 6);
      ctx.stroke();
      const m = measureText(node.props.text || "");
      drawText(
        ctx,
        node.props.text || "",
        node.x + (node.w - m.w) / 2,
        node.y + (node.h - m.h) / 2,
        COLORS.fg,
      );
      return;
    }

    if (node.tag === "label") {
      const align = String(node.attrs.align || node.props.align || "start");
      const m = measureText(node.props.text || "");
      let tx = node.x;
      if (align === "center") tx = node.x + (node.w - m.w) / 2;
      if (align === "end") tx = node.x + Math.max(0, node.w - m.w);
      const ty = node.y + Math.max(0, (node.h - m.h) / 2);
      drawText(ctx, node.props.text || "", tx, ty, COLORS.fg);
      return;
    }

    if (node.tag === "field") {
      ctx.fillStyle = COLORS.panel;
      roundRect(ctx, node.x, node.y, node.w, node.h, 4);
      ctx.fill();
      ctx.strokeStyle = COLORS.border;
      roundRect(ctx, node.x + 0.5, node.y + 0.5, node.w - 1, node.h - 1, 4);
      ctx.stroke();
      const t = node.props.text || node.props.placeholder || "";
      drawText(ctx, t, node.x + 8, node.y + (node.h - GLYPH_H) / 2, node.props.text ? COLORS.fg : COLORS.dim);
      return;
    }

    if (node.tag === "box") {
      ctx.fillStyle = COLORS.panel;
      ctx.fillRect(node.x, node.y, node.w, node.h);
    }

    for (const c of node.children) paint(c);
  }

  for (const r of roots) paint(r);
}

export function hitTest(roots, px, py) {
  let found = null;
  function walk(node) {
    for (let i = node.children.length - 1; i >= 0; i--) walk(node.children[i]);
    if (px >= node.x && py >= node.y && px < node.x + node.w && py < node.y + node.h) {
      if (node.tag === "button" || node.tag === "field" || node.events.click) {
        if (!found) found = node;
      }
    }
  }
  for (let i = roots.length - 1; i >= 0; i--) walk(roots[i]);
  return found;
}

export function clearHover(roots) {
  function walk(n) {
    n.hover = false;
    for (const c of n.children) walk(c);
  }
  for (const r of roots) walk(r);
}

export function syncProps(node) {
  node.props.text = node.text != null ? String(node.text) : node.props.text;
  if (node.props.text != null) node.attrs.text = node.props.text;
  for (const c of node.children) syncProps(c);
}

export function createAppRuntime(ast) {
  const tree = buildTree(ast);
  const env = createEnv(tree.idIndex);

  const baseSet = env.set.bind(env);
  env.set = (path, value) => {
    baseSet(path, value);
    const w = tree.idIndex.get(path[0]);
    if (w && path[1] === "text") {
      w.props.text = String(value);
      w.text = String(value);
    }
  };

  return {
    ...tree,
    env,
    fire(node, eventName) {
      if (!node) return false;
      const handler = node.events[eventName];
      if (!handler) return false;
      runEvent(handler, env);
      for (const r of tree.roots) syncProps(r);
      return true;
    },
  };
}
