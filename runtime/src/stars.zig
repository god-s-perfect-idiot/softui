//! 3D starfield for SoftASM `svc fb_stars`.
//! SoftASM passes integer phase (drives travel distance).

const STAR_COUNT: usize = 256;

const Star = struct {
    x: f32,
    y: f32,
    z: f32,
};

var stars: [STAR_COUNT]Star = undefined;
var seeded: bool = false;

fn hash(n: u32) u32 {
    var x = n;
    x ^= x >> 16;
    x *%= 0x7feb352d;
    x ^= x >> 15;
    x *%= 0x846ca68b;
    x ^= x >> 16;
    return x;
}

fn seedStars() void {
    var i: usize = 0;
    while (i < STAR_COUNT) : (i += 1) {
        const h1 = hash(@as(u32, @intCast(i)) *% 2654435761);
        const h2 = hash(h1 ^ 0x9e3779b9);
        const h3 = hash(h2 ^ 0x85ebca6b);
        stars[i] = .{
            .x = (@as(f32, @floatFromInt(h1 & 0xffff)) / 32768.0) - 1.0,
            .y = (@as(f32, @floatFromInt(h2 & 0xffff)) / 32768.0) - 1.0,
            .z = 0.15 + (@as(f32, @floatFromInt(h3 & 0xffff)) / 65535.0) * 0.85,
        };
    }
    seeded = true;
}

fn plot(fb: []u8, stride: u32, w: usize, h: usize, x: i32, y: i32, r: u8, g: u8, b: u8) void {
    if (x < 0 or y < 0) return;
    const xu: usize = @intCast(x);
    const yu: usize = @intCast(y);
    if (xu >= w or yu >= h) return;
    const o = yu * @as(usize, stride) + xu * 4;
    fb[o + 0] = r;
    fb[o + 1] = g;
    fb[o + 2] = b;
    fb[o + 3] = 255;
}

pub fn render(
    fb: []u8,
    width: u32,
    height: u32,
    stride: u32,
    phase: u32,
) void {
    const w: usize = width;
    const h: usize = height;
    if (w == 0 or h == 0) return;
    if (!seeded) seedStars();

    // Deep space clear.
    var yi: usize = 0;
    while (yi < h) : (yi += 1) {
        var xi: usize = 0;
        while (xi < w) : (xi += 1) {
            const o = yi * @as(usize, stride) + xi * 4;
            fb[o + 0] = 4;
            fb[o + 1] = 5;
            fb[o + 2] = 10;
            fb[o + 3] = 255;
        }
    }

    const cx: f32 = @as(f32, @floatFromInt(width)) * 0.5;
    const cy: f32 = @as(f32, @floatFromInt(height)) * 0.5;
    const scale: f32 = @as(f32, @floatFromInt(@min(width, height))) * 0.55;
    const travel = @as(f32, @floatFromInt(phase & 1023)) * (0.012 / 1024.0) * 1024.0;

    var i: usize = 0;
    while (i < STAR_COUNT) : (i += 1) {
        var z = stars[i].z - travel;
        // Wrap into (0.05, 1.0]
        while (z <= 0.05) z += 0.95;
        while (z > 1.0) z -= 0.95;

        const ooz = 1.0 / z;
        const sx = cx + stars[i].x * scale * ooz;
        const sy = cy + stars[i].y * scale * ooz;

        // Motion streak toward previous z.
        const z_prev = @min(z + 0.04, 1.0);
        const ooz_p = 1.0 / z_prev;
        const px = cx + stars[i].x * scale * ooz_p;
        const py = cy + stars[i].y * scale * ooz_p;

        const bright = (1.0 - z) * (1.0 - z);
        const c: u8 = @intFromFloat(80.0 + bright * 175.0);
        const warm: u8 = @intFromFloat(bright * 40.0);

        // Draw streak.
        const steps: i32 = 6;
        var s: i32 = 0;
        while (s <= steps) : (s += 1) {
            const t = @as(f32, @floatFromInt(s)) / @as(f32, @floatFromInt(steps));
            const x = @as(i32, @intFromFloat(px + (sx - px) * t));
            const y = @as(i32, @intFromFloat(py + (sy - py) * t));
            const fade: u8 = @intFromFloat(@as(f32, @floatFromInt(c)) * (0.35 + 0.65 * t));
            plot(fb, stride, w, h, x, y, fade, fade, @min(255, fade +% warm));
            if (bright > 0.55) {
                plot(fb, stride, w, h, x + 1, y, fade / 2, fade / 2, fade / 2);
                plot(fb, stride, w, h, x, y + 1, fade / 2, fade / 2, fade / 2);
            }
        }
    }
}
