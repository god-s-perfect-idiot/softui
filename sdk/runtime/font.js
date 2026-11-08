/** Simple monospace text for the SDK canvas preview. */

export const GLYPH_W = 8;
export const GLYPH_H = 14;

export function measureText(text, scale = 1) {
  return {
    w: String(text).length * GLYPH_W * scale,
    h: GLYPH_H * scale,
  };
}

export function drawText(ctx, text, x, y, color = "#d7e0ea", scale = 1) {
  const size = GLYPH_H * scale;
  ctx.fillStyle = color;
  ctx.font = `${size}px ui-monospace, "Cascadia Code", "Consolas", monospace`;
  ctx.textBaseline = "top";
  ctx.fillText(String(text), x, y);
}
