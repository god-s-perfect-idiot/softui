//! UI kit gallery — skeuomorphic SoftUI widgets.

const font = @import("font.zig");
const gfx = @import("demo_gfx.zig");
const input = @import("input.zig");

var toggle_on: bool = true;
var slider: u32 = 40;
var selected: u32 = 0;

pub fn reset() void {
    toggle_on = true;
    slider = 40;
    selected = 0;
}

pub fn onKey(key: u32) void {
    if (key == ' ' or key == 13) {
        toggle_on = !toggle_on;
        return;
    }
    if (key == 0x102) {
        selected = if (selected == 0) 3 else selected - 1;
        return;
    }
    if (key == 0x103) {
        selected = (selected + 1) % 4;
        return;
    }
    if (key == 0x100 and slider > 0) slider -= 5;
    if (key == 0x101 and slider < 100) slider += 5;
}

pub fn render(fb: []u8, width: u32, height: u32, stride: u32, phase: u32) void {
    // Brushed plate backdrop.
    gfx.clear(fb, stride, width, height, 0xFF0A0C10);
    gfx.fillRoundVGrad(fb, stride, width, height, 0, 0, width, height, 0, 0xFF12161C, 0xFF07090C);

    const line = font.GLYPH_H + 4;
    gfx.drawText(fb, stride, width, height, 12, 36, "UI KIT", gfx.COLOR_DIM);
    gfx.drawText(fb, stride, width, height, 12, 36 + line, "Space toggle  arrows move", gfx.COLOR_DIM);

    const ctrl_y: u32 = 36 + line * 2 + 4;
    const ctrl_h: u32 = font.GLYPH_H + 16;
    const p = input.latest;
    const hover_btn = hit(p.x, p.y, 12, ctrl_y, 108, ctrl_h);
    drawButton(fb, stride, width, height, 12, ctrl_y, 108, ctrl_h, "Button", hover_btn or selected == 0);

    drawField(fb, stride, width, height, 132, ctrl_y, width -| 144, ctrl_h, "text field");

    // Rectangular toggle: rounded-rect well + matching rounded-rect thumb.
    const ty: u32 = ctrl_y + ctrl_h + 16;
    gfx.drawText(fb, stride, width, height, 12, ty + 6, "Toggle", if (selected == 1) gfx.COLOR_ACCENT else gfx.COLOR_DIM);
    const tx: u32 = 12 + font.textWidth("Toggle") + 12;
    const tw: u32 = 54;
    const th: u32 = 24;
    const track_r: u32 = 3;
    const tube_top: u32 = if (toggle_on) gfx.lighten(gfx.COLOR_OK, 70) else 0xFF1A1E24;
    const tube_bot: u32 = if (toggle_on) gfx.darken(gfx.COLOR_OK, 55) else 0xFF0A0C10;
    const tube_rim: u32 = if (toggle_on) gfx.darken(gfx.COLOR_OK, 90) else 0xFF3A4450;
    gfx.insetRound(fb, stride, width, height, tx, ty + 2, tw, th, track_r, tube_top, tube_bot, tube_rim);
    // Glass sheen across the well
    if (tw > 8 and th > 6) {
        gfx.fillRound(fb, stride, width, height, tx + 3, ty + 4, tw -| 6, 4, 2, if (toggle_on) 0x55FFFFFF else 0x22FFFFFF);
    }
    // Rounded-rect thumb
    const knob_w: u32 = 24;
    const knob_h: u32 = th -| 6;
    const knob_r: u32 = 3;
    const knob_x: u32 = if (toggle_on) tx + tw -| knob_w -| 3 else tx + 3;
    const knob_y: u32 = ty + 5;
    gfx.fillRound(fb, stride, width, height, knob_x, knob_y + 1, knob_w, knob_h, knob_r, 0x44000000);
    gfx.fillRound(fb, stride, width, height, knob_x, knob_y, knob_w, knob_h, knob_r, 0xFF5A6570);
    gfx.fillRoundVGrad(
        fb,
        stride,
        width,
        height,
        knob_x + 1,
        knob_y + 1,
        knob_w -| 2,
        knob_h -| 2,
        if (knob_r > 0) knob_r -| 1 else 0,
        0xFFE8EEF4,
        0xFF9AA4B0,
    );
    if (knob_h > 6 and knob_w > 6) {
        gfx.fillRound(fb, stride, width, height, knob_x + 3, knob_y + 2, knob_w -| 6, 3, 2, 0x66FFFFFF);
        gfx.hline(fb, stride, width, height, knob_x + 2, knob_y + 1, knob_w -| 4, 0xFFF0F4F8);
        gfx.hline(fb, stride, width, height, knob_x + 2, knob_y + knob_h -| 2, knob_w -| 4, 0xFF6A7380);
    }

    // Recessed slider groove + chrome thumb
    const sy: u32 = ty + line + 14;
    gfx.drawText(fb, stride, width, height, 12, sy, "Slider", if (selected == 2) gfx.COLOR_ACCENT else gfx.COLOR_DIM);
    const sw = if (width > 24) width - 24 else width;
    const track_y = sy + font.GLYPH_H + 8;
    const track_h: u32 = 12;
    gfx.insetRound(fb, stride, width, height, 12, track_y, sw, track_h, track_h / 2, 0xFF0A0C10, 0xFF1A2028, 0xFF3A4452);
    const fill_w = @max(track_h, (sw * slider) / 100);
    if (slider > 0) {
        gfx.fillRoundVGrad(
            fb,
            stride,
            width,
            height,
            12,
            track_y,
            fill_w,
            track_h,
            track_h / 2,
            gfx.lighten(gfx.COLOR_ACCENT, 55),
            gfx.darken(gfx.COLOR_ACCENT, 35),
        );
        if (fill_w > 6 and track_h > 4) {
            gfx.fillRound(fb, stride, width, height, 14, track_y + 2, fill_w -| 4, 3, 2, 0x66FFFFFF);
        }
    }
    const thumb_x: i32 = @intCast(12 + ((sw -| 1) * slider) / 100);
    const thumb_y: i32 = @intCast(track_y + track_h / 2);
    gfx.glossyKnob(fb, stride, width, height, thumb_x, thumb_y, 8, gfx.lighten(gfx.COLOR_ACCENT, 70), gfx.darken(gfx.COLOR_ACCENT, 40));
    var pct_buf: [8]u8 = undefined;
    const pct = gfx.formatU32(&pct_buf, slider);
    gfx.drawText(
        fb,
        stride,
        width,
        height,
        12 + sw -| font.textWidth(pct),
        sy,
        pct,
        gfx.COLOR_FG,
    );

    // Glass progress tube
    const py: u32 = track_y + track_h + 18;
    gfx.drawText(fb, stride, width, height, 12, py, "Progress", if (selected == 3) gfx.COLOR_ACCENT else gfx.COLOR_DIM);
    const prog_y = py + font.GLYPH_H + 8;
    const prog_h: u32 = 14;
    gfx.insetRound(fb, stride, width, height, 12, prog_y, sw, prog_h, prog_h / 2, 0xFF0A0C10, 0xFF1A2028, 0xFF3A4452);
    const pulse = @max(if (phase % 100 == 0) @as(u32, 0) else prog_h, ((phase % 100) * sw) / 100);
    if (pulse > 0) {
        gfx.fillRoundVGrad(
            fb,
            stride,
            width,
            height,
            12,
            prog_y,
            pulse,
            prog_h,
            prog_h / 2,
            gfx.lighten(gfx.COLOR_OK, 60),
            gfx.darken(gfx.COLOR_OK, 30),
        );
        if (pulse > 8 and prog_h > 5) {
            gfx.fillRound(fb, stride, width, height, 14, prog_y + 2, pulse -| 4, 4, 2, 0x77FFFFFF);
        }
    }

    // Embossed list rows
    const list_y: u32 = prog_y + prog_h + 18;
    const row_h: u32 = font.GLYPH_H + 12;
    gfx.drawText(fb, stride, width, height, 12, list_y, "List rows", gfx.COLOR_DIM);
    const rows = [_][]const u8{ "Settings", "Files", "Network", "About" };
    var i: u32 = 0;
    while (i < rows.len) : (i += 1) {
        const ry = list_y + line + i * row_h;
        if (ry + row_h > height) break;
        const active = i == selected % 4;
        if (active) {
            gfx.raisedRound(
                fb,
                stride,
                width,
                height,
                12,
                ry,
                sw,
                row_h -| 2,
                7,
                0xFF2A3648,
                0xFF161C26,
                0xFF405068,
            );
        } else {
            gfx.insetRound(
                fb,
                stride,
                width,
                height,
                12,
                ry,
                sw,
                row_h -| 2,
                7,
                0xFF101418,
                0xFF0A0C10,
                0xFF2A3038,
            );
        }
        var mark: [24]u8 = undefined;
        mark[0] = if (active) '>' else ' ';
        mark[1] = ' ';
        var n: usize = 2;
        for (rows[i]) |c| {
            if (n >= mark.len) break;
            mark[n] = c;
            n += 1;
        }
        gfx.drawText(fb, stride, width, height, 16, ry + (row_h -| font.GLYPH_H) / 2, mark[0..n], if (active) gfx.COLOR_FG else gfx.COLOR_DIM);
    }

    gfx.drawText(fb, stride, width, height, 12, height -| (font.GLYPH_H + 4), "Esc / exit to leave", gfx.COLOR_DIM);
}

