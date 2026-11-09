//! Pointer paint canvas — drag to draw, C clears.

const gfx = @import("demo_gfx.zig");
const input = @import("input.zig");

const MAX_W: usize = 640;
const MAX_H: usize = 480;

var ink: [MAX_W * MAX_H]u8 = undefined;
var ink_w: usize = 0;
var ink_h: usize = 0;
var last_x: i32 = -1;
var last_y: i32 = -1;

pub fn reset() void {
    @memset(ink[0..], 0);
    ink_w = 0;
    ink_h = 0;
    last_x = -1;
    last_y = -1;
}

pub fn onKey(key: u32) void {
    if (key == 'c' or key == 'C') {
        @memset(ink[0..], 0);
        last_x = -1;
        last_y = -1;
    }
}

fn ensure(w: u32, h: u32) void {
    const ww: usize = @min(@as(usize, w), MAX_W);
    const hh: usize = @min(@as(usize, h), MAX_H);
    if (ww != ink_w or hh != ink_h) {
        @memset(ink[0..], 0);
        ink_w = ww;
        ink_h = hh;
        last_x = -1;
        last_y = -1;
    }
}

fn stamp(x: u32, y: u32) void {
    if (ink_w == 0 or ink_h == 0) return;
    const x0: i32 = @as(i32, @intCast(x)) - 1;
    const y0: i32 = @as(i32, @intCast(y)) - 1;
    var dy: i32 = 0;
    while (dy < 3) : (dy += 1) {
        var dx: i32 = 0;
        while (dx < 3) : (dx += 1) {
            const px = x0 + dx;
            const py = y0 + dy;
            if (px < 0 or py < 0) continue;
            const xu: usize = @intCast(px);
            const yu: usize = @intCast(py);
            if (xu >= ink_w or yu >= ink_h) continue;
            ink[yu * ink_w + xu] = 255;
        }
    }
}

fn stroke(x0: i32, y0: i32, x1: i32, y1: i32) void {
    var x = x0;
    var y = y0;
    const dx: i32 = if (x1 >= x0) x1 - x0 else x0 - x1;
    const dy: i32 = if (y1 >= y0) y1 - y0 else y0 - y1;
    const sx: i32 = if (x0 < x1) 1 else -1;
    const sy: i32 = if (y0 < y1) 1 else -1;
    var err = dx - dy;
    while (true) {
        if (x >= 0 and y >= 0) stamp(@intCast(x), @intCast(y));
        if (x == x1 and y == y1) break;
        const e2 = err * 2;
        if (e2 > -dy) {
            err -= dy;
            x += sx;
        }
        if (e2 < dx) {
            err += dx;
            y += sy;
        }
    }
}

pub fn render(fb: []u8, width: u32, height: u32, stride: u32, phase: u32) void {
    _ = phase;
    ensure(width, height);
    gfx.clear(fb, stride, width, height, gfx.COLOR_BG);

    const p = input.latest;
    const down = (p.buttons & 1) != 0;
    if (down and p.x < width and p.y < height and p.y >= 24) {
        const cx: i32 = @intCast(p.x);
        const cy: i32 = @intCast(p.y);
        if (last_x >= 0 and last_y >= 0) {
            stroke(last_x, last_y, cx, cy);
        } else {
            stamp(p.x, p.y);
        }
        last_x = cx;
        last_y = cy;
    } else {
        last_x = -1;
        last_y = -1;
    }

    // Blit ink
    var y: usize = 0;
    while (y < ink_h) : (y += 1) {
        var x: usize = 0;
        while (x < ink_w) : (x += 1) {
            if (ink[y * ink_w + x] != 0) {
                gfx.put(fb, stride, width, height, @intCast(x), @intCast(y), gfx.COLOR_ACCENT);
            }
        }
    }

    gfx.fill(fb, stride, width, height, 0, 0, width, 24, gfx.COLOR_BG);
    gfx.drawText(fb, stride, width, height, 12, 8, "PAINT  drag draw  C clear", gfx.COLOR_DIM);
}
