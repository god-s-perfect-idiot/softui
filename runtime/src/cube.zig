//! Rotating shaded cube for SoftASM `svc fb_cube`.
//! SoftASM passes integer phase (mod 1024 = one turn).

const TAU: f32 = 6.28318530718;
const PHASE: f32 = TAU / 1024.0;

const Vert = struct { x: f32, y: f32, z: f32 };

const Face = struct {
    i0: u8,
    i1: u8,
    i2: u8,
    i3: u8,
    r: u8,
    g: u8,
    b: u8,
};

const verts_base = [_]Vert{
    .{ .x = -1, .y = -1, .z = -1 },
    .{ .x = 1, .y = -1, .z = -1 },
    .{ .x = 1, .y = 1, .z = -1 },
    .{ .x = -1, .y = 1, .z = -1 },
    .{ .x = -1, .y = -1, .z = 1 },
    .{ .x = 1, .y = -1, .z = 1 },
    .{ .x = 1, .y = 1, .z = 1 },
    .{ .x = -1, .y = 1, .z = 1 },
};

const faces = [_]Face{
    .{ .i0 = 0, .i1 = 1, .i2 = 2, .i3 = 3, .r = 210, .g = 150, .b = 70 }, // -Z brass
    .{ .i0 = 5, .i1 = 4, .i2 = 7, .i3 = 6, .r = 90, .g = 170, .b = 190 }, // +Z teal
    .{ .i0 = 4, .i1 = 0, .i2 = 3, .i3 = 7, .r = 180, .g = 90, .b = 90 }, // -X clay
    .{ .i0 = 1, .i1 = 5, .i2 = 6, .i3 = 2, .r = 120, .g = 160, .b = 90 }, // +X olive
    .{ .i0 = 3, .i1 = 2, .i2 = 6, .i3 = 7, .r = 200, .g = 180, .b = 110 }, // +Y sand
    .{ .i0 = 4, .i1 = 5, .i2 = 1, .i3 = 0, .r = 100, .g = 110, .b = 150 }, // -Y slate
};

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

fn drawLine(fb: []u8, stride: u32, w: usize, h: usize, x0: i32, y0: i32, x1: i32, y1: i32, r: u8, g: u8, b: u8) void {
    var x = x0;
    var y = y0;
    const dx: i32 = if (x1 >= x0) x1 - x0 else x0 - x1;
    const sx: i32 = if (x0 < x1) 1 else -1;
    const dy: i32 = if (y1 >= y0) y0 - y1 else y1 - y0;
    const sy: i32 = if (y0 < y1) 1 else -1;
    var err = dx + dy;
    while (true) {
        plot(fb, stride, w, h, x, y, r, g, b);
        if (x == x1 and y == y1) break;
        const e2 = err * 2;
        if (e2 >= dy) {
            err += dy;
            x += sx;
        }
        if (e2 <= dx) {
            err += dx;
            y += sy;
        }
    }
}