fn hit(px: u32, py: u32, x: u32, y: u32, w: u32, h: u32) bool {
    return px >= x and px < x + w and py >= y and py < y + h;
}

fn drawButton(fb: []u8, stride: u32, width: u32, height: u32, x: u32, y: u32, w: u32, h: u32, label: []const u8, hot: bool) void {
    const face_top: u32 = if (hot) 0xFF3A6A98 else 0xFF2A3644;
    const face_bot: u32 = if (hot) 0xFF1A3858 else 0xFF121820;
    const rim: u32 = if (hot) gfx.lighten(gfx.COLOR_ACCENT, 20) else 0xFF3A4858;
    gfx.raisedRound(fb, stride, width, height, x, y, w, h, 8, face_top, face_bot, rim);
    const tw: u32 = font.textWidth(label);
    const tx = x + (w -| tw) / 2;
    const ty = y + (h -| font.GLYPH_H) / 2;
    // Embossed caption: dark shadow then light face.
    gfx.drawText(fb, stride, width, height, tx + 1, ty + 1, label, 0x88000000);
    gfx.drawText(fb, stride, width, height, tx, ty, label, if (hot) 0xFFE8F4FF else gfx.COLOR_FG);
}

fn drawField(fb: []u8, stride: u32, width: u32, height: u32, x: u32, y: u32, w: u32, h: u32, placeholder: []const u8) void {
    gfx.insetRound(fb, stride, width, height, x, y, w, h, 7, 0xFF0A0C10, 0xFF151A22, 0xFF3A4452);
    gfx.drawText(fb, stride, width, height, x + 10, y + (h -| font.GLYPH_H) / 2, placeholder, gfx.COLOR_DIM);
}
