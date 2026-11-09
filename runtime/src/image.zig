//! Image viewer — SoftUI SIMG decode + Host ABI PNG/JPEG decode.

const gfx = @import("demo_gfx.zig");
const hostapi = @import("hostapi.zig");

const MAX_RGBA: usize = 256 * 256 * 4;
var rgba: [MAX_RGBA]u8 = undefined;
var img_w: u32 = 0;
var img_h: u32 = 0;
var status: enum { empty, simg, host_pending, host_ok, fail } = .empty;
var source_name: []const u8 = "(none)";

pub fn reset() void {
    img_w = 0;
    img_h = 0;
    status = .empty;
    source_name = "(none)";
}

/// Load image bytes from SoftFS (SIMG or host-decodable).
pub fn loadBytes(name: []const u8, data: []const u8) void {
    source_name = name;
    img_w = 0;
    img_h = 0;
    if (data.len >= 12 and data[0] == 'S' and data[1] == 'I' and data[2] == 'M' and data[3] == 'G') {
        const w = stdMemReadU32(data[4..8]);
        const h = stdMemReadU32(data[8..12]);
        const need = @as(usize, w) * @as(usize, h) * 4;
        if (w == 0 or h == 0 or 12 + need > data.len or need > MAX_RGBA) {
            status = .fail;
            return;
        }
        @memcpy(rgba[0..need], data[12 .. 12 + need]);
        img_w = w;
        img_h = h;
        status = .simg;
        return;
    }
    // Host decode path (PNG/JPEG/…)
    var ow: u32 = 0;
    var oh: u32 = 0;
    if (hostapi.imageDecode(data, rgba[0..], &ow, &oh)) {
        img_w = ow;
        img_h = oh;
        status = .host_ok;
        return;
    }
    // Pending or fail — keep trying in render for pending.
    status = .host_pending;
    stashPending(data);
}

var pending: [96 * 1024]u8 = undefined;
var pending_len: usize = 0;

fn stashPending(data: []const u8) void {
    pending_len = @min(data.len, pending.len);
    @memcpy(pending[0..pending_len], data[0..pending_len]);
}

fn retryHost() void {
    if (pending_len == 0) return;
    var ow: u32 = 0;
    var oh: u32 = 0;
    if (hostapi.imageDecode(pending[0..pending_len], rgba[0..], &ow, &oh)) {
        img_w = ow;
        img_h = oh;
        status = .host_ok;
    }
}

fn stdMemReadU32(b: []const u8) u32 {
    return @as(u32, b[0]) | (@as(u32, b[1]) << 8) | (@as(u32, b[2]) << 16) | (@as(u32, b[3]) << 24);
}

pub fn render(fb: []u8, width: u32, height: u32, stride: u32, phase: u32) void {
    _ = phase;
    if (status == .host_pending) retryHost();

    gfx.clear(fb, stride, width, height, gfx.COLOR_BG);
    gfx.drawText(fb, stride, width, height, 12, 36, "IMAGE VIEWER", gfx.COLOR_DIM);

    var info: [40]u8 = undefined;
    var n: usize = 0;
    for (source_name) |c| {
        if (n >= 20) break;
        info[n] = c;
        n += 1;
    }
    if (n < info.len) {
        info[n] = ' ';
        n += 1;
    }
    const tag: []const u8 = switch (status) {
        .empty => "empty",
        .simg => "SIMG",
        .host_pending => "decode...",
        .host_ok => "host",
        .fail => "FAIL",
    };
    for (tag) |c| {
        if (n >= info.len) break;
        info[n] = c;
        n += 1;
    }
    gfx.drawText(fb, stride, width, height, 12, 52, info[0..n], gfx.COLOR_ACCENT);

    const margin: u32 = 12;
    const top: u32 = 72;
    const box_w = if (width > margin * 2) width - margin * 2 else width;
    const box_h = if (height > top + 40) height - top - 40 else 40;

    if (img_w > 0 and img_h > 0) {
        // Nearest-neighbor scale into box.
        var y: u32 = 0;
        while (y < box_h) : (y += 1) {
            const sy = (y * img_h) / box_h;
            var x: u32 = 0;
            while (x < box_w) : (x += 1) {
                const sx = (x * img_w) / box_w;
                const o: usize = (@as(usize, sy) * @as(usize, img_w) + @as(usize, sx)) * 4;
                if (o + 3 >= MAX_RGBA) break;
                const color: u32 = (@as(u32, rgba[o + 3]) << 24) |
                    (@as(u32, rgba[o + 0]) << 16) |
                    (@as(u32, rgba[o + 1]) << 8) |
                    rgba[o + 2];
                gfx.put(fb, stride, width, height, margin + x, top + y, color);
            }
        }
        gfx.rect(fb, stride, width, height, margin, top, box_w, box_h, gfx.COLOR_FG);
        var dim_buf: [24]u8 = undefined;
        const dim = gfx.formatPair(&dim_buf, img_w, 'x', img_h);
        gfx.drawText(fb, stride, width, height, 12, height -| 36, dim, gfx.COLOR_DIM);
    } else {
        // Fallback procedural while pending / empty.
        var y: u32 = 0;
        while (y < box_h) : (y += 1) {
            var x: u32 = 0;
            while (x < box_w) : (x += 1) {
                const cell = ((x / 8) + (y / 8)) & 1;
                const color: u32 = if (cell == 0) 0xFF1A3048 else 0xFF101820;
                gfx.put(fb, stride, width, height, margin + x, top + y, color);
            }
        }
        gfx.rect(fb, stride, width, height, margin, top, box_w, box_h, gfx.COLOR_BORDER);
        const msg: []const u8 = if (status == .host_pending) "decoding..." else "no image loaded";
        gfx.drawText(fb, stride, width, height, 12, top + box_h / 2, msg, gfx.COLOR_DIM);
    }

    gfx.drawText(fb, stride, width, height, 12, height -| 20, "Esc / exit to leave", gfx.COLOR_DIM);
}
