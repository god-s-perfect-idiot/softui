//! Shared framebuffer helpers for SoftUI capability demos.

const font = @import("font.zig");

pub fn put(fb: []u8, stride: u32, width: u32, height: u32, x: u32, y: u32, color: u32) void {
    if (x >= width or y >= height) return;
    const o: usize = @as(usize, y) * @as(usize, stride) + @as(usize, x) * 4;
    if (o + 3 >= fb.len) return;
    fb[o + 0] = @truncate(color >> 16);
    fb[o + 1] = @truncate(color >> 8);
    fb[o + 2] = @truncate(color);
    fb[o + 3] = @truncate(color >> 24);
}

pub fn fill(fb: []u8, stride: u32, fb_w: u32, fb_h: u32, x0: u32, y0: u32, w: u32, h: u32, color: u32) void {
    if (w == 0 or h == 0) return;
    const r: u8 = @truncate(color >> 16);
    const g: u8 = @truncate(color >> 8);
    const b: u8 = @truncate(color);
    const a: u8 = @truncate(color >> 24);
    const x1 = @min(x0 +% w, fb_w);
    const y1 = @min(y0 +% h, fb_h);
    if (x0 >= x1 or y0 >= y1) return;
    var y: u32 = y0;
    while (y < y1) : (y += 1) {
        var o: usize = @as(usize, y) * @as(usize, stride) + @as(usize, x0) * 4;
        var x: u32 = x0;
        while (x < x1) : (x += 1) {
            if (o + 3 >= fb.len) break;
            fb[o + 0] = r;
            fb[o + 1] = g;
            fb[o + 2] = b;
            fb[o + 3] = a;
            o += 4;
        }
    }
}

pub fn clear(fb: []u8, stride: u32, width: u32, height: u32, color: u32) void {
    fill(fb, stride, width, height, 0, 0, width, height, color);
}

pub fn hline(fb: []u8, stride: u32, width: u32, height: u32, x0: u32, y: u32, w: u32, color: u32) void {
    fill(fb, stride, width, height, x0, y, w, 1, color);
}

pub fn vline(fb: []u8, stride: u32, width: u32, height: u32, x: u32, y0: u32, h: u32, color: u32) void {
    fill(fb, stride, width, height, x, y0, 1, h, color);
}

pub fn rect(fb: []u8, stride: u32, width: u32, height: u32, x: u32, y: u32, w: u32, h: u32, color: u32) void {
    if (w == 0 or h == 0) return;
    hline(fb, stride, width, height, x, y, w, color);
    hline(fb, stride, width, height, x, y + h -| 1, w, color);
    vline(fb, stride, width, height, x, y, h, color);
    vline(fb, stride, width, height, x + w -| 1, y, h, color);
}

pub fn putBlend(fb: []u8, stride: u32, width: u32, height: u32, x: u32, y: u32, color: u32) void {
    if (x >= width or y >= height) return;
    const o: usize = @as(usize, y) * @as(usize, stride) + @as(usize, x) * 4;
    if (o + 3 >= fb.len) return;
    const sa: u32 = (color >> 24) & 0xFF;
    if (sa == 0) return;
    if (sa == 255) {
        put(fb, stride, width, height, x, y, color);
        return;
    }
    const sr: u32 = (color >> 16) & 0xFF;
    const sg: u32 = (color >> 8) & 0xFF;
    const sb: u32 = color & 0xFF;
    const dr: u32 = fb[o + 0];
    const dg: u32 = fb[o + 1];
    const db: u32 = fb[o + 2];
    fb[o + 0] = @truncate((sr * sa + dr * (255 - sa)) / 255);
    fb[o + 1] = @truncate((sg * sa + dg * (255 - sa)) / 255);
    fb[o + 2] = @truncate((sb * sa + db * (255 - sa)) / 255);
    fb[o + 3] = 255;
}

/// Coverage 0..255 for a circle of radius `r` centered at the pixel origin.
fn circleCoverage(dx: f32, dy: f32, r: f32) u8 {
    if (r <= 0) return 255;
    const dist = @sqrt(dx * dx + dy * dy);
    const aa: f32 = 0.75;
    if (dist <= r - aa) return 255;
    if (dist >= r + aa) return 0;
    const t = (r + aa - dist) / (2 * aa);
    const c: i32 = @intFromFloat(t * 255.0 + 0.5);
    if (c <= 0) return 0;
    if (c >= 255) return 255;
    return @intCast(c);
}

