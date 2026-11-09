//! SoftUI framebuffer text console. All glyphs drawn by SoftUI — never host text.

const font = @import("font.zig");

pub const DEFAULT_FG: u32 = 0xFFD7E0EA;
pub const DEFAULT_BG: u32 = 0xFF0B0E12;
pub const DEFAULT_CURSOR: u32 = 0xFF50B4FF;
pub const DEFAULT_DIM: u32 = 0xFF7A8796;

const MAX_COLS: usize = 240;
const MAX_ROWS: usize = 120;
const LINE_CAP: usize = 256;
/// Row pitch in pixels (glyph is 16px; extra space is leading/padding).
const LINE_HEIGHT: u32 = font.GLYPH_H + 4;
const GLYPH_Y_PAD: u32 = (LINE_HEIGHT - font.GLYPH_H) / 2;

pub const Console = struct {
    cols: u32 = 0,
    rows: u32 = 0,
    cell_w: u32 = font.GLYPH_W,
    cell_h: u32 = LINE_HEIGHT,
    /// Scrollback lines as fixed buffers (row-major chars, space-padded).
    lines: [MAX_ROWS][MAX_COLS]u8 = undefined,
    line_lens: [MAX_ROWS]u16 = @splat(0),
    /// Number of used scroll rows (0..rows), bottom is current output row.
    used: u32 = 0,
    dirty: bool = true,
    cursor_on: bool = true,
    blink_div: u32 = 0,
    fg: u32 = DEFAULT_FG,
    bg: u32 = DEFAULT_BG,
    cursor_color: u32 = DEFAULT_CURSOR,

    pub fn init(self: *Console, fb_w: u32, fb_h: u32) void {
        self.cell_w = font.GLYPH_W;
        self.cell_h = LINE_HEIGHT;
        self.cols = @min(fb_w / self.cell_w, @as(u32, MAX_COLS));
        self.rows = @min(fb_h / self.cell_h, @as(u32, MAX_ROWS));
        self.used = 0;
        self.dirty = true;
        if (self.fg == 0) self.fg = DEFAULT_FG;
        if (self.bg == 0) self.bg = DEFAULT_BG;
        if (self.cursor_color == 0) self.cursor_color = DEFAULT_CURSOR;
        self.clear();
    }

    pub fn setFg(self: *Console, color: u32) void {
        self.fg = color | 0xFF000000;
        self.dirty = true;
    }

    pub fn setBg(self: *Console, color: u32) void {
        self.bg = color | 0xFF000000;
        self.dirty = true;
    }

    pub fn resetColors(self: *Console) void {
        self.fg = DEFAULT_FG;
        self.bg = DEFAULT_BG;
        self.cursor_color = DEFAULT_CURSOR;
        self.dirty = true;
    }

    pub fn clear(self: *Console) void {
        var r: u32 = 0;
        while (r < MAX_ROWS) : (r += 1) {
            @memset(self.lines[r][0..MAX_COLS], ' ');
            self.line_lens[r] = 0;
        }
        self.used = 1;
        self.dirty = true;
    }

    pub fn write(self: *Console, text: []const u8) void {
        for (text) |c| {
            self.writeChar(c);
        }
        self.dirty = true;
    }

    pub fn writeChar(self: *Console, c: u8) void {
        if (c == '\n') {
            self.newline();
            return;
        }
        if (c == '\r') return;
        if (c == '\t') {
            self.writeChar(' ');
            self.writeChar(' ');
            self.writeChar(' ');
            self.writeChar(' ');
            return;
        }
        const ch: u8 = if (c >= 32 and c < 127) c else '?';
        if (self.used == 0) self.used = 1;
        const row: usize = self.used - 1;
        var len = self.line_lens[row];
        if (len >= self.cols) {
            self.newline();
            len = self.line_lens[self.used - 1];
        }
        const r2: usize = self.used - 1;
        self.lines[r2][len] = ch;
        self.line_lens[r2] = len + 1;
        self.dirty = true;
    }

    fn newline(self: *Console) void {
        if (self.used < self.rows) {
            self.used += 1;
            const r: usize = self.used - 1;
            @memset(self.lines[r][0..MAX_COLS], ' ');
            self.line_lens[r] = 0;
        } else {
            // Scroll up.
            var r: usize = 0;
            while (r + 1 < self.rows) : (r += 1) {
                self.lines[r] = self.lines[r + 1];
                self.line_lens[r] = self.line_lens[r + 1];
            }
            const last: usize = self.rows - 1;
            @memset(self.lines[last][0..MAX_COLS], ' ');
            self.line_lens[last] = 0;
        }
        self.dirty = true;
    }

    pub fn currentLineLen(self: *const Console) u32 {
        if (self.used == 0) return 0;
        return self.line_lens[self.used - 1];
    }

    /// Replace the editable suffix of the current line (after `prompt_len` chars).
    pub fn setInputLine(self: *Console, prompt: []const u8, input: []const u8) void {
        if (self.used == 0) self.used = 1;
        const r: usize = self.used - 1;
        @memset(self.lines[r][0..MAX_COLS], ' ');
        var i: usize = 0;
        while (i < prompt.len and i < self.cols) : (i += 1) {
            self.lines[r][i] = prompt[i];
        }
        var j: usize = 0;
        while (j < input.len and i < self.cols) : (j += 1) {
            self.lines[r][i] = input[j];
            i += 1;
        }
        self.line_lens[r] = @intCast(i);
        self.dirty = true;
    }

    pub fn tickBlink(self: *Console) void {
        self.blink_div +%= 1;
        if (self.blink_div % 30 == 0) {
            self.cursor_on = !self.cursor_on;
            self.dirty = true;
        }
    }

    pub fn draw(
        self: *Console,
        fb: []u8,
        width: u32,
        height: u32,
        stride: u32,
        show_cursor: bool,
        origin_y: u32,
    ) void {
        _ = height;
        // Clear console band (may sit below SoftUI app chrome).
        var y: u32 = 0;
        while (y < self.rows * self.cell_h) : (y += 1) {
            var x: u32 = 0;
            while (x < self.cols * self.cell_w) : (x += 1) {
                put(fb, stride, width, x, origin_y + y, self.bg);
            }
        }

        var row: u32 = 0;
        while (row < self.used and row < self.rows) : (row += 1) {
            const len = self.line_lens[row];
            var col: u32 = 0;
            while (col < len and col < self.cols) : (col += 1) {
                const ch = self.lines[row][col];
                drawGlyph(
                    fb,
                    stride,
                    width,
                    col * self.cell_w,
                    origin_y + row * self.cell_h + GLYPH_Y_PAD,
                    ch,
                    self.fg,
                );
            }
        }

        if (show_cursor and self.cursor_on and self.used > 0) {
            const r = self.used - 1;
            const c = self.line_lens[r];
            if (c < self.cols) {
                const x0 = c * self.cell_w;
                const y0 = origin_y + r * self.cell_h + GLYPH_Y_PAD;
                var yy: u32 = 0;
                while (yy < font.GLYPH_H) : (yy += 1) {
                    var xx: u32 = 0;
                    while (xx < 2) : (xx += 1) {
                        put(fb, stride, width, x0 + xx, y0 + yy, self.cursor_color);
                    }
                }
            }
        }
        self.dirty = false;
    }
};

fn put(fb: []u8, stride: u32, width: u32, x: u32, y: u32, color: u32) void {
    if (x >= width) return;
    const o: usize = @as(usize, y) * @as(usize, stride) + @as(usize, x) * 4;
    if (o + 3 >= fb.len) return;
    fb[o + 0] = @truncate(color >> 16);
    fb[o + 1] = @truncate(color >> 8);
    fb[o + 2] = @truncate(color);
    fb[o + 3] = @truncate(color >> 24);
}

fn drawGlyph(fb: []u8, stride: u32, width: u32, x0: u32, y0: u32, ch: u8, color: u32) void {
    font.blitGlyph(fb, stride, width, x0, y0, ch, color);
}
