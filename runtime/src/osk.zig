//! SoftUI on-screen keyboard. Guest-drawn overlay; off unless toggled.

const font = @import("font.zig");
const input = @import("input.zig");

pub const MOD_SHIFT: u32 = 1;
pub const MOD_CTRL: u32 = 2;
pub const MOD_ALT: u32 = 4;

/// Hardware combo: Ctrl+Shift+K (case-insensitive).
pub const HOTKEY: u32 = 'k';

pub const PtrKind = enum(u32) {
    move = 0,
    down = 1,
    up = 2,
};

const COLOR_PANEL: u32 = 0xE0141A22;
const COLOR_KEY: u32 = 0xFF1C2430;
const COLOR_KEY_ACTIVE: u32 = 0xFF1A3048;
const COLOR_KEY_MOD: u32 = 0xFF243044;
const COLOR_BORDER: u32 = 0xFF2A3544;
const COLOR_FG: u32 = 0xFFD7E0EA;
const COLOR_DIM: u32 = 0xFF7A8796;
const COLOR_ACCENT: u32 = 0xFF50B4FF;

const KeyKind = enum { char, special, shift, ctrl, hide };

const KeySpec = struct {
    label: []const u8,
    label_shift: []const u8,
    code: u32,
    code_shift: u32,
    units: u32,
    kind: KeyKind,
};

fn k(label: []const u8, code: u32) KeySpec {
    return .{
        .label = label,
        .label_shift = label,
        .code = code,
        .code_shift = code,
        .units = 1,
        .kind = .char,
    };
}

fn ks(label: []const u8, shifted: []const u8, code: u32, code_shift: u32) KeySpec {
    return .{
        .label = label,
        .label_shift = shifted,
        .code = code,
        .code_shift = code_shift,
        .units = 1,
        .kind = .char,
    };
}

fn kw(label: []const u8, code: u32, units: u32, kind: KeyKind) KeySpec {
    return .{
        .label = label,
        .label_shift = label,
        .code = code,
        .code_shift = code,
        .units = units,
        .kind = kind,
    };
}

const ROW0 = [_]KeySpec{
    ks("`", "~", '`', '~'),
    ks("1", "!", '1', '!'),
    ks("2", "@", '2', '@'),
    ks("3", "#", '3', '#'),
    ks("4", "$", '4', '$'),
    ks("5", "%", '5', '%'),
    ks("6", "^", '6', '^'),
    ks("7", "&", '7', '&'),
    ks("8", "*", '8', '*'),
    ks("9", "(", '9', '('),
    ks("0", ")", '0', ')'),
    ks("-", "_", '-', '_'),
    ks("=", "+", '=', '+'),
    kw("Bksp", input.KEY_BACKSPACE, 2, .special),
};

const ROW1 = [_]KeySpec{
    kw("Tab", input.KEY_TAB, 2, .special),
    k("q", 'q'),
    k("w", 'w'),
    k("e", 'e'),
    k("r", 'r'),
    k("t", 't'),
    k("y", 'y'),
    k("u", 'u'),
    k("i", 'i'),
    k("o", 'o'),
    k("p", 'p'),
    ks("[", "{", '[', '{'),
    ks("]", "}", ']', '}'),
    ks("\\", "|", '\\', '|'),
};

const ROW2 = [_]KeySpec{
    kw("Caps", 0, 2, .shift),
    k("a", 'a'),
    k("s", 's'),
    k("d", 'd'),
    k("f", 'f'),
    k("g", 'g'),
    k("h", 'h'),
    k("j", 'j'),
    k("k", 'k'),
    k("l", 'l'),
    ks(";", ":", ';', ':'),
    ks("'", "\"", '\'', '"'),
    kw("Enter", input.KEY_ENTER, 2, .special),
};

const ROW3 = [_]KeySpec{
    kw("Shift", 0, 3, .shift),
    k("z", 'z'),
    k("x", 'x'),
    k("c", 'c'),
    k("v", 'v'),
    k("b", 'b'),
    k("n", 'n'),
    k("m", 'm'),
    ks(",", "<", ',', '<'),
    ks(".", ">", '.', '>'),
    ks("/", "?", '/', '?'),
    kw("Shift", 0, 2, .shift),
};

const ROW4 = [_]KeySpec{
    kw("Ctrl", 0, 2, .ctrl),
    kw("Hide", 0, 2, .hide),
    kw("Space", ' ', 6, .char),
    kw("<", input.KEY_LEFT, 1, .special),
    kw(">", input.KEY_RIGHT, 1, .special),
    kw("^", input.KEY_UP, 1, .special),
    kw("v", input.KEY_DOWN, 1, .special),
    kw("Esc", input.KEY_ESCAPE, 2, .special),
};

const ROWS = [_][]const KeySpec{
    ROW0[0..],
    ROW1[0..],
    ROW2[0..],
    ROW3[0..],
    ROW4[0..],
};

const GAP: u32 = 3;
const PAD: u32 = 6;
const KEY_H: u32 = 28;
const ROW_COUNT: u32 = 5;