fn roundCoverage(lx: f32, ly: f32, w: f32, h: f32, r: f32) u8 {
    if (r <= 0) return 255;
    // Pixel centers relative to rect; corner centers inset by r.
    const cx = if (lx < r) r else if (lx >= w - r) w - r else lx;
    const cy = if (ly < r) r else if (ly >= h - r) h - r else ly;
    if (cx == lx and cy == ly) return 255;
    return circleCoverage(lx - cx, ly - cy, r);
}

/// Filled axis-aligned rounded rectangle (radius clamped to fit) with edge AA.
pub fn fillRound(fb: []u8, stride: u32, fb_w: u32, fb_h: u32, x0: u32, y0: u32, w: u32, h: u32, radius: u32, color: u32) void {
    if (w == 0 or h == 0) return;
    const r_u = @min(radius, @min(w / 2, h / 2));
    const rf: f32 = @floatFromInt(r_u);
    const wf: f32 = @floatFromInt(w);
    const hf: f32 = @floatFromInt(h);
    const base_a: u32 = (color >> 24) & 0xFF;
    const x1 = x0 +% w;
    const y1 = y0 +% h;
    var y: u32 = y0;
    while (y < y1 and y < fb_h) : (y += 1) {
        var x: u32 = x0;
        while (x < x1 and x < fb_w) : (x += 1) {
            const lx = @as(f32, @floatFromInt(x - x0)) + 0.5;
            const ly = @as(f32, @floatFromInt(y - y0)) + 0.5;
            const cov = roundCoverage(lx, ly, wf, hf, rf);
            if (cov == 0) continue;
            if (cov == 255 and base_a == 255) {
                put(fb, stride, fb_w, fb_h, x, y, color);
            } else {
                const a: u32 = (base_a * @as(u32, cov) + 127) / 255;
                const blended = (color & 0x00FFFFFF) | (a << 24);
                putBlend(fb, stride, fb_w, fb_h, x, y, blended);
            }
        }
    }
}

/// 1px rounded outline + optional fill (fill_color alpha 0 skips fill).
pub fn roundRect(fb: []u8, stride: u32, fb_w: u32, fb_h: u32, x0: u32, y0: u32, w: u32, h: u32, radius: u32, fill_color: u32, border_color: u32) void {
    if (w == 0 or h == 0) return;
    fillRound(fb, stride, fb_w, fb_h, x0, y0, w, h, radius, border_color);
    if (w > 2 and h > 2 and (fill_color >> 24) != 0) {
        const ir = if (radius > 0) radius -| 1 else 0;
        fillRound(fb, stride, fb_w, fb_h, x0 + 1, y0 + 1, w -| 2, h -| 2, ir, fill_color);
    }
}

/// Disc filled circle centered at (cx, cy) with edge AA.
pub fn fillCircle(fb: []u8, stride: u32, fb_w: u32, fb_h: u32, cx: i32, cy: i32, radius: i32, color: u32) void {
    if (radius <= 0) return;
    const rf: f32 = @floatFromInt(radius);
    const base_a: u32 = (color >> 24) & 0xFF;
    const pad: i32 = radius + 1;
    var dy: i32 = -pad;
    while (dy <= pad) : (dy += 1) {
        var dx: i32 = -pad;
        while (dx <= pad) : (dx += 1) {
            const cov = circleCoverage(@floatFromInt(dx), @floatFromInt(dy), rf);
            if (cov == 0) continue;
            const x = cx + dx;
            const y = cy + dy;
            if (x < 0 or y < 0) continue;
            const xu: u32 = @intCast(x);
            const yu: u32 = @intCast(y);
            if (cov == 255 and base_a == 255) {
                put(fb, stride, fb_w, fb_h, xu, yu, color);
            } else {
                const a: u32 = (base_a * @as(u32, cov) + 127) / 255;
                const blended = (color & 0x00FFFFFF) | (a << 24);
                putBlend(fb, stride, fb_w, fb_h, xu, yu, blended);
            }
        }
    }
}

