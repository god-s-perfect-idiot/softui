//! Keyboard event viewer — Esc exits; other keys are logged.

const gfx = @import("demo_gfx.zig");

const CAP: usize = 12;

var hist: [CAP]u32 = undefined;
var hist_len: usize = 0;
var last_mods: u32 = 0;

pub fn reset() void {
    @memset(hist[0..], 0);
    hist_len = 0;
    last_mods = 0;
}

pub fn pushKey(key: u32, mods: u32) void {
    last_mods = mods;
    if (hist_len < CAP) {
        hist[hist_len] = key;
        hist_len += 1;
        return;
    }
    var i: usize = 0;
    while (i + 1 < CAP) : (i += 1) hist[i] = hist[i + 1];
    hist[CAP - 1] = key;
}

pub fn render(fb: []u8, width: u32, height: u32, stride: u32, phase: u32) void {
    _ = phase;
    gfx.clear(fb, stride, width, height, gfx.COLOR_BG);
    gfx.drawText(fb, stride, width, height, 12, 36, "KEY TRACKER", gfx.COLOR_DIM);
    gfx.drawText(fb, stride, width, height, 12, 52, "type keys - Esc exits", gfx.COLOR_DIM);

    var mods_buf: [24]u8 = undefined;
    var i: usize = 0;
    const mpref = "mods ";
    for (mpref) |c| {
        mods_buf[i] = c;
        i += 1;
    }
    i = gfx.writeU32(&mods_buf, i, last_mods);
    gfx.drawText(fb, stride, width, height, 12, 72, mods_buf[0..i], gfx.COLOR_ACCENT);

    var row: u32 = 0;
    while (row < hist_len) : (row += 1) {
        const key = hist[hist_len - 1 - row];
        var line: [48]u8 = undefined;
        var n: usize = 0;
        const label = keyLabel(key);
        for (label) |c| {
            if (n >= line.len) break;
            line[n] = c;
            n += 1;
        }
        if (n + 2 < line.len) {
            line[n] = ' ';
            n += 1;
            line[n] = '#';
            n += 1;
        }
        n = gfx.writeU32(&line, n, key);
        const y = 96 + row * 14;
        if (y + 8 >= height) break;
        gfx.drawText(fb, stride, width, height, 12, y, line[0..n], if (row == 0) gfx.COLOR_FG else gfx.COLOR_DIM);
    }

    if (hist_len == 0) {
        gfx.drawText(fb, stride, width, height, 12, 96, "(no keys yet)", gfx.COLOR_DIM);
    }
}

fn keyLabel(key: u32) []const u8 {
    if (key == 8) return "Backspace";
    if (key == 9) return "Tab";
    if (key == 13) return "Enter";
    if (key == 27) return "Esc";
    if (key == 32) return "Space";
    if (key == 0x100) return "Left";
    if (key == 0x101) return "Right";
    if (key == 0x102) return "Up";
    if (key == 0x103) return "Down";
    if (key == 0x104) return "Home";
    if (key == 0x105) return "End";
    if (key == 0x106) return "Delete";
    if (key >= 32 and key < 127) {
        // Single printable char — return static via small trick.
        return printable(key);
    }
    return "Key";
}

var printable_buf: [1]u8 = .{0};
fn printable(key: u32) []const u8 {
    printable_buf[0] = @truncate(key);
    return printable_buf[0..1];
}
