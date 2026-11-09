//! SoftUI app icons — SIMG preferred; SVG accepted via Host ABI decode.
//! SoftFS names: `icons/<name>.simg` or `icons/<name>.svg`.

const hostapi = @import("hostapi.zig");

pub const ICON_SIZE: u32 = 64;
pub const MAX_ICONS: usize = 24;
const ICON_RGBA: usize = ICON_SIZE * ICON_SIZE * 4;
const MAX_SRC: usize = 96 * 1024;

const WP_MAX_W: u32 = 160;
const WP_MAX_H: u32 = 100;
const WP_RGBA: usize = WP_MAX_W * WP_MAX_H * 4;

const Slot = struct {
    rgba: []u8,
    cap: usize,
    w: u32 = 0,
    h: u32 = 0,
    ready: bool = false,
    pending: bool = false,
    src: [MAX_SRC]u8 = undefined,
    src_len: usize = 0,
};

var icon_rgba: [MAX_ICONS][ICON_RGBA]u8 = undefined;
var slots: [MAX_ICONS]Slot = undefined;
var slots_init: bool = false;

var wp_rgba: [WP_RGBA]u8 = undefined;
var wallpaper: Slot = undefined;
var wp_init: bool = false;

fn ensureInit() void {
    if (!slots_init) {
        var i: usize = 0;
        while (i < MAX_ICONS) : (i += 1) {
            slots[i] = .{
                .rgba = icon_rgba[i][0..],
                .cap = ICON_RGBA,
            };
        }
        slots_init = true;
    }
    if (!wp_init) {
        wallpaper = .{
            .rgba = wp_rgba[0..],
            .cap = WP_RGBA,
        };
        wp_init = true;
    }
}

pub fn reset() void {
    ensureInit();
    for (&slots) |*s| {
        s.ready = false;
        s.pending = false;
        s.w = 0;
        s.h = 0;
        s.src_len = 0;
    }
    wallpaper.ready = false;
    wallpaper.pending = false;
    wallpaper.w = 0;
    wallpaper.h = 0;
    wallpaper.src_len = 0;
}

fn isSimg(data: []const u8) bool {
    return data.len >= 12 and data[0] == 'S' and data[1] == 'I' and data[2] == 'M' and data[3] == 'G';
}

fn readU32le(b: []const u8) u32 {
    return @as(u32, b[0]) | (@as(u32, b[1]) << 8) | (@as(u32, b[2]) << 16) | (@as(u32, b[3]) << 24);
}

fn loadInto(slot: *Slot, data: []const u8) void {
    slot.ready = false;
    slot.pending = false;
    slot.w = 0;
    slot.h = 0;
    slot.src_len = 0;

    if (isSimg(data)) {
        const w = readU32le(data[4..8]);
        const h = readU32le(data[8..12]);
        const need = @as(usize, w) * @as(usize, h) * 4;
        if (w == 0 or h == 0 or 12 + need > data.len or need > slot.cap) return;
        @memcpy(slot.rgba[0..need], data[12 .. 12 + need]);
        slot.w = w;
        slot.h = h;
        slot.ready = true;
        return;
    }

    slot.src_len = @min(data.len, slot.src.len);
    @memcpy(slot.src[0..slot.src_len], data[0..slot.src_len]);
    slot.pending = true;
    retryHost(slot);
}

fn retryHost(slot: *Slot) void {
    if (!slot.pending or slot.src_len == 0) return;
    var ow: u32 = 0;
    var oh: u32 = 0;
    if (hostapi.imageDecode(slot.src[0..slot.src_len], slot.rgba[0..slot.cap], &ow, &oh)) {
        const need = @as(usize, ow) * @as(usize, oh) * 4;
        if (need > slot.cap or ow == 0 or oh == 0) {
            slot.pending = false;
            return;
        }
        slot.w = ow;
        slot.h = oh;
        slot.ready = true;
        slot.pending = false;
    }
}

pub fn loadSlot(index: usize, data: []const u8) void {
    ensureInit();
    if (index >= MAX_ICONS) return;
    loadInto(&slots[index], data);
}

pub fn loadWallpaper(data: []const u8) void {
    ensureInit();
    loadInto(&wallpaper, data);
}

pub fn tickPending() void {
    ensureInit();
    for (&slots) |*s| {
        if (s.pending) retryHost(s);
    }
    if (wallpaper.pending) retryHost(&wallpaper);
}

pub fn blit(
    fb: []u8,
    stride: u32,
    fb_w: u32,
    fb_h: u32,
    dx: u32,
    dy: u32,
    dw: u32,
    dh: u32,
    index: usize,
) void {
    ensureInit();
    if (index >= MAX_ICONS) return;
    const s = &slots[index];
    if (!s.ready or s.w == 0 or s.h == 0 or dw == 0 or dh == 0) return;
    blitScaled(fb, stride, fb_w, fb_h, dx, dy, dw, dh, s.rgba, s.w, s.h);
}

pub fn blitWallpaper(fb: []u8, stride: u32, fb_w: u32, fb_h: u32, dx: u32, dy: u32, dw: u32, dh: u32) void {
    ensureInit();
    if (!wallpaper.ready or wallpaper.w == 0 or wallpaper.h == 0 or dw == 0 or dh == 0) return;
    blitScaled(fb, stride, fb_w, fb_h, dx, dy, dw, dh, wallpaper.rgba, wallpaper.w, wallpaper.h);
}

pub fn wallpaperReady() bool {
    ensureInit();
    return wallpaper.ready;
}

pub fn slotReady(index: usize) bool {
    ensureInit();
    return index < MAX_ICONS and slots[index].ready;
}

fn blitScaled(
    fb: []u8,
    stride: u32,
    fb_w: u32,
    fb_h: u32,
    dx: u32,
    dy: u32,
    dw: u32,
    dh: u32,
    src: []const u8,
    sw: u32,
    sh: u32,
) void {
    var y: u32 = 0;
    while (y < dh) : (y += 1) {
        const sy = (y * sh) / dh;
        const fy = dy +% y;
        if (fy >= fb_h) break;
        var x: u32 = 0;
        while (x < dw) : (x += 1) {
            const sx = (x * sw) / dw;
            const fx = dx +% x;
            if (fx >= fb_w) break;
            const so: usize = (@as(usize, sy) * @as(usize, sw) + @as(usize, sx)) * 4;
            if (so + 3 >= src.len) continue;
            const sr = src[so + 0];
            const sg = src[so + 1];
            const sb = src[so + 2];
            const sa = src[so + 3];
            if (sa == 0) continue;
            const o: usize = @as(usize, fy) * @as(usize, stride) + @as(usize, fx) * 4;
            if (o + 3 >= fb.len) continue;
            if (sa == 255) {
                fb[o + 0] = sr;
                fb[o + 1] = sg;
                fb[o + 2] = sb;
                fb[o + 3] = 255;
            } else {
                const dr: u32 = fb[o + 0];
                const dg: u32 = fb[o + 1];
                const db: u32 = fb[o + 2];
                const a: u32 = sa;
                fb[o + 0] = @truncate((@as(u32, sr) * a + dr * (255 - a)) / 255);
                fb[o + 1] = @truncate((@as(u32, sg) * a + dg * (255 - a)) / 255);
                fb[o + 2] = @truncate((@as(u32, sb) * a + db * (255 - a)) / 255);
                fb[o + 3] = 255;
            }
        }
    }
}
