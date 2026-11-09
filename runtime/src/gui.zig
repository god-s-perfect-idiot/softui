//! SoftUI bootloader + hybrid shell.
//! Minimal text UI for fast iteration: black background, white labels.

const font = @import("font.zig");
const input = @import("input.zig");

pub const BOOT_TIMEOUT_NS: u64 = 10_000_000_000;
pub const BAR_H: u32 = 28;
pub const TRAY_H: u32 = 20;
pub const HIT_MIN: u32 = 24;
pub const MAX_SESSIONS: u32 = 6;

pub const Stage = enum { bootloader, desktop, app, cli };
pub const Choice = enum { gui, cli };
pub const Launch = enum {
    shell,
    clock,
    cursor,
    keys,
    image,
    music,
    paint,
    uikit,
    colors,
    text,
    donut,
    plasma,
    stars,
    cube,
    fire,
    calc,
    hello,
};

const TILE_COUNT: u32 = 17;
const TILE_LABELS = [_][]const u8{
    "Shell",
    "Clock",
    "Cursor",
    "Keys",
    "Image",
    "Music",
    "Paint",
    "UIKit",
    "Colors",
    "Text",
    "Donut",
    "Plasma",
    "Stars",
    "Cube",
    "Fire",
    "Calc",
    "Hello",
};

const COLOR_BG: u32 = 0xFF000000;
const COLOR_FG: u32 = 0xFFFFFFFF;
const COLOR_DIM: u32 = 0xFFAAAAAA;

const TAP_SLOP: u32 = 16;
const LIST_PAD_X: u32 = 12;
const LIST_ROW_H: u32 = font.GLYPH_H + 8;

const Rect = struct { x: u32, y: u32, w: u32, h: u32 };

