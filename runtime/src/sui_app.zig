//! SoftUI suigui host bridge — runs .sui from SoftFS via host_sui_paint.

const gfx = @import("demo_gfx.zig");
const hostapi = @import("hostapi.zig");
const input = @import("input.zig");

var source: [8192]u8 = undefined;
var source_len: usize = 0;
var source_name: []const u8 = "(none)";
var last_ptr_kind: u32 = 0;
var paint_rc: i32 = -1;

pub fn reset() void {
    source_len = 0;
    source_name = "(none)";
    last_ptr_kind = 0;
    paint_rc = -1;
}

pub fn loadSource(name: []const u8, data: []const u8) void {
    source_name = name;
    source_len = @min(data.len, source.len);
    @memcpy(source[0..source_len], data[0..source_len]);
    paint_rc = -1;
}

pub fn render(fb: []u8, width: u32, height: u32, stride: u32, phase: u32) void {
    _ = phase;
    if (source_len == 0) {
        gfx.clear(fb, stride, width, height, gfx.COLOR_BG);
        gfx.drawText(fb, stride, width, height, 12, 40, "suigui", gfx.COLOR_DIM);
        gfx.drawText(fb, stride, width, height, 12, 60, "no .sui loaded", gfx.COLOR_WARN);
        return;
    }

    const p = input.latest;
    var ev: u32 = 0;
    if (p.kind == 0) ev = 1;
    if (p.kind == 1) ev = 2;
    // Fire click once per down edge.
    if (p.kind == 1 and last_ptr_kind != 1) {
        ev = 2;
    } else if (p.kind == 0 or (p.buttons & 1) != 0) {
        ev = 1;
    } else {
        ev = 0;
    }
    last_ptr_kind = p.kind;

    // Content area below SoftUI chrome (BAR_H=24). Paint into a temp region by
    // offsetting: host paints full FB; chrome redraws on top afterward.
    paint_rc = hostapi.suiPaint(source[0..source_len], fb, width, height, stride, ev, p.x, p.y);
    if (paint_rc != 0) {
        gfx.clear(fb, stride, width, height, gfx.COLOR_BG);
        gfx.drawText(fb, stride, width, height, 12, 40, "suigui bridge", gfx.COLOR_DIM);
        gfx.drawText(fb, stride, width, height, 12, 60, source_name, gfx.COLOR_FG);
        gfx.drawText(fb, stride, width, height, 12, 80, "host_sui_paint failed", gfx.COLOR_WARN);
        gfx.drawText(fb, stride, width, height, 12, 100, "Esc / exit to leave", gfx.COLOR_DIM);
    }
}
