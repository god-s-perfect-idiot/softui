//! SoftUI bootloader + desktop chrome. Guest-owned pixels; dual keyboard/pointer UX.

const font = @import("font.zig");
const input = @import("input.zig");

pub const BOOT_TIMEOUT_NS: u64 = 10_000_000_000;
pub const BAR_H: u32 = 36;
pub const HIT_MIN: u32 = 44;

pub const Stage = enum { bootloader, desktop, app, cli };

pub const Choice = enum { gui, cli };

pub const Launch = enum { shell, donut, plasma, stars, cube, fire };

const TILE_COUNT: u32 = 6;
const TILE_LABELS = [_][]const u8{
    "Shell",
    "Donut",
    "Plasma",
    "Stars",
    "Cube",
    "Fire",
};

const COLOR_BG: u32 = 0xFF0B0E12;
const COLOR_BG2: u32 = 0xFF0E1218;
const COLOR_PANEL: u32 = 0xFF141A22;
const COLOR_BAR: u32 = 0xFF10161E;
const COLOR_FG: u32 = 0xFFD7E0EA;
const COLOR_DIM: u32 = 0xFF7A8796;
const COLOR_ACCENT: u32 = 0xFF50B4FF;
const COLOR_SELECT: u32 = 0xFF1A3048;
const COLOR_SCRIM: u32 = 0xB0000000;

const TAP_SLOP: u32 = 12;

const Rect = struct { x: u32, y: u32, w: u32, h: u32 };