pub fn drawText(fb: []u8, stride: u32, width: u32, height: u32, x0: u32, y0: u32, text: []const u8, color: u32) void {
    _ = height;
    font.blitText(fb, stride, width, x0, y0, text, color);
}

pub fn drawGlyph(fb: []u8, stride: u32, width: u32, height: u32, x0: u32, y0: u32, ch: u8, color: u32) void {
    _ = height;
    font.blitGlyph(fb, stride, width, x0, y0, ch, color);
}

pub fn writeU32(buf: []u8, start: usize, v: u32) usize {
    var tmp: [10]u8 = undefined;
    var n = v;
    var len: usize = 0;
    if (n == 0) {
        tmp[0] = '0';
        len = 1;
    } else {
        while (n > 0) : (n /= 10) {
            tmp[len] = '0' + @as(u8, @intCast(n % 10));
            len += 1;
        }
    }
    var i: usize = 0;
    while (i < len) : (i += 1) buf[start + i] = tmp[len - 1 - i];
    return start + len;
}

pub fn formatU32(buf: []u8, v: u32) []const u8 {
    const n = writeU32(buf, 0, v);
    return buf[0..n];
}

pub fn formatPair(buf: []u8, a: u32, sep: u8, b: u32) []const u8 {
    var i = writeU32(buf, 0, a);
    if (i < buf.len) {
        buf[i] = sep;
        i += 1;
    }
    i = writeU32(buf, i, b);
    return buf[0..i];
}

pub fn formatHMS(buf: *[12]u8, total_secs: u32) []const u8 {
    const hh = (total_secs / 3600) % 100;
    const mm = (total_secs / 60) % 60;
    const ss = total_secs % 60;
    buf[0] = '0' + @as(u8, @intCast(hh / 10));
    buf[1] = '0' + @as(u8, @intCast(hh % 10));
    buf[2] = ':';
    buf[3] = '0' + @as(u8, @intCast(mm / 10));
    buf[4] = '0' + @as(u8, @intCast(mm % 10));
    buf[5] = ':';
    buf[6] = '0' + @as(u8, @intCast(ss / 10));
    buf[7] = '0' + @as(u8, @intCast(ss % 10));
    return buf[0..8];
}

/// OS GUI theme (webOS-inspired). See docs/gui-styling.md.
pub const COLOR_BG_TOP: u32 = 0xFF4A4A4A;
pub const COLOR_BG_BOTTOM: u32 = 0xFF2C2C2C;
pub const COLOR_BG: u32 = 0xFF3A3A3A;
pub const COLOR_FG: u32 = 0xFFF2F2F2;
pub const COLOR_DIM: u32 = 0xFFB0B0B0;
pub const COLOR_PRIMARY: u32 = 0xFF5078A0;
pub const COLOR_SECONDARY: u32 = 0xFFE8C84A;
/// @deprecated Prefer COLOR_PRIMARY.
pub const COLOR_ACCENT: u32 = COLOR_PRIMARY;
pub const COLOR_PANEL: u32 = 0xFF383838;
pub const COLOR_BAR: u32 = 0xFF3D3F43;
pub const COLOR_BORDER: u32 = 0xFF1A1A1A;
pub const COLOR_OK: u32 = 0xFF3DDC97;
pub const COLOR_WARN: u32 = 0xFFE8C84A;

/// Full-rect vertical plate gradient (default SoftUI background).
pub fn fillVGrad(
    fb: []u8,
    stride: u32,
    fb_w: u32,
    fb_h: u32,
    x0: u32,
    y0: u32,
    w: u32,
    h: u32,
    top: u32,
    bottom: u32,
) void {
    fillRoundVGrad(fb, stride, fb_w, fb_h, x0, y0, w, h, 0, top, bottom);
}

pub fn clearPlate(fb: []u8, stride: u32, width: u32, height: u32) void {
    fillVGrad(fb, stride, width, height, 0, 0, width, height, COLOR_BG_TOP, COLOR_BG_BOTTOM);
}

fn channel(c: u32, shift: u5) u32 {
    return (c >> shift) & 0xFF;
}