pub const Gui = struct {
    stage: Stage = .bootloader,
    choice: Choice = .gui,
    tile: u32 = 0,
    deadline_ns: u64 = 0,
    armed: bool = false,
    app_launch: Launch = .shell,
    layout_w: u32 = 0,
    layout_h: u32 = 0,
    ptr_down: bool = false,
    ptr_x: u32 = 0,
    ptr_y: u32 = 0,
    now_ns: u64 = 0,
    on_choose_cli: ?*const fn () void = null,
    on_choose_gui: ?*const fn () void = null,
    on_launch: ?*const fn (Launch) void = null,
    on_close_app: ?*const fn () void = null,
    on_home: ?*const fn () void = null,
    on_toggle_osk: ?*const fn () void = null,
    session_launches: [MAX_SESSIONS]Launch = undefined,
    session_used: [MAX_SESSIONS]bool = undefined,
    session_focus: u32 = 0,

    pub fn start(self: *Gui) void {
        self.stage = .bootloader;
        self.choice = .gui;
        self.tile = 0;
        self.deadline_ns = 0;
        self.armed = false;
        self.ptr_down = false;
        self.session_focus = 0;
        var i: u32 = 0;
        while (i < MAX_SESSIONS) : (i += 1) self.session_used[i] = false;
    }

    pub fn returnToDesktop(self: *Gui) void {
        self.stage = .desktop;
        self.ptr_down = false;
    }

    pub fn appTitle(self: *const Gui) []const u8 {
        return TILE_LABELS[@intFromEnum(self.app_launch)];
    }

    pub fn sessionCount(self: *const Gui) u32 {
        var n: u32 = 0;
        var i: u32 = 0;
        while (i < MAX_SESSIONS) : (i += 1) {
            if (self.session_used[i]) n += 1;
        }
        return n;
    }

    pub fn tick(self: *Gui, now_ns: u64, width: u32, height: u32) void {
        self.layout_w = width;
        self.layout_h = height;
        self.now_ns = now_ns;
        switch (self.stage) {
            .bootloader => self.tickBootloader(now_ns),
            .desktop => self.tickDesktop(),
            .app => self.tickApp(),
            .cli => self.drainPointersOnly(),
        }
    }

    pub fn draw(self: *Gui, fb: []u8, width: u32, height: u32, stride: u32, now_ns: u64) void {
        self.layout_w = width;
        self.layout_h = height;
        self.now_ns = now_ns;
        switch (self.stage) {
            .bootloader => self.drawBootloader(fb, width, height, stride, now_ns),
            .desktop => self.drawDesktop(fb, width, height, stride, now_ns),
            .app => self.drawAppChrome(fb, width, height, stride, now_ns),
            .cli => {},
        }
    }

    fn tickBootloader(self: *Gui, now_ns: u64) void {
        if (!self.armed) {
            self.deadline_ns = now_ns +% BOOT_TIMEOUT_NS;
            self.armed = true;
        }
        self.drainPointers(now_ns);
        while (input.pop()) |ev| {
            self.handleBootKey(ev, now_ns);
            if (self.stage != .bootloader) return;
        }
        if (self.stage == .bootloader and self.armed and now_ns >= self.deadline_ns) {
            self.commitGui();
        }
    }

    fn tickDesktop(self: *Gui) void {
        self.drainPointers(0);
        while (input.pop()) |ev| self.handleDesktopKey(ev);
    }

    fn tickApp(self: *Gui) void {
        // Keys belong to SoftShell / demos — chrome is pointer only.
        self.drainPointers(0);
    }

    fn drainPointersOnly(self: *Gui) void {
        _ = self;
        while (input.popPointer()) |_| {}
    }

    fn drainPointers(self: *Gui, now_ns: u64) void {
        while (input.popPointer()) |p| {
            self.handlePointer(p, now_ns);
            if (self.stage != .bootloader and self.stage != .desktop and self.stage != .app) return;
        }
    }

    fn resetDeadline(self: *Gui, now_ns: u64) void {
        self.deadline_ns = now_ns +% BOOT_TIMEOUT_NS;
        self.armed = true;
    }

    fn handleBootKey(self: *Gui, ev: input.Event, now_ns: u64) void {
        const key = ev.key;
        if (key == input.KEY_LEFT or key == input.KEY_UP) {
            self.choice = .gui;
            self.resetDeadline(now_ns);
            return;
        }
        if (key == input.KEY_RIGHT or key == input.KEY_DOWN) {
            self.choice = .cli;
            self.resetDeadline(now_ns);
            return;
        }
        if (key == input.KEY_ENTER or key == ' ') {
            switch (self.choice) {
                .gui => self.commitGui(),
                .cli => self.commitCli(),
            }
        }
    }

    fn commitGui(self: *Gui) void {
        self.stage = .desktop;
        self.tile = 0;
        if (self.on_choose_gui) |cb| cb();
    }

    fn commitCli(self: *Gui) void {
        self.stage = .cli;
        if (self.on_choose_cli) |cb| cb();
    }

    fn handleDesktopKey(self: *Gui, ev: input.Event) void {
        const key = ev.key;
        if (key == input.KEY_UP) {
            if (self.tile == 0) self.tile = TILE_COUNT - 1 else self.tile -= 1;
            return;
        }
        if (key == input.KEY_DOWN) {
            self.tile = (self.tile + 1) % TILE_COUNT;
            return;
        }
        if (key == input.KEY_ENTER or key == ' ') {
            self.launchTile(self.tile);
        }
    }

    fn findSessionForLaunch(self: *const Gui, launch: Launch) ?u32 {
        var i: u32 = 0;
        while (i < MAX_SESSIONS) : (i += 1) {
            if (self.session_used[i] and self.session_launches[i] == launch) return i;
        }
        return null;
    }

    fn addSession(self: *Gui, launch: Launch) bool {
        var i: u32 = 0;
        while (i < MAX_SESSIONS) : (i += 1) {
            if (!self.session_used[i]) {
                self.session_used[i] = true;
                self.session_launches[i] = launch;
                self.session_focus = i;
                self.app_launch = launch;
                return true;
            }
        }
        return false;
    }

    fn focusSession(self: *Gui, idx: u32) void {
        self.session_focus = idx;
        self.app_launch = self.session_launches[idx];
    }

    fn switchToSession(self: *Gui, idx: u32) void {
        self.focusSession(idx);
        self.stage = .app;
        if (self.on_launch) |cb| cb(self.app_launch);
    }

    fn closeFocusedApp(self: *Gui) void {
        if (self.session_used[self.session_focus]) {
            self.session_used[self.session_focus] = false;
        } else {
            var i: u32 = 0;
            while (i < MAX_SESSIONS) : (i += 1) {
                if (self.session_used[i] and self.session_launches[i] == self.app_launch) {
                    self.session_used[i] = false;
                    break;
                }
            }
        }
        if (self.on_close_app) |cb| cb();

        var last: ?u32 = null;
        var i: u32 = 0;
        while (i < MAX_SESSIONS) : (i += 1) {
            if (self.session_used[i]) last = i;
        }
        if (last) |li| {
            self.focusSession(li);
            self.stage = .app;
            if (self.on_launch) |cb| cb(self.app_launch);
        } else {
            self.returnToDesktop();
        }
    }

    fn launchTile(self: *Gui, idx: u32) void {
        const launch: Launch = @enumFromInt(@as(u8, @intCast(idx)));
        self.tile = idx;
        if (self.findSessionForLaunch(launch)) |si| {
            self.focusSession(si);
        } else {
            if (!self.addSession(launch)) {
                self.app_launch = launch;
            }
        }
        self.stage = .app;
        if (self.on_launch) |cb| cb(launch);
    }

    fn activateTrayAt(self: *Gui, x: u32, y: u32) void {
        const w = self.layout_w;
        const h = self.layout_h;
        if (w == 0 or h == 0) return;
        if (trayHitSession(self, x, y, w, h)) |si| {
            self.switchToSession(si);
        }
    }

    fn handlePointer(self: *Gui, p: input.Pointer, now_ns: u64) void {
        if (p.kind == input.PTR_DOWN) {
            self.ptr_down = true;
            self.ptr_x = p.x;
            self.ptr_y = p.y;
            return;
        }
        if (p.kind != input.PTR_UP or !self.ptr_down) return;
        self.ptr_down = false;

        const dx_i: i32 = @as(i32, @intCast(p.x)) - @as(i32, @intCast(self.ptr_x));
        const dy_i: i32 = @as(i32, @intCast(p.y)) - @as(i32, @intCast(self.ptr_y));
        const adx: u32 = if (dx_i < 0) @intCast(-dx_i) else @intCast(dx_i);
        const ady: u32 = if (dy_i < 0) @intCast(-dy_i) else @intCast(dy_i);
        if (adx > TAP_SLOP or ady > TAP_SLOP) return;
        self.activateAt(self.ptr_x, self.ptr_y, now_ns);
    }

    fn activateAt(self: *Gui, x: u32, y: u32, now_ns: u64) void {
        const w = self.layout_w;
        const h = self.layout_h;
        if (w == 0 or h == 0) return;

        if (self.stage == .desktop or self.stage == .app) {
            if (hit(x, y, kbdBtnRect(w))) {
                if (self.on_toggle_osk) |cb| cb();
                return;
            }
        }

        if (self.stage == .app) {
            if (hit(x, y, homeBtnRect(w))) {
                if (self.on_home) |cb| cb();
                self.returnToDesktop();
                return;
            }
            if (hit(x, y, exitBtnRect(w))) {
                self.closeFocusedApp();
                return;
            }
            if (hit(x, y, trayRect(w, h))) {
                self.activateTrayAt(x, y);
                return;
            }
            return;
        }

        if (self.stage == .bootloader) {
            if (hit(x, y, bootOptionRect(w, h, 0))) {
                self.choice = .gui;
                self.commitGui();
                return;
            }
            if (hit(x, y, bootOptionRect(w, h, 1))) {
                self.choice = .cli;
                self.commitCli();
                return;
            }
            self.resetDeadline(now_ns);
            return;
        }

        if (self.stage == .desktop) {
            if (hit(x, y, trayRect(w, h))) {
                self.activateTrayAt(x, y);
                return;
            }
            var i: u32 = 0;
            while (i < TILE_COUNT) : (i += 1) {
                if (hit(x, y, appListRect(w, h, i))) {
                    self.launchTile(i);
                    return;
                }
            }
        }
    }

    fn drawBootloader(self: *Gui, fb: []u8, width: u32, height: u32, stride: u32, now_ns: u64) void {
        fill(fb, stride, width, height, 0, 0, width, height, COLOR_BG);

        const labels = [_][]const u8{ "GUI", "CLI" };
        var i: u32 = 0;
        while (i < 2) : (i += 1) {
            const selected = (i == 0 and self.choice == .gui) or (i == 1 and self.choice == .cli);
            const r = bootOptionRect(width, height, i);
            var line_buf: [24]u8 = undefined;
            const line = formatMarked(&line_buf, labels[i], selected);
            drawText(fb, stride, width, r.x, r.y + (r.h -| font.GLYPH_H) / 2, line, COLOR_FG);
        }

        var msg_buf: [24]u8 = undefined;
        const msg = formatAutoMsg(&msg_buf, remainingSeconds(self.deadline_ns, now_ns, self.armed));
        const msg_y = bootOptionRect(width, height, 1).y + LIST_ROW_H + 12;
        if (msg_y + font.GLYPH_H < height) {
            drawText(fb, stride, width, LIST_PAD_X, msg_y, msg, COLOR_DIM);
        }
    }

    fn drawDesktop(self: *Gui, fb: []u8, width: u32, height: u32, stride: u32, now_ns: u64) void {
        fill(fb, stride, width, height, 0, 0, width, height, COLOR_BG);
        self.drawTopBar(fb, width, height, stride, now_ns, "SoftUI", .desktop);

        const list_bottom = height -| TRAY_H;
        var i: u32 = 0;
        while (i < TILE_COUNT) : (i += 1) {
            const r = appListRect(width, height, i);
            if (r.y + r.h > list_bottom) break;
            var line_buf: [24]u8 = undefined;
            const line = formatMarked(&line_buf, TILE_LABELS[i], i == self.tile);
            drawText(fb, stride, width, r.x, r.y + (r.h -| font.GLYPH_H) / 2, line, COLOR_FG);
        }
        self.drawTray(fb, width, height, stride);
    }

    pub fn drawAppChrome(self: *Gui, fb: []u8, width: u32, height: u32, stride: u32, now_ns: u64) void {
        self.drawTopBar(fb, width, height, stride, now_ns, self.appTitle(), .app);
        self.drawTray(fb, width, height, stride);
    }

    const TopBarMode = enum { desktop, app };

    fn drawTopBar(self: *Gui, fb: []u8, width: u32, height: u32, stride: u32, now_ns: u64, title: []const u8, mode: TopBarMode) void {
        _ = now_ns;
        fill(fb, stride, width, height, 0, 0, width, BAR_H, COLOR_BG);
        const ty = (BAR_H -| font.GLYPH_H) / 2;
        drawText(fb, stride, width, LIST_PAD_X, ty, title, COLOR_FG);

        const kbd = kbdBtnRect(width);
        switch (mode) {
            .desktop => {
                var dbg_buf: [28]u8 = undefined;
                const dbg = formatResLine(&dbg_buf, width, height);
                const title_w: u32 = font.textWidth(title);
                const dbg_x = LIST_PAD_X + title_w + 16;
                if (dbg_x + font.textWidth(dbg) + 8 < kbd.x) {
                    drawText(fb, stride, width, dbg_x, ty, dbg, COLOR_DIM);
                }
                drawText(fb, stride, width, kbd.x, ty, "kbd", COLOR_FG);
            },
            .app => {
                const home = homeBtnRect(width);
                const exit = exitBtnRect(width);
                drawText(fb, stride, width, home.x, ty, "home", COLOR_FG);
                drawText(fb, stride, width, exit.x, ty, "exit", COLOR_FG);
                drawText(fb, stride, width, kbd.x, ty, "kbd", COLOR_FG);
            },
        }
        _ = self;
    }

    fn drawTray(self: *Gui, fb: []u8, width: u32, height: u32, stride: u32) void {
        const tr = trayRect(width, height);
        if (tr.h == 0 or tr.y >= height) return;
        fill(fb, stride, width, height, tr.x, tr.y, tr.w, tr.h, COLOR_BG);
        const ty = tr.y + (tr.h -| font.GLYPH_H) / 2;
        var x: u32 = LIST_PAD_X;
        var i: u32 = 0;
        while (i < MAX_SESSIONS) : (i += 1) {
            if (!self.session_used[i]) continue;
            const label = TILE_LABELS[@intFromEnum(self.session_launches[i])];
            const focused = self.stage == .app and i == self.session_focus;
            var line_buf: [24]u8 = undefined;
            const line = formatMarked(&line_buf, label, focused);
            drawText(fb, stride, width, x, ty, line, if (focused) COLOR_FG else COLOR_DIM);
            x += font.textWidth(line) + 8;
        }
    }
};