pub const Osk = struct {
    /// Always false until the user toggles with the hotkey or Hide.
    visible: bool = false,
    shift_on: bool = false,
    ctrl_on: bool = false,
    pressed_row: i32 = -1,
    pressed_col: i32 = -1,

    pub fn reset(self: *Osk) void {
        self.visible = false;
        self.shift_on = false;
        self.ctrl_on = false;
        self.pressed_row = -1;
        self.pressed_col = -1;
    }

    /// Returns true if the key was consumed as the OSK hotkey.
    pub fn handleHotkey(self: *Osk, key: u32, mods: u32) bool {
        const ctrl = (mods & MOD_CTRL) != 0;
        const shift = (mods & MOD_SHIFT) != 0;
        const lower = if (key >= 'A' and key <= 'Z') key + 32 else key;
        if (ctrl and shift and lower == HOTKEY) {
            self.visible = !self.visible;
            if (!self.visible) {
                self.shift_on = false;
                self.ctrl_on = false;
                self.clearPress();
            }
            return true;
        }
        return false;
    }

    /// Handle host pointer. Returns true if the event was consumed by the OSK.
    pub fn handlePointer(self: *Osk, x: u32, y: u32, buttons: u32, kind: u32, fb_w: u32, fb_h: u32) bool {
        if (!self.visible) return false;
        const panel = panelRect(fb_w, fb_h);
        const inside = x >= panel.x and x < panel.x + panel.w and y >= panel.y and y < panel.y + panel.h;
        if (!inside) {
            if (kind == @intFromEnum(PtrKind.up)) self.clearPress();
            return false;
        }

        if (kind == @intFromEnum(PtrKind.down) and (buttons & 1) != 0) {
            if (hitTest(x, y, fb_w, fb_h)) |hit| {
                self.pressed_row = @intCast(hit.row);
                self.pressed_col = @intCast(hit.col);
                self.activate(ROWS[hit.row][hit.col]);
            }
            return true;
        }
        if (kind == @intFromEnum(PtrKind.up)) {
            self.clearPress();
            return true;
        }
        return true;
    }

    pub fn draw(self: *const Osk, fb: []u8, width: u32, height: u32, stride: u32) void {
        if (!self.visible) return;
        const panel = panelRect(width, height);
        fill(fb, stride, width, height, panel.x, panel.y, panel.w, panel.h, COLOR_PANEL);

        const hint = "ctrl+shift+k toggles";
        drawText(fb, stride, width, panel.x + PAD, panel.y + 4, hint, COLOR_DIM);

        const unit = keyUnitWidth(width);
        var row: u32 = 0;
        while (row < ROW_COUNT) : (row += 1) {
            const specs = ROWS[row];
            const row_units = rowUnitCount(specs);
            const row_w = row_units * unit + (row_units -| 1) * GAP;
            var x: u32 = if (width > row_w) (width - row_w) / 2 else PAD;
            const y = panel.y + 18 + row * (KEY_H + GAP);

            var col: u32 = 0;
            while (col < specs.len) : (col += 1) {
                const spec = specs[col];
                const kw_px = spec.units * unit + (spec.units -| 1) * GAP;
                const active = self.pressed_row == @as(i32, @intCast(row)) and self.pressed_col == @as(i32, @intCast(col));
                const mod_lit = (spec.kind == .shift and self.shift_on) or (spec.kind == .ctrl and self.ctrl_on);
                const bg = if (active or mod_lit) COLOR_KEY_ACTIVE else if (spec.kind == .shift or spec.kind == .ctrl or spec.kind == .hide) COLOR_KEY_MOD else COLOR_KEY;
                fill(fb, stride, width, height, x, y, kw_px, KEY_H, bg);
                fill(fb, stride, width, height, x, y, kw_px, 1, COLOR_BORDER);
                fill(fb, stride, width, height, x, y + KEY_H - 1, kw_px, 1, COLOR_BORDER);
                fill(fb, stride, width, height, x, y, 1, KEY_H, COLOR_BORDER);
                fill(fb, stride, width, height, x + kw_px - 1, y, 1, KEY_H, COLOR_BORDER);

                var label_buf: [8]u8 = undefined;
                const label = keyLabel(spec, self.shift_on, &label_buf);
                const fg = if (mod_lit) COLOR_ACCENT else COLOR_FG;
                const lx = x + (kw_px -| @as(u32, @intCast(label.len * font.GLYPH_W))) / 2;
                const ly = y + (KEY_H -| font.GLYPH_H) / 2;
                drawText(fb, stride, width, lx, ly, label, fg);

                x += kw_px + GAP;
            }
        }
    }

    fn activate(self: *Osk, spec: KeySpec) void {
        switch (spec.kind) {
            .hide => {
                self.visible = false;
                self.shift_on = false;
                self.ctrl_on = false;
                self.clearPress();
            },
            .shift => self.shift_on = !self.shift_on,
            .ctrl => self.ctrl_on = !self.ctrl_on,
            .char, .special => {
                var code = if (self.shift_on) spec.code_shift else spec.code;
                if (spec.kind == .char and self.shift_on and code >= 'a' and code <= 'z') {
                    code = code - 32;
                }
                var mods: u32 = 0;
                if (self.shift_on) mods |= MOD_SHIFT;
                if (self.ctrl_on) mods |= MOD_CTRL;
                input.push(code, mods);
                // One-shot shift after a character (Caps/Shift sticky until used once for letters).
                if (spec.kind == .char and self.shift_on) self.shift_on = false;
            },
        }
    }

    fn clearPress(self: *Osk) void {
        self.pressed_row = -1;
        self.pressed_col = -1;
    }
};