/// Linear blend of opaque ARGB colors. `t` is 0..255 (0 = a, 255 = b).
pub fn mix(a: u32, b: u32, t: u8) u32 {
    const t32: u32 = t;
    const u: u32 = 255 - t32;
    const ar = channel(a, 16);
    const ag = channel(a, 8);
    const ab = channel(a, 0);
    const br = channel(b, 16);
    const bg = channel(b, 8);
    const bb = channel(b, 0);
    const r = (ar * u + br * t32) / 255;
    const g = (ag * u + bg * t32) / 255;
    const bl = (ab * u + bb * t32) / 255;
    return 0xFF000000 | (r << 16) | (g << 8) | bl;
}

pub fn lighten(c: u32, amount: u8) u32 {
    return mix(c, 0xFFFFFFFF, amount);
}

pub fn darken(c: u32, amount: u8) u32 {
    return mix(c, 0xFF000000, amount);
}

/// Vertical gradient fill inside a rounded rect (top → bottom).
pub fn fillRoundVGrad(
    fb: []u8,
    stride: u32,
    fb_w: u32,
    fb_h: u32,
    x0: u32,
    y0: u32,
    w: u32,
    h: u32,
    radius: u32,
    top: u32,
    bottom: u32,
) void {
    if (w == 0 or h == 0) return;
    const r_u = @min(radius, @min(w / 2, h / 2));
    const rf: f32 = @floatFromInt(r_u);
    const wf: f32 = @floatFromInt(w);
    const hf: f32 = @floatFromInt(h);
    const denom: u32 = if (h > 1) h - 1 else 1;
    const x1 = x0 +% w;
    const y1 = y0 +% h;
    var y: u32 = y0;
    while (y < y1 and y < fb_h) : (y += 1) {
        const ty: u8 = @truncate(((@as(u32, y - y0) * 255) + denom / 2) / denom);
        const color = mix(top, bottom, ty);
        var x: u32 = x0;
        while (x < x1 and x < fb_w) : (x += 1) {
            const lx = @as(f32, @floatFromInt(x - x0)) + 0.5;
            const ly = @as(f32, @floatFromInt(y - y0)) + 0.5;
            const cov = roundCoverage(lx, ly, wf, hf, rf);
            if (cov == 0) continue;
            if (cov == 255) {
                put(fb, stride, fb_w, fb_h, x, y, color);
            } else {
                const blended = (color & 0x00FFFFFF) | (@as(u32, cov) << 24);
                putBlend(fb, stride, fb_w, fb_h, x, y, blended);
            }
        }
    }
}

/// Soft drop shadow under a rounded rect.
pub fn softShadow(
    fb: []u8,
    stride: u32,
    fb_w: u32,
    fb_h: u32,
    x0: u32,
    y0: u32,
    w: u32,
    h: u32,
    radius: u32,
) void {
    fillRound(fb, stride, fb_w, fb_h, x0 + 2, y0 + 3, w, h, radius, 0x66000000);
    fillRound(fb, stride, fb_w, fb_h, x0 + 1, y0 + 2, w, h, radius, 0x33000000);
}

/// Raised plastic / metal control: shadow, vertical gloss, bevel rim, top sheen.
pub fn raisedRound(
    fb: []u8,
    stride: u32,
    fb_w: u32,
    fb_h: u32,
    x0: u32,
    y0: u32,
    w: u32,
    h: u32,
    radius: u32,
    face_top: u32,
    face_bot: u32,
    rim: u32,
) void {
    if (w == 0 or h == 0) return;
    softShadow(fb, stride, fb_w, fb_h, x0, y0, w, h, radius);
    fillRound(fb, stride, fb_w, fb_h, x0, y0, w, h, radius, rim);
    if (w > 2 and h > 2) {
        const ir = if (radius > 0) radius -| 1 else 0;
        fillRoundVGrad(fb, stride, fb_w, fb_h, x0 + 1, y0 + 1, w -| 2, h -| 2, ir, face_top, face_bot);
    }
    // Specular band near the top edge.
    if (h > 8 and w > 6) {
        const sheen_h = @max(2, h / 5);
        const ir = if (radius > 1) radius -| 2 else 0;
        fillRound(fb, stride, fb_w, fb_h, x0 + 3, y0 + 2, w -| 6, sheen_h, ir, 0x55FFFFFF);
    }
    // Bevel: light top/left, dark bottom/right.
    if (w > 2 and h > 2) {
        hline(fb, stride, fb_w, fb_h, x0 + 1, y0 + 1, w -| 2, lighten(face_top, 90));
        hline(fb, stride, fb_w, fb_h, x0 + 1, y0 + h -| 2, w -| 2, darken(face_bot, 70));
        vline(fb, stride, fb_w, fb_h, x0 + 1, y0 + 1, h -| 2, lighten(face_top, 60));
        vline(fb, stride, fb_w, fb_h, x0 + w -| 2, y0 + 1, h -| 2, darken(face_bot, 55));
    }
}

