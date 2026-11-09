//! Typography / glyph demo — SoftUI bitmap font coverage.

const gfx = @import("demo_gfx.zig");
const font = @import("font.zig");

pub fn render(fb: []u8, width: u32, height: u32, stride: u32, phase: u32) void {
    _ = phase;
    gfx.clear(fb, stride, width, height, gfx.COLOR_BG);
    const line = font.GLYPH_H + 4;
    gfx.drawText(fb, stride, width, height, 12, 36, "TEXT / GLYPHS", gfx.COLOR_DIM);
    gfx.drawText(fb, stride, width, height, 12, 36 + line, "SoftUI 12x16 humanist font", gfx.COLOR_DIM);

    gfx.drawText(fb, stride, width, height, 12, 36 + line * 2 + 4, "The quick brown fox", gfx.COLOR_FG);
    gfx.drawText(fb, stride, width, height, 12, 36 + line * 3 + 4, "jumps over the lazy dog", gfx.COLOR_FG);
    gfx.drawText(fb, stride, width, height, 12, 36 + line * 4 + 4, "0123456789 +-*/=()[]{}", gfx.COLOR_ACCENT);

    // Full printable ASCII grid
    var ch: u8 = font.FIRST;
    var x: u32 = 12;
    var y: u32 = 36 + line * 5 + 12;
    const right = if (width > 12) width - 12 else width;
    while (ch <= font.LAST) : (ch += 1) {
        const adv = font.advance(ch);
        if (x + adv > right) {
            x = 12;
            y += font.GLYPH_H + 2;
            if (y + font.GLYPH_H >= height -| 28) break;
        }
        gfx.drawGlyph(fb, stride, width, height, x, y, ch, gfx.COLOR_FG);
        x += adv + 1;
    }

    gfx.drawText(fb, stride, width, height, 12, height -| 20, "Esc / exit to leave", gfx.COLOR_DIM);
}