const Rect = struct { x: u32, y: u32, w: u32, h: u32 };
const Hit = struct { row: u32, col: u32 };

fn panelHeight() u32 {
    return 18 + ROW_COUNT * KEY_H + (ROW_COUNT - 1) * GAP + PAD;
}

fn panelRect(fb_w: u32, fb_h: u32) Rect {
    const h = panelHeight();
    const y: u32 = if (fb_h > h) fb_h - h else 0;
    return .{ .x = 0, .y = y, .w = fb_w, .h = h };
}

fn keyUnitWidth(fb_w: u32) u32 {
    // Number row is the densest (~15 units).
    const units: u32 = 15;
    const gaps = units -| 1;
    const usable = if (fb_w > 2 * PAD + gaps * GAP) fb_w - 2 * PAD - gaps * GAP else unitFallback();
    const u = usable / units;
    return if (u < 18) 18 else u;
}

fn unitFallback() u32 {
    return 18 * 15;
}

fn rowUnitCount(specs: []const KeySpec) u32 {
    var n: u32 = 0;
    for (specs) |s| n += s.units;
    return n;
}

fn keyLabel(spec: KeySpec, shift_on: bool, buf: *[8]u8) []const u8 {
    if (!shift_on or spec.kind != .char) return spec.label;
    if (spec.label.len == 1 and spec.label[0] >= 'a' and spec.label[0] <= 'z' and
        spec.label_shift.len == 1 and spec.label_shift[0] == spec.label[0])
    {
        buf[0] = spec.label[0] - 32;
        return buf[0..1];
    }
    return spec.label_shift;
}

fn hitTest(px: u32, py: u32, fb_w: u32, fb_h: u32) ?Hit {
    const panel = panelRect(fb_w, fb_h);
    if (py < panel.y + 18) return null;
    const unit = keyUnitWidth(fb_w);
    const local_y = py -| (panel.y + 18);
    const row = local_y / (KEY_H + GAP);
    if (row >= ROW_COUNT) return null;
    const row_y = panel.y + 18 + row * (KEY_H + GAP);
    if (py < row_y or py >= row_y + KEY_H) return null;

    const specs = ROWS[row];
    const row_units = rowUnitCount(specs);
    const row_w = row_units * unit + (row_units -| 1) * GAP;
    var x: u32 = if (fb_w > row_w) (fb_w - row_w) / 2 else PAD;

    var col: u32 = 0;
    while (col < specs.len) : (col += 1) {
        const spec = specs[col];
        const kw_px = spec.units * unit + (spec.units -| 1) * GAP;
        if (px >= x and px < x + kw_px) return .{ .row = row, .col = col };
        x += kw_px + GAP;
    }
    return null;
}

fn fill(fb: []u8, stride: u32, fb_w: u32, fb_h: u32, x0: u32, y0: u32, w: u32, h: u32, color: u32) void {
    var y: u32 = y0;
    while (y < y0 + h and y < fb_h) : (y += 1) {
        var x: u32 = x0;
        while (x < x0 + w and x < fb_w) : (x += 1) {
            put(fb, stride, fb_w, x, y, color);
        }
    }
}

fn put(fb: []u8, stride: u32, width: u32, x: u32, y: u32, color: u32) void {
    if (x >= width) return;
    const o: usize = @as(usize, y) * @as(usize, stride) + @as(usize, x) * 4;
    if (o + 3 >= fb.len) return;
    // Simple over: treat high alpha as opaque for OSK chrome.
    fb[o + 0] = @truncate(color >> 16);
    fb[o + 1] = @truncate(color >> 8);
    fb[o + 2] = @truncate(color);
    fb[o + 3] = @truncate(color >> 24);
}

fn drawText(fb: []u8, stride: u32, width: u32, x0: u32, y0: u32, text: []const u8, color: u32) void {
    var i: u32 = 0;
    for (text) |ch| {
        drawGlyph(fb, stride, width, x0 + i * font.GLYPH_W, y0, ch, color);
        i += 1;
    }
}

fn drawGlyph(fb: []u8, stride: u32, width: u32, x0: u32, y0: u32, ch: u8, color: u32) void {
    const g = font.glyph(ch);
    var row: u32 = 0;
    while (row < 8) : (row += 1) {
        const bits = g.*[row];
        var col: u32 = 0;
        while (col < 8) : (col += 1) {
            if ((bits & (@as(u8, 1) << @intCast(col))) != 0) {
                put(fb, stride, width, x0 + col, y0 + row, color);
            }
        }
    }
}