fn bootOptionRect(width: u32, height: u32, index: u32) Rect {
    _ = height;
    const y = 40 + index * LIST_ROW_H;
    return .{
        .x = LIST_PAD_X,
        .y = y,
        .w = @max(HIT_MIN * 3, width -| LIST_PAD_X * 2),
        .h = LIST_ROW_H,
    };
}

fn appListRect(width: u32, height: u32, index: u32) Rect {
    const list_bottom = height -| TRAY_H;
    const y = BAR_H + 8 + index * LIST_ROW_H;
    if (y >= list_bottom) return .{ .x = 0, .y = 0, .w = 0, .h = 0 };
    return .{
        .x = LIST_PAD_X,
        .y = y,
        .w = @max(HIT_MIN * 3, width -| LIST_PAD_X * 2),
        .h = @min(LIST_ROW_H, list_bottom - y),
    };
}

pub fn trayRect(width: u32, height: u32) Rect {
    return .{
        .x = 0,
        .y = height -| TRAY_H,
        .w = width,
        .h = TRAY_H,
    };
}

fn trayHitSession(self: *const Gui, x: u32, y: u32, width: u32, height: u32) ?u32 {
    const tr = trayRect(width, height);
    if (!hit(x, y, tr)) return null;
    var cx: u32 = LIST_PAD_X;
    var i: u32 = 0;
    while (i < MAX_SESSIONS) : (i += 1) {
        if (!self.session_used[i]) continue;
        const label = TILE_LABELS[@intFromEnum(self.session_launches[i])];
        var line_buf: [24]u8 = undefined;
        const line = formatMarked(&line_buf, label, false);
        const slot_w: u32 = font.textWidth(line) + 8;
        const r = Rect{ .x = cx, .y = tr.y, .w = slot_w, .h = tr.h };
        if (hit(x, y, r)) return i;
        cx += slot_w;
    }
    return null;
}