fn fillTri(
    fb: []u8,
    stride: u32,
    w: usize,
    h: usize,
    ax: i32,
    ay: i32,
    bx: i32,
    by: i32,
    cx: i32,
    cy: i32,
    r: u8,
    g: u8,
    b: u8,
) void {
    const min_x = @max(@as(i32, 0), @min(ax, @min(bx, cx)));
    const max_x = @min(@as(i32, @intCast(w)) - 1, @max(ax, @max(bx, cx)));
    const min_y = @max(@as(i32, 0), @min(ay, @min(by, cy)));
    const max_y = @min(@as(i32, @intCast(h)) - 1, @max(ay, @max(by, cy)));
    if (min_x > max_x or min_y > max_y) return;

    const area = (bx - ax) * (cy - ay) - (by - ay) * (cx - ax);
    if (area == 0) return;

    var y = min_y;
    while (y <= max_y) : (y += 1) {
        var x = min_x;
        while (x <= max_x) : (x += 1) {
            const w0 = (bx - ax) * (y - ay) - (by - ay) * (x - ax);
            const w1 = (cx - bx) * (y - by) - (cy - by) * (x - bx);
            const w2 = (ax - cx) * (y - cy) - (ay - cy) * (x - cx);
            if ((area > 0 and w0 >= 0 and w1 >= 0 and w2 >= 0) or
                (area < 0 and w0 <= 0 and w1 <= 0 and w2 <= 0))
            {
                plot(fb, stride, w, h, x, y, r, g, b);
            }
        }
    }
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

    var y: usize = 0;
    while (y < h) : (y += 1) {
        var x: usize = 0;
        while (x < w) : (x += 1) {
            const o = y * @as(usize, stride) + x * 4;
            fb[o + 0] = 12;
            fb[o + 1] = 14;
            fb[o + 2] = 20;
            fb[o + 3] = 255;
        }
    }

    const A = @as(f32, @floatFromInt(phase & 1023)) * PHASE;
    const B = A * 0.67;
    const cosA = @cos(A);
    const sinA = @sin(A);
    const cosB = @cos(B);
    const sinB = @sin(B);

    const cx: f32 = @as(f32, @floatFromInt(width)) * 0.5;
    const cy: f32 = @as(f32, @floatFromInt(height)) * 0.5;
    const k: f32 = @as(f32, @floatFromInt(@min(width, height))) * 0.28;

    var proj: [8]struct { x: i32, y: i32, z: f32 } = undefined;
    for (verts_base, 0..) |v, i| {
        // Rotate Y then X.
        const x1 = v.x * cosB + v.z * sinB;
        const z1 = -v.x * sinB + v.z * cosB;
        const y2 = v.y * cosA - z1 * sinA;
        const z2 = v.y * sinA + z1 * cosA;
        const z_off = z2 + 4.0;
        const ooz = 1.0 / z_off;
        proj[i] = .{
            .x = @intFromFloat(cx + k * x1 * ooz),
            .y = @intFromFloat(cy - k * y2 * ooz),
            .z = z_off,
        };
    }

    // Sort faces by average depth (painter's algorithm, far→near).
    var order: [6]u8 = .{ 0, 1, 2, 3, 4, 5 };
    var a: usize = 0;
    while (a < 5) : (a += 1) {
        var b_i: usize = a + 1;
        while (b_i < 6) : (b_i += 1) {
            const fa = faces[order[a]];
            const fb_f = faces[order[b_i]];
            const za = (proj[fa.i0].z + proj[fa.i1].z + proj[fa.i2].z + proj[fa.i3].z) * 0.25;
            const zb = (proj[fb_f.i0].z + proj[fb_f.i1].z + proj[fb_f.i2].z + proj[fb_f.i3].z) * 0.25;
            if (za < zb) {
                const tmp = order[a];
                order[a] = order[b_i];
                order[b_i] = tmp;
            }
        }
    }

    for (order) |fi| {
        const f = faces[fi];
        const p0 = proj[f.i0];
        const p1 = proj[f.i1];
        const p2 = proj[f.i2];
        const p3 = proj[f.i3];

        // Back-face cull via projected cross.
        const ax = p1.x - p0.x;
        const ay = p1.y - p0.y;
        const bx = p3.x - p0.x;
        const by = p3.y - p0.y;
        if (ax * by - ay * bx <= 0) continue;

        // Simple lighting from face average z (closer = brighter).
        const zavg = (p0.z + p1.z + p2.z + p3.z) * 0.25;
        var lum = 1.35 - zavg * 0.18;
        if (lum < 0.35) lum = 0.35;
        if (lum > 1.0) lum = 1.0;
        const r: u8 = @intFromFloat(@as(f32, @floatFromInt(f.r)) * lum);
        const g: u8 = @intFromFloat(@as(f32, @floatFromInt(f.g)) * lum);
        const b: u8 = @intFromFloat(@as(f32, @floatFromInt(f.b)) * lum);

        fillTri(fb, stride, w, h, p0.x, p0.y, p1.x, p1.y, p2.x, p2.y, r, g, b);
        fillTri(fb, stride, w, h, p0.x, p0.y, p2.x, p2.y, p3.x, p3.y, r, g, b);

        // Edge highlight.
        const er: u8 = @min(255, @as(u16, r) + 40);
        const eg: u8 = @min(255, @as(u16, g) + 40);
        const eb: u8 = @min(255, @as(u16, b) + 40);
        drawLine(fb, stride, w, h, p0.x, p0.y, p1.x, p1.y, er, eg, eb);
        drawLine(fb, stride, w, h, p1.x, p1.y, p2.x, p2.y, er, eg, eb);
        drawLine(fb, stride, w, h, p2.x, p2.y, p3.x, p3.y, er, eg, eb);
        drawLine(fb, stride, w, h, p3.x, p3.y, p0.x, p0.y, er, eg, eb);
    }
}
