//! Spinning torus for SoftASM `svc fb_donut`.
//! SoftASM passes integer phases (mod 1024 = one turn).

const std = @import("std");

const TAU: f32 = 6.28318530718;
const PHASE: f32 = TAU / 1024.0;

var zbuf: [1920 * 1080]f32 = undefined;

pub fn render(
    fb: []u8,
    width: u32,
    height: u32,
    stride: u32,
    phase_a: u32,
    phase_b: u32,
) void {
    const w: usize = width;
    const h: usize = height;
    if (w == 0 or h == 0 or w * h > zbuf.len) return;

    var y: usize = 0;
    while (y < h) : (y += 1) {
        var x: usize = 0;
        while (x < w) : (x += 1) {
            const o = y * @as(usize, stride) + x * 4;
            fb[o + 0] = 8;
            fb[o + 1] = 10;
            fb[o + 2] = 16;
            fb[o + 3] = 255;
            zbuf[y * w + x] = 0;
        }
    }

    const A = @as(f32, @floatFromInt(phase_a & 1023)) * PHASE;
    const B = @as(f32, @floatFromInt(phase_b & 1023)) * PHASE;
    const cosA = @cos(A);
    const sinA = @sin(A);
    const cosB = @cos(B);
    const sinB = @sin(B);

    const min_dim: f32 = @floatFromInt(@min(width, height));
    const k1: f32 = min_dim * 0.55;
    const cx: f32 = @as(f32, @floatFromInt(width)) * 0.5;
    const cy: f32 = @as(f32, @floatFromInt(height)) * 0.5;

    const R1: f32 = 1.0;
    const R2: f32 = 2.0;

    var theta: f32 = 0;
    while (theta < TAU) : (theta += 0.04) {
        const cost = @cos(theta);
        const sint = @sin(theta);
        var phi: f32 = 0;
        while (phi < TAU) : (phi += 0.012) {
            const cosp = @cos(phi);
            const sinp = @sin(phi);

            // Point on torus.
            const circle_x = R2 + R1 * cost;
            const x = circle_x * cosp;
            const yv = R1 * sint;
            const z = circle_x * sinp;

            // Rotate: X by A, then Y by B.
            const y2 = yv * cosA - z * sinA;
            const z2 = yv * sinA + z * cosA;
            const x3 = x * cosB + z2 * sinB;
            const z3 = -x * sinB + z2 * cosB;
            const y3 = y2;

            const z_off = z3 + 5.0;
            if (z_off <= 0.1) continue;
            const ooz = 1.0 / z_off;

            const xp: i32 = @intFromFloat(cx + k1 * x3 * ooz);
            const yp: i32 = @intFromFloat(cy - k1 * y3 * ooz);
            if (xp < 0 or yp < 0) continue;
            const xu: usize = @intCast(xp);
            const yu: usize = @intCast(yp);
            if (xu >= w or yu >= h) continue;

            const idx = yu * w + xu;
            if (ooz <= zbuf[idx]) continue;
            zbuf[idx] = ooz;

            // Surface normal luminance (L = (0, 1, -1) normalized-ish).
            const nx = cosp * cost * cosB - sint * sinB;
            const ny = cosp * cost * sinA * sinB + sint * cosA;
            const nz = -cosp * cost * cosA;
            var lum = ny * 0.6 - nz * 0.45 + nx * 0.15 + 0.25;
            if (lum < 0) lum = 0;
            if (lum > 1) lum = 1;

            // Warm metal palette.
            const r: u8 = @intFromFloat(50.0 + lum * 205.0);
            const g: u8 = @intFromFloat(70.0 + lum * 160.0);
            const b: u8 = @intFromFloat(90.0 + lum * 110.0);

            plot(fb, stride, w, h, xu, yu, r, g, b);
            if (xu + 1 < w) plot(fb, stride, w, h, xu + 1, yu, r, g, b);
            if (yu + 1 < h) plot(fb, stride, w, h, xu, yu + 1, r, g, b);
            if (xu + 1 < w and yu + 1 < h) plot(fb, stride, w, h, xu + 1, yu + 1, r, g, b);
        }
    }
}

fn plot(fb: []u8, stride: u32, w: usize, h: usize, x: usize, y: usize, r: u8, g: u8, b: u8) void {
    _ = w;
    _ = h;
    const o = y * @as(usize, stride) + x * 4;
    fb[o + 0] = r;
    fb[o + 1] = g;
    fb[o + 2] = b;
    fb[o + 3] = 255;
}