fn homeBtnRect(width: u32) Rect {
    const exit = exitBtnRect(width);
    const tw: u32 = 4 * font.GLYPH_W;
    return .{
        .x = exit.x -| tw -| 12,
        .y = 0,
        .w = tw + 8,
        .h = BAR_H,
    };
}

fn kbdBtnRect(width: u32) Rect {
    const tw: u32 = 3 * font.GLYPH_W;
    return .{
        .x = width -| tw -| LIST_PAD_X,
        .y = 0,
        .w = tw + LIST_PAD_X,
        .h = BAR_H,
    };
}

fn exitBtnRect(width: u32) Rect {
    const kbd = kbdBtnRect(width);
    const tw: u32 = 4 * font.GLYPH_W;
    return .{
        .x = kbd.x -| tw -| 12,
        .y = 0,
        .w = tw + 8,
        .h = BAR_H,
    };
}

fn hit(x: u32, y: u32, r: Rect) bool {
    return x >= r.x and x < r.x + r.w and y >= r.y and y < r.y + r.h;
}

fn remainingSeconds(deadline_ns: u64, now_ns: u64, armed: bool) u32 {
    if (!armed) return @intCast(BOOT_TIMEOUT_NS / 1_000_000_000);
    if (now_ns >= deadline_ns) return 0;
    return @intCast((deadline_ns - now_ns + 999_999_999) / 1_000_000_000);
}