/// Recessed well: outer rim, deep face, inner top shadow, bottom bounce light.
pub fn insetRound(
    fb: []u8,
    stride: u32,
    fb_w: u32,
    fb_h: u32,
    x0: u32,
    y0: u32,
    w: u32,
    h: u32,
    radius: u32,
    well_top: u32,
    well_bot: u32,
    rim: u32,
) void {
    if (w == 0 or h == 0) return;
    fillRound(fb, stride, fb_w, fb_h, x0, y0, w, h, radius, rim);
    if (w > 2 and h > 2) {
        const ir = if (radius > 0) radius -| 1 else 0;
        fillRoundVGrad(fb, stride, fb_w, fb_h, x0 + 1, y0 + 1, w -| 2, h -| 2, ir, well_top, well_bot);
    }
    if (w > 4 and h > 4) {
        blendHline(fb, stride, fb_w, fb_h, x0 + 2, y0 + 2, w -| 4, 0x88000000);
        blendHline(fb, stride, fb_w, fb_h, x0 + 2, y0 + 3, w -| 4, 0x44000000);
        blendHline(fb, stride, fb_w, fb_h, x0 + 2, y0 + h -| 3, w -| 4, 0x33FFFFFF);
        blendVline(fb, stride, fb_w, fb_h, x0 + 2, y0 + 2, h -| 4, 0x55000000);
        blendVline(fb, stride, fb_w, fb_h, x0 + w -| 3, y0 + 2, h -| 4, 0x22FFFFFF);
    }
}

fn blendHline(fb: []u8, stride: u32, width: u32, height: u32, x0: u32, y: u32, w: u32, color: u32) void {
    if (w == 0 or y >= height) return;
    const x1 = @min(x0 +% w, width);
    var x: u32 = x0;
    while (x < x1) : (x += 1) {
        putBlend(fb, stride, width, height, x, y, color);
    }
}

fn blendVline(fb: []u8, stride: u32, width: u32, height: u32, x: u32, y0: u32, h: u32, color: u32) void {
    if (h == 0 or x >= width) return;
    const y1 = @min(y0 +% h, height);
    var y: u32 = y0;
    while (y < y1) : (y += 1) {
        putBlend(fb, stride, width, height, x, y, color);
    }
}

/// Glossy circular knob / thumb.
pub fn glossyKnob(
    fb: []u8,
    stride: u32,
    fb_w: u32,
    fb_h: u32,
    cx: i32,
    cy: i32,
    radius: i32,
    face: u32,
    rim: u32,
) void {
    if (radius <= 0) return;
    // Soft contact shadow.
    fillCircle(fb, stride, fb_w, fb_h, cx + 1, cy + 2, radius, 0x66000000);
    fillCircle(fb, stride, fb_w, fb_h, cx, cy, radius, rim);
    if (radius > 1) {
        fillCircle(fb, stride, fb_w, fb_h, cx, cy, radius - 1, face);
    }
    // Specular highlight (upper-left).
    const hr = @max(@as(i32, 1), @divTrunc(radius, 3));
    fillCircle(fb, stride, fb_w, fb_h, cx - @divTrunc(radius, 3), cy - @divTrunc(radius, 3), hr, 0xAAFFFFFF);
    if (radius > 3) {
        fillCircle(
            fb,
            stride,
            fb_w,
            fb_h,
            cx - @divTrunc(radius, 4),
            cy - @divTrunc(radius, 4),
            @max(@as(i32, 1), hr - 1),
            0x55FFFFFF,
        );
    }
}
