/** Humanist UI text for the SDK canvas preview (proportional, matches SoftUI). */

export const GLYPH_W = 12;
export const GLYPH_H = 18;

const FONT_STACK = `"Segoe UI Variable", "Segoe UI", "Trebuchet MS", system-ui, sans-serif`;

let measureCtx = null;

function fontCss(scale = 1) {
  return `500 ${GLYPH_H * scale}px ${FONT_STACK}`;
}

export function measureText(text, scale = 1) {
  if (!measureCtx) {
    const c = typeof OffscreenCanvas !== "undefined"
      ? new OffscreenCanvas(1, 1)
      : document.createElement("canvas");
    measureCtx = c.getContext("2d");
  }
  measureCtx.font = fontCss(scale);
  return {
    w: Math.ceil(measureCtx.measureText(String(text)).width),
    h: GLYPH_H * scale,
  };
}

/**
 * Soft UI text. Under a ≥2× CTM, a tiny blur is invisible — soften in user
 * space with a wider blur plus a low-alpha ring so curves lose hard stairs.
 */
export function drawText(ctx, text, x, y, color = "#d7e0ea", scale = 1) {
  const s = String(text);
  if (!s) return;

  ctx.save();
  ctx.fillStyle = color;
  ctx.font = fontCss(scale);
  ctx.textBaseline = "top";
  ctx.textAlign = "left";

  // Wide halo in user space (survives CTM scale) — softens curve stairs.
  if ("filter" in ctx) ctx.filter = "blur(1.6px)";
  ctx.globalAlpha = 0.65;
  ctx.fillText(s, x, y);

  if ("filter" in ctx) ctx.filter = "none";
  ctx.globalAlpha = 0.28;
  const o = 0.7;
  ctx.fillText(s, x - o, y);
  ctx.fillText(s, x + o, y);
  ctx.fillText(s, x, y - o);
  ctx.fillText(s, x, y + o);
  ctx.fillText(s, x - o * 0.75, y - o * 0.75);
  ctx.fillText(s, x + o * 0.75, y - o * 0.75);
  ctx.fillText(s, x - o * 0.75, y + o * 0.75);
  ctx.fillText(s, x + o * 0.75, y + o * 0.75);

  // Body slightly translucent so the soft edge remains visible.
  ctx.globalAlpha = 0.88;
  ctx.fillText(s, x, y);
  ctx.restore();
}