pub const Gui = struct {
    stage: Stage = .bootloader,
    choice: Choice = .gui,
    tile: u32 = 0,
    deadline_ns: u64 = 0,
    armed: bool = false,
    info_open: bool = false,
    app_launch: Launch = .shell,
    layout_w: u32 = 0,
    layout_h: u32 = 0,
    ptr_down: bool = false,
    ptr_x: u32 = 0,
    ptr_y: u32 = 0,
    on_choose_cli: ?*const fn () void = null,
    on_choose_gui: ?*const fn () void = null,
    on_launch: ?*const fn (Launch) void = null,
    on_close_app: ?*const fn () void = null,
    on_toggle_osk: ?*const fn () void = null,

    pub fn start(self: *Gui) void {
        self.stage = .bootloader;
        self.choice = .gui;
        self.tile = 0;
        self.deadline_ns = 0;
        self.armed = false;
        self.info_open = false;
        self.ptr_down = false;
    }

    pub fn returnToDesktop(self: *Gui) void {
        self.stage = .desktop;
        self.info_open = false;
        self.ptr_down = false;
    }

    pub fn appTitle(self: *const Gui) []const u8 {
        return switch (self.app_launch) {
            .shell => "Shell",
            .donut => "Donut",
            .plasma => "Plasma",
            .stars => "Stars",
            .cube => "Cube",
            .fire => "Fire",
        };
    }

    pub fn tick(self: *Gui, now_ns: u64, width: u32, height: u32) void {
        self.layout_w = width;
        self.layout_h = height;
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
        switch (self.stage) {
            .bootloader => self.drawBootloader(fb, width, height, stride, now_ns),
            .desktop => self.drawDesktop(fb, width, height, stride),
            .app => self.drawAppChrome(fb, width, height, stride),
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
        // Keys stay with SoftShell; Gui only owns Close via pointer.
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
        if (self.info_open) {
            if (ev.key == input.KEY_ESCAPE or ev.key == '?' or ev.key == 'i' or ev.key == 'I' or ev.key == input.KEY_ENTER) {
                self.info_open = false;
                self.resetDeadline(now_ns);
            }
            return;
        }
        const key = ev.key;
        if (key == '?' or key == 'i' or key == 'I') {
            self.info_open = true;
            self.resetDeadline(now_ns);
            return;
        }
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
        self.info_open = false;
        if (self.on_choose_gui) |cb| cb();
    }

    fn commitCli(self: *Gui) void {
        self.stage = .cli;
        self.info_open = false;
        if (self.on_choose_cli) |cb| cb();
    }

    fn handleDesktopKey(self: *Gui, ev: input.Event) void {
        if (self.info_open) {
            if (ev.key == input.KEY_ESCAPE or ev.key == '?' or ev.key == 'i' or ev.key == 'I' or ev.key == input.KEY_ENTER) {
                self.info_open = false;
            }
            return;
        }
        const key = ev.key;
        if (key == '?' or key == 'i' or key == 'I') {
            self.info_open = true;
            return;
        }
        if (key == input.KEY_LEFT) {
            if (self.tile == 0) self.tile = TILE_COUNT - 1 else self.tile -= 1;
            return;
        }
        if (key == input.KEY_RIGHT) {
            self.tile = (self.tile + 1) % TILE_COUNT;
            return;
        }
        if (key == input.KEY_UP) {
            const cols = gridCols(self.layout_w);
            if (self.tile >= cols) self.tile -= cols;
            return;
        }
        if (key == input.KEY_DOWN) {
            const cols = gridCols(self.layout_w);
            if (self.tile + cols < TILE_COUNT) self.tile += cols;
            return;
        }
        if (key == input.KEY_ENTER or key == ' ') {
            self.launchTile(self.tile);
        }
    }

    fn launchTile(self: *Gui, idx: u32) void {
        const launch: Launch = switch (idx) {
            0 => .shell,
            1 => .donut,
            2 => .plasma,
            3 => .stars,
            4 => .cube,
            else => .fire,
        };
        self.tile = idx;
        self.app_launch = launch;
        self.stage = .app;
        self.info_open = false;
        if (self.on_launch) |cb| cb(launch);
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
        const dx = if (p.x > self.ptr_x) p.x - self.ptr_x else self.ptr_x - p.x;
        const dy = if (p.y > self.ptr_y) p.y - self.ptr_y else self.ptr_y - p.y;
        if (dx > TAP_SLOP or dy > TAP_SLOP) return;
        self.activateAt(self.ptr_x, self.ptr_y, now_ns);
    }

    fn activateAt(self: *Gui, x: u32, y: u32, now_ns: u64) void {
        const w = self.layout_w;
        const h = self.layout_h;
        if (w == 0 or h == 0) return;

        if (self.stage == .app) {
            if (hit(x, y, closeRect(w))) {
                if (self.on_close_app) |cb| cb();
            }
            return;
        }

        if (self.info_open) {
            const card = infoCardRect(w, h);
            if (hit(x, y, infoCloseRect(card)) or !hit(x, y, card)) {
                self.info_open = false;
                if (self.stage == .bootloader) self.resetDeadline(now_ns);
            }
            return;
        }

        if (hit(x, y, infoBtnRect(w))) {
            self.info_open = true;
            if (self.stage == .bootloader) self.resetDeadline(now_ns);
            return;
        }
        if (hit(x, y, kbdBtnRect(w))) {
            if (self.on_toggle_osk) |cb| cb();
            if (self.stage == .bootloader) self.resetDeadline(now_ns);
            return;
        }

        if (self.stage == .bootloader) {
            const layout = bootChoiceLayout(w, h);
            if (hit(x, y, layout.gui)) {
                self.choice = .gui;
                self.commitGui();
                return;
            }
            if (hit(x, y, layout.cli)) {
                self.choice = .cli;
                self.commitCli();
                return;
            }
            self.resetDeadline(now_ns);
            return;
        }

        if (self.stage == .desktop) {
            var i: u32 = 0;
            while (i < TILE_COUNT) : (i += 1) {
                if (hit(x, y, tileRect(w, h, i))) {
                    self.launchTile(i);
                    return;
                }
            }
        }
    }

    fn drawBootloader(self: *Gui, fb: []u8, width: u32, height: u32, stride: u32, now_ns: u64) void {
        fillBg(fb, stride, width, height);
        self.drawTopBar(fb, width, height, stride, "boot");

        const title = "SoftUI";
        const subtitle = "bootloader";
        const title_y: u32 = BAR_H + if (height > BAR_H + 160) (height - BAR_H) / 2 -| 70 else 24;
        drawText(fb, stride, width, centerX(width, title), title_y, title, COLOR_ACCENT);
        drawText(fb, stride, width, centerX(width, subtitle), title_y + 18, subtitle, COLOR_DIM);

        const layout = bootChoiceLayout(width, height);
        self.drawButton(fb, stride, width, height, layout.gui, "GUI", self.choice == .gui);
        self.drawButton(fb, stride, width, height, layout.cli, "CLI", self.choice == .cli);

        var msg_buf: [24]u8 = undefined;
        const remain_s = remainingSeconds(self.deadline_ns, now_ns, self.armed);
        const msg = formatAutoMsg(&msg_buf, remain_s);
        const msg_y = @max(layout.gui.y, layout.cli.y) + @max(layout.gui.h, layout.cli.h) + 20;
        drawText(fb, stride, width, centerX(width, msg), msg_y, msg, COLOR_DIM);

        if (self.info_open) self.drawInfoSheet(fb, width, height, stride);
    }

    fn drawDesktop(self: *Gui, fb: []u8, width: u32, height: u32, stride: u32) void {
        fillBg(fb, stride, width, height);
        self.drawTopBar(fb, width, height, stride, "desktop");

        var i: u32 = 0;
        while (i < TILE_COUNT) : (i += 1) {
            const r = tileRect(width, height, i);
            const selected = i == self.tile;
            self.drawButton(fb, stride, width, height, r, TILE_LABELS[i], selected);
        }

        if (self.info_open) self.drawInfoSheet(fb, width, height, stride);
    }

    pub fn drawAppChrome(self: *Gui, fb: []u8, width: u32, height: u32, stride: u32) void {
        fill(fb, stride, width, height, 0, 0, width, BAR_H, COLOR_BAR);
        fill(fb, stride, width, height, 0, BAR_H -| 1, width, 1, COLOR_SELECT);
        drawText(fb, stride, width, 12, (BAR_H -| font.GLYPH_H) / 2, "SoftUI", COLOR_ACCENT);
        drawText(fb, stride, width, 72, (BAR_H -| font.GLYPH_H) / 2, self.appTitle(), COLOR_FG);

        var res_buf: [24]u8 = undefined;
        const res = formatRes(&res_buf, width, height);
        const res_x = width -| @as(u32, @intCast(res.len * font.GLYPH_W)) -| HIT_MIN -| 16;
        if (res_x > 120) {
            drawText(fb, stride, width, res_x, (BAR_H -| font.GLYPH_H) / 2, res, COLOR_DIM);
        }

        const close = closeRect(width);
        fill(fb, stride, width, height, close.x, close.y, close.w, close.h, COLOR_PANEL);
        drawBorder(fb, stride, width, height, close, COLOR_ACCENT);
        drawText(fb, stride, width, close.x + (close.w -| font.GLYPH_W) / 2, close.y + (close.h -| font.GLYPH_H) / 2, "X", COLOR_FG);
    }

    fn drawTopBar(_: *Gui, fb: []u8, width: u32, height: u32, stride: u32, stage_name: []const u8) void {
        fill(fb, stride, width, height, 0, 0, width, BAR_H, COLOR_BAR);
        fill(fb, stride, width, height, 0, BAR_H -| 1, width, 1, COLOR_SELECT);
        drawText(fb, stride, width, 12, (BAR_H -| font.GLYPH_H) / 2, "SoftUI", COLOR_ACCENT);
        drawText(fb, stride, width, 72, (BAR_H -| font.GLYPH_H) / 2, stage_name, COLOR_DIM);

        var res_buf: [24]u8 = undefined;
        const res = formatRes(&res_buf, width, height);
        const info = infoBtnRect(width);
        const kbd = kbdBtnRect(width);
        const res_x = kbd.x -| @as(u32, @intCast(res.len * font.GLYPH_W)) -| 12;
        if (res_x > 120) {
            drawText(fb, stride, width, res_x, (BAR_H -| font.GLYPH_H) / 2, res, COLOR_DIM);
        }

        fill(fb, stride, width, height, kbd.x, kbd.y, kbd.w, kbd.h, COLOR_PANEL);
        drawBorder(fb, stride, width, height, kbd, COLOR_DIM);
        drawText(fb, stride, width, kbd.x + (kbd.w -| 24) / 2, kbd.y + (kbd.h -| font.GLYPH_H) / 2, "kbd", COLOR_FG);

        fill(fb, stride, width, height, info.x, info.y, info.w, info.h, COLOR_PANEL);
        drawBorder(fb, stride, width, height, info, COLOR_DIM);
        drawText(fb, stride, width, info.x + (info.w -| font.GLYPH_W) / 2, info.y + (info.h -| font.GLYPH_H) / 2, "?", COLOR_FG);
    }

    fn drawInfoSheet(self: *Gui, fb: []u8, width: u32, height: u32, stride: u32) void {
        _ = self;
        // Scrim
        fill(fb, stride, width, height, 0, 0, width, height, COLOR_SCRIM);
        const card = infoCardRect(width, height);
        fill(fb, stride, width, height, card.x, card.y, card.w, card.h, COLOR_PANEL);
        drawBorder(fb, stride, width, height, card, COLOR_ACCENT);

        drawText(fb, stride, width, card.x + 16, card.y + 14, "SoftUI", COLOR_ACCENT);
        var res_buf: [28]u8 = undefined;
        const res = formatResLine(&res_buf, width, height);
        drawText(fb, stride, width, card.x + 16, card.y + 36, res, COLOR_FG);

        const lines = [_][]const u8{
            "tap or enter  activate",
            "arrows         focus",
            "esc / X        back",
            "?              close help",
            "kbd            on-screen keys",
        };
        var i: u32 = 0;
        while (i < lines.len) : (i += 1) {
            drawText(fb, stride, width, card.x + 16, card.y + 60 + i * 16, lines[i], COLOR_DIM);
        }

        const close = infoCloseRect(card);
        fill(fb, stride, width, height, close.x, close.y, close.w, close.h, COLOR_SELECT);
        drawBorder(fb, stride, width, height, close, COLOR_ACCENT);
        drawText(fb, stride, width, close.x + (close.w -| 40) / 2, close.y + (close.h -| font.GLYPH_H) / 2, "Close", COLOR_FG);
    }

    fn drawButton(
        self: *Gui,
        fb: []u8,
        stride: u32,
        width: u32,
        height: u32,
        r: Rect,
        label: []const u8,
        selected: bool,
    ) void {
        _ = self;
        fill(fb, stride, width, height, r.x, r.y, r.w, r.h, if (selected) COLOR_SELECT else COLOR_PANEL);
        drawBorder(fb, stride, width, height, r, if (selected) COLOR_ACCENT else COLOR_DIM);
        const lx = r.x + (r.w -| @as(u32, @intCast(label.len * font.GLYPH_W))) / 2;
        const ly = r.y + (r.h -| font.GLYPH_H) / 2;
        drawText(fb, stride, width, lx, ly, label, if (selected) COLOR_ACCENT else COLOR_FG);
    }
};

const BootLayout = struct { gui: Rect, cli: Rect };

fn bootChoiceLayout(width: u32, height: u32) BootLayout {
    const btn_w: u32 = if (width < 560) @max(HIT_MIN * 3, width -| 48) else 160;
    const btn_h: u32 = @max(HIT_MIN, 48);
    const gap: u32 = 16;
    const stacked = width < 560;
    const title_y: u32 = BAR_H + if (height > BAR_H + 160) (height - BAR_H) / 2 -| 70 else 24;
    const origin_y = title_y + 48;

    if (stacked) {
        const x: u32 = if (width > btn_w) (width - btn_w) / 2 else 16;
        return .{
            .gui = .{ .x = x, .y = origin_y, .w = btn_w, .h = btn_h },
            .cli = .{ .x = x, .y = origin_y + btn_h + gap, .w = btn_w, .h = btn_h },
        };
    }
    const total = btn_w * 2 + gap;
    const x0: u32 = if (width > total) (width - total) / 2 else 16;
    return .{
        .gui = .{ .x = x0, .y = origin_y, .w = btn_w, .h = btn_h },
        .cli = .{ .x = x0 + btn_w + gap, .y = origin_y, .w = btn_w, .h = btn_h },
    };
}

fn gridCols(width: u32) u32 {
    if (width < 360) return 1;
    if (width < 720) return 2;
    return 3;
}

fn tileRect(width: u32, height: u32, index: u32) Rect {
    const cols = gridCols(width);
    const rows = (TILE_COUNT + cols - 1) / cols;
    const gap: u32 = 12;
    const margin: u32 = 16;
    const avail_w = width -| margin * 2;
    const avail_h = height -| BAR_H -| margin * 2;
    const tile_w = @max(HIT_MIN * 2, (avail_w -| (cols -| 1) * gap) / cols);
    const tile_h = @max(HIT_MIN + 8, (avail_h -| (rows -| 1) * gap) / rows);
    const grid_w = cols * tile_w + (cols -| 1) * gap;
    const grid_h = rows * tile_h + (rows -| 1) * gap;
    const origin_x: u32 = if (width > grid_w) (width - grid_w) / 2 else margin;
    const origin_y: u32 = BAR_H + if (height > grid_h + BAR_H) (height - BAR_H - grid_h) / 2 else margin;
    const col = index % cols;
    const row = index / cols;
    return .{
        .x = origin_x + col * (tile_w + gap),
        .y = origin_y + row * (tile_h + gap),
        .w = tile_w,
        .h = tile_h,
    };
}

fn infoBtnRect(width: u32) Rect {
    const s: u32 = @max(HIT_MIN -| 4, BAR_H -| 8);
    return .{ .x = width -| s -| 8, .y = (BAR_H -| s) / 2, .w = s, .h = s };
}

fn kbdBtnRect(width: u32) Rect {
    const info = infoBtnRect(width);
    const s = info.h;
    const w: u32 = @max(s + 8, 48);
    return .{ .x = info.x -| w -| 8, .y = info.y, .w = w, .h = s };
}

fn closeRect(width: u32) Rect {
    const s: u32 = @max(HIT_MIN -| 4, BAR_H -| 8);
    return .{ .x = width -| s -| 8, .y = (BAR_H -| s) / 2, .w = s, .h = s };
}

fn infoCardRect(width: u32, height: u32) Rect {
    const w: u32 = @min(width -| 24, 320);
    const h: u32 = @min(height -| 24, 200);
    return .{
        .x = if (width > w) (width - w) / 2 else 8,
        .y = if (height > h) (height - h) / 2 else 8,
        .w = w,
        .h = h,
    };
}

fn infoCloseRect(card: Rect) Rect {
    const bw: u32 = @max(HIT_MIN * 2, 96);
    const bh: u32 = HIT_MIN;
    return .{
        .x = card.x + (card.w -| bw) / 2,
        .y = card.y + card.h -| bh -| 14,
        .w = bw,
        .h = bh,
    };
}

fn hit(x: u32, y: u32, r: Rect) bool {
    return x >= r.x and x < r.x + r.w and y >= r.y and y < r.y + r.h;
}

fn fillBg(fb: []u8, stride: u32, width: u32, height: u32) void {
    fill(fb, stride, width, height, 0, 0, width, height, COLOR_BG);
    const band = height / 3;
    if (band > 0) fill(fb, stride, width, height, 0, 0, width, band, COLOR_BG2);
}

fn drawBorder(fb: []u8, stride: u32, width: u32, height: u32, r: Rect, color: u32) void {
    fill(fb, stride, width, height, r.x, r.y, r.w, 2, color);
    fill(fb, stride, width, height, r.x, r.y + r.h -| 2, r.w, 2, color);
    fill(fb, stride, width, height, r.x, r.y, 2, r.h, color);
    fill(fb, stride, width, height, r.x + r.w -| 2, r.y, 2, r.h, color);
}

fn remainingSeconds(deadline_ns: u64, now_ns: u64, armed: bool) u32 {
    if (!armed) return @intCast(BOOT_TIMEOUT_NS / 1_000_000_000);
    if (now_ns >= deadline_ns) return 0;
    const left = deadline_ns - now_ns;
    return @intCast((left + 999_999_999) / 1_000_000_000);
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

fn formatRes(buf: *[24]u8, w: u32, h: u32) []const u8 {
    var i: usize = 0;
    i = writeU32(buf, i, w);
    buf[i] = 'x';
    i += 1;
    i = writeU32(buf, i, h);
    return buf[0..i];
}

fn formatResLine(buf: *[28]u8, w: u32, h: u32) []const u8 {
    const prefix = "fb ";
    var i: usize = 0;
    for (prefix) |c| {
        buf[i] = c;
        i += 1;
    }
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
    while (i < len) : (i += 1) {
        buf[start + i] = tmp[len - 1 - i];
    }
    return start + len;
}

fn centerX(width: u32, text: []const u8) u32 {
    const tw: u32 = @intCast(text.len * font.GLYPH_W);
    if (width <= tw) return 0;
    return (width - tw) / 2;
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
