//! Pointer tracker — exercises softui_push_pointer + latest position.

const gfx = @import("demo_gfx.zig");
const input = @import("input.zig");

pub fn render(fb: []u8, width: u32, height: u32, stride: u32, phase: u32) void {
    _ = phase;
    gfx.clear(fb, stride, width, height, gfx.COLOR_BG);

    const p = input.latest;
    const x = p.x;
    const y = p.y;
    const down = (p.buttons & 1) != 0;

    gfx.drawText(fb, stride, width, height, 12, 36, "CURSOR TRACKER", gfx.COLOR_DIM);

    var line: [40]u8 = undefined;
    var i: usize = 0;
    const pref = "pos ";
    for (pref) |c| {
        line[i] = c;
        i += 1;
    }
    i = gfx.writeU32(&line, i, x);
    if (i < line.len) {
        line[i] = ',';
        i += 1;
    }
    i = gfx.writeU32(&line, i, y);
    gfx.drawText(fb, stride, width, height, 12, 56, line[0..i], gfx.COLOR_FG);

    var btn_line: [24]u8 = undefined;
    const btn_txt = if (down) "button DOWN" else "button up  ";
    @memcpy(btn_line[0..btn_txt.len], btn_txt);
    gfx.drawText(fb, stride, width, height, 12, 72, btn_line[0..btn_txt.len], if (down) gfx.COLOR_OK else gfx.COLOR_DIM);

    var kind_buf: [20]u8 = undefined;
    i = 0;
    const kpref = "kind ";
    for (kpref) |c| {
        kind_buf[i] = c;
        i += 1;
    }
    i = gfx.writeU32(&kind_buf, i, p.kind);
    gfx.drawText(fb, stride, width, height, 12, 88, kind_buf[0..i], gfx.COLOR_DIM);

    gfx.drawText(fb, stride, width, height, 12, 112, "move pointer across FB", gfx.COLOR_DIM);
    gfx.drawText(fb, stride, width, height, 12, 128, "Esc / exit to leave", gfx.COLOR_DIM);

    // Crosshair
    if (x < width and y < height) {
        const arm: u32 = 16;
        const x0 = if (x > arm) x - arm else 0;
        const y0 = if (y > arm) y - arm else 0;
        gfx.hline(fb, stride, width, height, x0, y, arm * 2 + 1, if (down) gfx.COLOR_OK else gfx.COLOR_ACCENT);
        gfx.vline(fb, stride, width, height, x, y0, arm * 2 + 1, if (down) gfx.COLOR_OK else gfx.COLOR_ACCENT);
        gfx.rect(fb, stride, width, height, x -| 3, y -| 3, 7, 7, gfx.COLOR_FG);
    }

    // Trail ticks in corners for bounds.
    gfx.put(fb, stride, width, height, 0, 0, gfx.COLOR_ACCENT);
    gfx.put(fb, stride, width, height, width -| 1, 0, gfx.COLOR_ACCENT);
    gfx.put(fb, stride, width, height, 0, height -| 1, gfx.COLOR_ACCENT);
    gfx.put(fb, stride, width, height, width -| 1, height -| 1, gfx.COLOR_ACCENT);
}
