//! SoftUI `txedit` — nano-like SoftFS text editor (SoftUI-rendered).

const font = @import("font.zig");
const input = @import("input.zig");
const softfs = @import("softfs.zig");

pub const MOD_CTRL: u32 = 2;

const MAX_LINES: usize = 80;
const MAX_COLS: usize = 120;
const BUF_CHARS: usize = MAX_LINES * MAX_COLS;

const LINE_HEIGHT: u32 = 16;
const GLYPH_Y_PAD: u32 = (LINE_HEIGHT - font.GLYPH_H) / 2;

pub const Action = enum {
    none,
    /// Editor wants to quit back to shell (saved or discarded).
    quit,
    /// SoftFS was written; shell should persist to host storage.
    saved,
};

pub const TxEdit = struct {
    active: bool = false,
    path: [softfs.MAX_NAME + 1]u8 = @splat(0),
    path_len: u8 = 0,
    lines: [MAX_LINES][MAX_COLS]u8 = undefined,
    lens: [MAX_LINES]u16 = @splat(0),
    line_count: u32 = 1,
    cur_row: u32 = 0,
    cur_col: u32 = 0,
    scroll: u32 = 0,
    dirty: bool = false,
    status: [64]u8 = @splat(0),
    status_len: u8 = 0,
    /// Confirm quit if dirty: 0=normal, 1=awaiting y/n
    quit_confirm: bool = false,
    fg: u32 = 0xFFD7E0EA,
    bg: u32 = 0xFF0B0E12,
    accent: u32 = 0xFF50B4FF,
    dim: u32 = 0xFF7A8796,
    blink: bool = true,
    blink_div: u32 = 0,
    cols: u32 = 80,
    rows: u32 = 25,

    pub fn open(self: *TxEdit, fs: *softfs.Fs, path: []const u8, fb_w: u32, fb_h: u32, fg: u32, bg: u32) bool {
        self.* = .{};
        self.fg = fg;
        self.bg = bg;
        self.cols = @min(fb_w / font.GLYPH_W, @as(u32, MAX_COLS));
        self.rows = @min(fb_h / LINE_HEIGHT, @as(u32, MAX_LINES));
        if (self.rows < 4 or self.cols < 16) return false;

        if (path.len == 0 or path.len > softfs.MAX_NAME) return false;
        @memcpy(self.path[0..path.len], path);
        self.path_len = @intCast(path.len);

        self.clearBuffer();
        if (fs.resolve(path)) |idx| {
            if (fs.nodes[idx].kind != .file) return false;
            if (fs.fileData(idx)) |data| {
                self.loadText(data);
            }
        } else {
            // New file — create empty on first save.
            self.setStatus("New file");
        }
        self.active = true;
        self.dirty = false;
        self.quit_confirm = false;
        if (self.status_len == 0) self.setStatus("^O save  ^X exit  arrows move");
        return true;
    }

    fn clearBuffer(self: *TxEdit) void {
        var r: usize = 0;
        while (r < MAX_LINES) : (r += 1) {
            @memset(self.lines[r][0..MAX_COLS], ' ');
            self.lens[r] = 0;
        }
        self.line_count = 1;
        self.cur_row = 0;
        self.cur_col = 0;
        self.scroll = 0;
    }

    fn loadText(self: *TxEdit, data: []const u8) void {
        self.clearBuffer();
        var row: u32 = 0;
        var col: u32 = 0;
        for (data) |c| {
            if (c == '\n') {
                if (row + 1 >= MAX_LINES) break;
                row += 1;
                col = 0;
                if (row + 1 > self.line_count) self.line_count = row + 1;
                continue;
            }
            if (c == '\r') continue;
            if (c < 32 or c >= 127) continue;
            if (col >= self.cols) {
                if (row + 1 >= MAX_LINES) break;
                row += 1;
                col = 0;
                if (row + 1 > self.line_count) self.line_count = row + 1;
            }
            self.lines[row][col] = c;
            col += 1;
            if (col > self.lens[row]) self.lens[row] = @intCast(col);
        }
        if (row + 1 > self.line_count) self.line_count = row + 1;
    }

    fn setStatus(self: *TxEdit, msg: []const u8) void {
        const n = @min(msg.len, self.status.len);
        @memcpy(self.status[0..n], msg[0..n]);
        self.status_len = @intCast(n);
    }

    fn pathSlice(self: *const TxEdit) []const u8 {
        return self.path[0..self.path_len];
    }

    pub fn tickBlink(self: *TxEdit) void {
        self.blink_div +%= 1;
        if (self.blink_div % 30 == 0) self.blink = !self.blink;
    }

    pub fn handleKey(self: *TxEdit, fs: *softfs.Fs, ev: input.Event) Action {
        const key = ev.key;
        const ctrl = (ev.mods & MOD_CTRL) != 0;

        if (self.quit_confirm) {
            if (key == 'y' or key == 'Y') {
                self.active = false;
                return .quit;
            }
            if (key == 'n' or key == 'N' or key == input.KEY_ESCAPE) {
                self.quit_confirm = false;
                self.setStatus("^O save  ^X exit");
            }
            return .none;
        }

        if (ctrl) {
            const k = if (key >= 'A' and key <= 'Z') key + 32 else key;
            if (k == 'x') {
                if (self.dirty) {
                    self.quit_confirm = true;
                    self.setStatus("Save modified? (y/n)");
                } else {
                    self.active = false;
                    return .quit;
                }
                return .none;
            }
            if (k == 'o' or k == 's') {
                return if (self.save(fs)) .saved else .none;
            }
            if (k == 'g') {
                self.setStatus("^O write  ^X exit  ^G help");
                return .none;
            }
            return .none;
        }

        switch (key) {
            input.KEY_LEFT => {
                if (self.cur_col > 0) self.cur_col -= 1 else if (self.cur_row > 0) {
                    self.cur_row -= 1;
                    self.cur_col = self.lens[self.cur_row];
                }
            },
            input.KEY_RIGHT => {
                if (self.cur_col < self.lens[self.cur_row]) {
                    self.cur_col += 1;
                } else if (self.cur_row + 1 < self.line_count) {
                    self.cur_row += 1;
                    self.cur_col = 0;
                }
            },
            input.KEY_UP => {
                if (self.cur_row > 0) {
                    self.cur_row -= 1;
                    if (self.cur_col > self.lens[self.cur_row]) self.cur_col = self.lens[self.cur_row];
                }
            },
            input.KEY_DOWN => {
                if (self.cur_row + 1 < self.line_count) {
                    self.cur_row += 1;
                    if (self.cur_col > self.lens[self.cur_row]) self.cur_col = self.lens[self.cur_row];
                }
            },
            input.KEY_HOME => self.cur_col = 0,
            input.KEY_END => self.cur_col = self.lens[self.cur_row],
            input.KEY_BACKSPACE => self.backspace(),
            input.KEY_DELETE => self.deleteForward(),
            input.KEY_ENTER => self.insertNewline(),
            input.KEY_TAB => {
                self.insertChar(' ');
                self.insertChar(' ');
            },
            else => {
                if (key >= 32 and key < 127) self.insertChar(@truncate(key));
            },
        }
        self.ensureCursorVisible();
        return .none;
    }

    fn backspace(self: *TxEdit) void {
        if (self.cur_col > 0) {
            const row = self.cur_row;
            var c = self.cur_col - 1;
            while (c + 1 < self.lens[row]) : (c += 1) {
                self.lines[row][c] = self.lines[row][c + 1];
            }
            if (self.lens[row] > 0) {
                self.lens[row] -= 1;
                self.lines[row][self.lens[row]] = ' ';
            }
            self.cur_col -= 1;
            self.dirty = true;
        } else if (self.cur_row > 0) {
            // Join with previous line.
            const prev = self.cur_row - 1;
            const room = self.cols - self.lens[prev];
            const take = @min(room, self.lens[self.cur_row]);
            var i: u32 = 0;
            while (i < take) : (i += 1) {
                self.lines[prev][self.lens[prev] + i] = self.lines[self.cur_row][i];
            }
            const join_col = self.lens[prev];
            self.lens[prev] += take;
            // Shift lines up.
            var r = self.cur_row;
            while (r + 1 < self.line_count) : (r += 1) {
                self.lines[r] = self.lines[r + 1];
                self.lens[r] = self.lens[r + 1];
            }
            if (self.line_count > 1) self.line_count -= 1;
            @memset(self.lines[self.line_count][0..MAX_COLS], ' ');
            self.lens[self.line_count] = 0;
            self.cur_row = prev;
            self.cur_col = join_col;
            self.dirty = true;
        }
    }

    fn deleteForward(self: *TxEdit) void {
        const row = self.cur_row;
        if (self.cur_col < self.lens[row]) {
            var c = self.cur_col;
            while (c + 1 < self.lens[row]) : (c += 1) {
                self.lines[row][c] = self.lines[row][c + 1];
            }
            self.lens[row] -= 1;
            self.lines[row][self.lens[row]] = ' ';
            self.dirty = true;
        }
    }

    fn insertChar(self: *TxEdit, ch: u8) void {
        const row = self.cur_row;
        if (self.lens[row] >= self.cols) return;
        var c = self.lens[row];
        while (c > self.cur_col) : (c -= 1) {
            self.lines[row][c] = self.lines[row][c - 1];
        }
        self.lines[row][self.cur_col] = ch;
        self.lens[row] += 1;
        self.cur_col += 1;
        self.dirty = true;
    }

    fn insertNewline(self: *TxEdit) void {
        if (self.line_count >= MAX_LINES or self.line_count >= self.rows - 1) return;
        // Shift lines down from cur_row+1.
        var r = self.line_count;
        while (r > self.cur_row + 1) : (r -= 1) {
            self.lines[r] = self.lines[r - 1];
            self.lens[r] = self.lens[r - 1];
        }
        // Split current line.
        const rest = self.lens[self.cur_row] - self.cur_col;
        @memset(self.lines[self.cur_row + 1][0..MAX_COLS], ' ');
        var i: u32 = 0;
        while (i < rest) : (i += 1) {
            self.lines[self.cur_row + 1][i] = self.lines[self.cur_row][self.cur_col + i];
            self.lines[self.cur_row][self.cur_col + i] = ' ';
        }
        self.lens[self.cur_row + 1] = @intCast(rest);
        self.lens[self.cur_row] = @intCast(self.cur_col);
        self.line_count += 1;
        self.cur_row += 1;
        self.cur_col = 0;
        self.dirty = true;
    }

    fn ensureCursorVisible(self: *TxEdit) void {
        const view = if (self.rows > 2) self.rows - 2 else 1; // leave status rows
        if (self.cur_row < self.scroll) self.scroll = self.cur_row;
        if (self.cur_row >= self.scroll + view) self.scroll = self.cur_row + 1 - view;
    }

    fn save(self: *TxEdit, fs: *softfs.Fs) bool {
        var out: [BUF_CHARS]u8 = undefined;
        var len: usize = 0;
        var r: u32 = 0;
        while (r < self.line_count) : (r += 1) {
            const n = self.lens[r];
            if (len + n + 1 > out.len) break;
            if (n > 0) {
                @memcpy(out[len .. len + n], self.lines[r][0..n]);
                len += n;
            }
            if (r + 1 < self.line_count or n > 0) {
                out[len] = '\n';
                len += 1;
            }
        }
        const data = out[0..len];
        const path = self.pathSlice();
        if (fs.resolve(path)) |idx| {
            if (fs.nodes[idx].kind != .file) {
                self.setStatus("Not a file");
                return false;
            }
            fs.writeFile(idx, data, false) catch {
                self.setStatus("Write failed");
                return false;
            };
        } else {
            const pp = fs.resolveParent(path) orelse {
                self.setStatus("Bad path");
                return false;
            };
            const idx = fs.createFile(pp.parent, pp.name, &.{}) catch {
                self.setStatus("Create failed");
                return false;
            };
            fs.writeFile(idx, data, false) catch {
                self.setStatus("Write failed");
                return false;
            };
        }
        self.dirty = false;
        self.setStatus("Wrote file");
        return true;
    }

    pub fn draw(self: *TxEdit, fb: []u8, width: u32, height: u32, stride: u32) void {
        _ = height;
        // Clear
        var y: u32 = 0;
        while (y < self.rows * LINE_HEIGHT) : (y += 1) {
            var x: u32 = 0;
            while (x < self.cols * font.GLYPH_W) : (x += 1) {
                put(fb, stride, width, x, y, self.bg);
            }
        }

        // Title bar
        self.drawBar(fb, stride, width, 0, " txedit ", self.pathSlice(), self.accent);

        const view_rows = if (self.rows > 2) self.rows - 2 else 1;
        var vr: u32 = 0;
        while (vr < view_rows) : (vr += 1) {
            const lr = self.scroll + vr;
            if (lr >= self.line_count) break;
            const screen_row = vr + 1;
            const n = self.lens[lr];
            var c: u32 = 0;
            while (c < n and c < self.cols) : (c += 1) {
                drawGlyph(
                    fb,
                    stride,
                    width,
                    c * font.GLYPH_W,
                    screen_row * LINE_HEIGHT + GLYPH_Y_PAD,
                    self.lines[lr][c],
                    self.fg,
                );
            }
        }

        // Cursor
        if (self.blink and self.cur_row >= self.scroll and self.cur_row < self.scroll + view_rows) {
            const sr = self.cur_row - self.scroll + 1;
            const x0 = self.cur_col * font.GLYPH_W;
            const y0 = sr * LINE_HEIGHT + GLYPH_Y_PAD;
            var yy: u32 = 0;
            while (yy < font.GLYPH_H) : (yy += 1) {
                var xx: u32 = 0;
                while (xx < 2) : (xx += 1) {
                    put(fb, stride, width, x0 + xx, y0 + yy, self.accent);
                }
            }
        }

        // Status bar
        const status_row = self.rows - 1;
        var msg_buf: [80]u8 = undefined;
        var mlen: usize = 0;
        if (self.dirty) {
            const mark = "[mod] ";
            @memcpy(msg_buf[0..mark.len], mark);
            mlen = mark.len;
        }
        const st = self.status[0..self.status_len];
        const copy_n = @min(st.len, msg_buf.len - mlen);
        @memcpy(msg_buf[mlen .. mlen + copy_n], st[0..copy_n]);
        mlen += copy_n;
        self.drawBar(fb, stride, width, status_row, msg_buf[0..mlen], "", self.dim);
    }

    fn drawBar(self: *TxEdit, fb: []u8, stride: u32, width: u32, row: u32, left: []const u8, right: []const u8, color: u32) void {
        const y0 = row * LINE_HEIGHT;
        var x: u32 = 0;
        while (x < self.cols * font.GLYPH_W) : (x += 1) {
            var yy: u32 = 0;
            while (yy < LINE_HEIGHT) : (yy += 1) {
                put(fb, stride, width, x, y0 + yy, self.bg);
            }
        }
        var i: u32 = 0;
        while (i < left.len and i < self.cols) : (i += 1) {
            drawGlyph(fb, stride, width, i * font.GLYPH_W, y0 + GLYPH_Y_PAD, left[i], color);
        }
        if (right.len > 0) {
            const start: u32 = if (self.cols > right.len) self.cols - @as(u32, @intCast(right.len)) else 0;
            var j: u32 = 0;
            while (j < right.len and start + j < self.cols) : (j += 1) {
                drawGlyph(fb, stride, width, (start + j) * font.GLYPH_W, y0 + GLYPH_Y_PAD, right[j], color);
            }
        }
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
