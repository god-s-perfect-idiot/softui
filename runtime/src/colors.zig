//! Color / fill demo — palette + live swatch under pointer.

const gfx = @import("demo_gfx.zig");
const input = @import("input.zig");

const PALETTE = [_]u32{
    0xFFFFFFFF,
    0xFF50B4FF,
    0xFF3DDC97,
    0xFFE8A838,
    0xFFFF5A5A,
    0xFFB48EAD,
    0xFF88C0D0,
    0xFFECEFF4,
    0xFF4C566A,
    0xFF2E3440,
    0xFF000000,
    0xFFA3BE8C,
};

var selected: u32 = 1;

pub fn reset() void {
    selected = 1;
}

pub fn onKey(key: u32) void {
    if (key == 0x100) { // left
        selected = if (selected == 0) PALETTE.len - 1 else selected - 1;
        return;
    }
    if (key == 0x101 or key == ' ' or key == 13) {
        selected = (selected + 1) % PALETTE.len;
    }
}

pub fn render(fb: []u8, width: u32, height: u32, stride: u32, phase: u32) void {
    _ = phase;
    gfx.clear(fb, stride, width, height, gfx.COLOR_BG);
    gfx.drawText(fb, stride, width, height, 12, 36, "COLORS", gfx.COLOR_DIM);
    gfx.drawText(fb, stride, width, height, 12, 52, "arrows/Space cycle", gfx.COLOR_DIM);

    const color = PALETTE[selected];
    const sw_w = if (width > 24) width - 24 else width;
    gfx.fill(fb, stride, width, height, 12, 72, sw_w, 48, color);
    gfx.rect(fb, stride, width, height, 12, 72, sw_w, 48, gfx.COLOR_FG);

    var hex_buf: [16]u8 = undefined;
    const hex = formatHex(&hex_buf, color);
    gfx.drawText(fb, stride, width, height, 12, 128, hex, gfx.COLOR_FG);

    // Palette grid
    const cell: u32 = 28;
    const cols: u32 = 6;
    var i: u32 = 0;
    while (i < PALETTE.len) : (i += 1) {
        const cx = 12 + (i % cols) * (cell + 4);
        const cy = 152 + (i / cols) * (cell + 4);
        gfx.fill(fb, stride, width, height, cx, cy, cell, cell, PALETTE[i]);
        if (i == selected) {
            gfx.rect(fb, stride, width, height, cx, cy, cell, cell, gfx.COLOR_FG);
        } else {
            gfx.rect(fb, stride, width, height, cx, cy, cell, cell, gfx.COLOR_BORDER);
        }
    }

    // Pointer sample readout
    const p = input.latest;
    if (p.x < width and p.y < height) {
        const o: usize = @as(usize, p.y) * @as(usize, stride) + @as(usize, p.x) * 4;
        if (o + 2 < fb.len) {
            const r = fb[o + 0];
            const g = fb[o + 1];
            const b = fb[o + 2];
            var sample: [32]u8 = undefined;
            var n: usize = 0;
            const pref = "sample ";
            for (pref) |c| {
                sample[n] = c;
                n += 1;
            }
            n = gfx.writeU32(&sample, n, r);
            if (n < sample.len) {
                sample[n] = ',';
                n += 1;
            }
            n = gfx.writeU32(&sample, n, g);
            if (n < sample.len) {
                sample[n] = ',';
                n += 1;
            }
            n = gfx.writeU32(&sample, n, b);
            gfx.drawText(fb, stride, width, height, 12, height -| 36, sample[0..n], gfx.COLOR_DIM);
        }
    }
    gfx.drawText(fb, stride, width, height, 12, height -| 20, "Esc / exit to leave", gfx.COLOR_DIM);
}

fn formatHex(buf: *[16]u8, color: u32) []const u8 {
    const hex = "0123456789ABCDEF";
    buf[0] = '#';
    var shift: u5 = 20;
    var i: usize = 1;
    while (i <= 6) : (i += 1) {
        const nibble: u4 = @truncate((color >> shift) & 0xF);
        buf[i] = hex[nibble];
        if (shift >= 4) shift -= 4 else break;
    }
    return buf[0..7];
}