fn formatAutoMsg(buf: *[24]u8, seconds: u32) []const u8 {
    const prefix = "GUI in ";
    var i: usize = 0;
    for (prefix) |c| {
        buf[i] = c;
        i += 1;
    }
    if (seconds >= 10) {
        buf[i] = '0' + @as(u8, @intCast(seconds / 10));
        i += 1;
        buf[i] = '0' + @as(u8, @intCast(seconds % 10));
        i += 1;
    } else {
        buf[i] = '0' + @as(u8, @intCast(seconds));
        i += 1;
    }
    buf[i] = 's';
    i += 1;
    return buf[0..i];
}

fn formatMarked(buf: *[24]u8, label: []const u8, selected: bool) []const u8 {
    var i: usize = 0;
    buf[i] = if (selected) '>' else ' ';
    i += 1;
    buf[i] = ' ';
    i += 1;
    for (label) |c| {
        if (i >= buf.len) break;
        buf[i] = c;
        i += 1;
    }
    return buf[0..i];
}

fn formatResLine(buf: *[28]u8, w: u32, h: u32) []const u8 {
    var i: usize = 0;
    i = writeU32(buf, i, w);
    buf[i] = 'x';
    i += 1;
    i = writeU32(buf, i, h);
    return buf[0..i];
}

