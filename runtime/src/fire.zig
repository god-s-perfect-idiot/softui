//! Doom-style fire for SoftASM `svc fb_fire`.
//! SoftASM passes integer phase (drives ember noise).

const MAX_W: usize = 480;
const MAX_H: usize = 270;

var heat: [MAX_W * MAX_H]u8 = undefined;
var fire_w: usize = 0;
var fire_h: usize = 0;

fn hash(n: u32) u32 {
    var x = n;
    x ^= x >> 16;
    x *%= 0x7feb352d;
    x ^= x >> 15;
    x *%= 0x846ca68b;
    x ^= x >> 16;
    return x;
}

fn palette(v: u8) struct { r: u8, g: u8, b: u8 } {
    // Black → deep red → orange → yellow → white.
    const t = @as(f32, @floatFromInt(v)) / 255.0;
    if (t < 0.15) {
        const u = t / 0.15;
        return .{ .r = @intFromFloat(u * 40.0), .g = 0, .b = @intFromFloat(u * 8.0) };
    } else if (t < 0.4) {
        const u = (t - 0.15) / 0.25;
        return .{
            .r = @intFromFloat(40.0 + u * 180.0),
            .g = @intFromFloat(u * 40.0),
            .b = @intFromFloat(8.0 * (1.0 - u)),
        };
    } else if (t < 0.7) {
        const u = (t - 0.4) / 0.3;
        return .{
            .r = 220,
            .g = @intFromFloat(40.0 + u * 160.0),
            .b = @intFromFloat(u * 20.0),
        };
    } else {
        const u = (t - 0.7) / 0.3;
        return .{
            .r = 255,
            .g = @intFromFloat(200.0 + u * 55.0),
            .b = @intFromFloat(20.0 + u * 200.0),
        };
    }
}

pub fn render(
    fb: []u8,
    width: u32,
    height: u32,
    stride: u32,
    phase: u32,
) void {
    // Simulate at reduced res for speed, then nearest-neighbor upscale.
    var fw = @as(usize, width) / 4;
    var fh = @as(usize, height) / 4;
    if (fw < 40) fw = @min(@as(usize, width), MAX_W);
    if (fh < 30) fh = @min(@as(usize, height), MAX_H);
    if (fw > MAX_W) fw = MAX_W;
    if (fh > MAX_H) fh = MAX_H;
    if (fw == 0 or fh == 0) return;

    if (fw != fire_w or fh != fire_h) {
        @memset(heat[0 .. fw * fh], 0);
        fire_w = fw;
        fire_h = fh;
    }

    // Seed bottom row with hot embers.
    const seed = phase *% 2654435761;
    var x: usize = 0;
    while (x < fw) : (x += 1) {
        const n = hash(seed +% @as(u32, @intCast(x)));
        const base: u8 = if ((n & 7) == 0) 0 else @truncate(160 + (n & 95));
        heat[(fh - 1) * fw + x] = base;
        if (fh >= 2) {
            heat[(fh - 2) * fw + x] = @truncate(@as(u16, base) * 3 / 4);
        }
    }

    // Rise and cool.
    var y: usize = 1;
    while (y < fh) : (y += 1) {
        const row = (fh - 1 - y) * fw;
        const below = (fh - y) * fw;
        x = 0;
        while (x < fw) : (x += 1) {
            const left = if (x == 0) x else x - 1;
            const right = if (x + 1 >= fw) x else x + 1;
            const sum: u32 =
                @as(u32, heat[below + x]) +
                @as(u32, heat[below + left]) +
                @as(u32, heat[below + right]) +
                @as(u32, heat[row + x]);
            var v: u32 = sum / 4;
            if (v > 1) v -= 1 + ((hash(seed +% @as(u32, @intCast(row + x))) >> 8) & 1);
            heat[row + x] = @truncate(v);
        }
    }

    // Upscale to framebuffer.
    const w: usize = width;
    const h: usize = height;
    var py: usize = 0;
    while (py < h) : (py += 1) {
        const sy = py * fh / h;
        var px: usize = 0;
        while (px < w) : (px += 1) {
            const sx = px * fw / w;
            const c = palette(heat[sy * fw + sx]);
            const o = py * @as(usize, stride) + px * 4;
            fb[o + 0] = c.r;
            fb[o + 1] = c.g;
            fb[o + 2] = c.b;
            fb[o + 3] = 255;
        }
    }
}