fn writeU32(buf: []u8, start: usize, v: u32) usize {
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

fn fill(fb: []u8, stride: u32, fb_w: u32, fb_h: u32, x0: u32, y0: u32, w: u32, h: u32, color: u32) void {
    if (w == 0 or h == 0) return;
    const a: u8 = @truncate(color >> 24);
    if (a == 0) return;
    const r: u8 = @truncate(color >> 16);
    const g: u8 = @truncate(color >> 8);
    const b: u8 = @truncate(color);
    const x1 = @min(x0 +% w, fb_w);
    const y1 = @min(y0 +% h, fb_h);
    if (x0 >= x1 or y0 >= y1) return;

    if (a == 255) {
        var y: u32 = y0;
        while (y < y1) : (y += 1) {
            var o: usize = @as(usize, y) * @as(usize, stride) + @as(usize, x0) * 4;
            var x: u32 = x0;
            while (x < x1) : (x += 1) {
                if (o + 3 >= fb.len) break;
                fb[o + 0] = r;
                fb[o + 1] = g;
                fb[o + 2] = b;
                fb[o + 3] = 255;
                o += 4;
            }
        }
        return;
    }

    var y: u32 = y0;
    while (y < y1) : (y += 1) {
        var x: u32 = x0;
        while (x < x1) : (x += 1) {
            putBlend(fb, stride, fb_w, x, y, color);
        }
    }
}

fn put(fb: []u8, stride: u32, width: u32, x: u32, y: u32, color: u32) void {
    if (x >= width) return;
    const o: usize = @as(usize, y) * @as(usize, stride) + @as(usize, x) * 4;
    if (o + 3 >= fb.len) return;
    fb[o + 0] = @truncate(color >> 16);
    fb[o + 1] = @truncate(color >> 8);
    fb[o + 2] = @truncate(color);
    fb[o + 3] = @truncate(color >> 24);
}

fn putBlend(fb: []u8, stride: u32, width: u32, x: u32, y: u32, color: u32) void {
    if (x >= width) return;
    const o: usize = @as(usize, y) * @as(usize, stride) + @as(usize, x) * 4;
    if (o + 3 >= fb.len) return;
    const sa: u32 = (color >> 24) & 0xFF;
    if (sa == 0) return;
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

fn drawText(fb: []u8, stride: u32, width: u32, x0: u32, y0: u32, text: []const u8, color: u32) void {
    font.blitText(fb, stride, width, x0, y0, text, color);
}
