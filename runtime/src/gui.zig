//! SoftUI bootloader + hybrid shell.
//! Mobile-first UX (Palm webOS / Firefox OS / Ubuntu Touch / postmarketOS cues):
//! large targets, bottom dock, edge gestures, spacious launcher.

const font = @import("font.zig");
const input = @import("input.zig");

pub const BOOT_TIMEOUT_NS: u64 = 10_000_000_000;
/// Compact top strip (phone status panel).
pub const BAR_H: u32 = 36;
/// Bottom dock / gesture shelf — primary navigation on phones.
pub const TRAY_H: u32 = 64;
pub const HIT_MIN: u32 = 48;
/// Bottom edge strip that accepts swipe-up → Home (Ubuntu Touch / webOS).
pub const EDGE_H: u32 = 20;
const PHONE_W: u32 = 600;

pub const Stage = enum { bootloader, desktop, app, cli };
pub const Choice = enum { gui, cli };
pub const Launch = enum { shell, donut, plasma, stars, cube, fire };

const TILE_COUNT: u32 = 6;
const TILE_LABELS = [_][]const u8{ "Shell", "Donut", "Plasma", "Stars", "Cube", "Fire" };
const TILE_GLYPHS = [_]u8{ '>', 'O', '~', '*', '#', '^' };
const TILE_TINTS = [_]u32{
    0xFF3D8FD4,
    0xFFE0A05A,
    0xFF5BC4A0,
    0xFF9AA6FF,
    0xFF6EC6E0,
    0xFFE07878,
};

const COLOR_BG: u32 = 0xFF070B12;
const COLOR_BG_TOP: u32 = 0xFF152538;
const COLOR_PANEL: u32 = 0xFF15202C;
const COLOR_PANEL2: u32 = 0xFF1A2838;
const COLOR_BAR: u32 = 0xE00E1620;
const COLOR_TRAY: u32 = 0xF40A1018;
const COLOR_FG: u32 = 0xFFE8EEF5;
const COLOR_DIM: u32 = 0xFF8090A4;
const COLOR_MUTED: u32 = 0xFF5A6A7C;
const COLOR_ACCENT: u32 = 0xFF5CBCFF;
const COLOR_ACCENT_DIM: u32 = 0xFF2A5A80;
const COLOR_SELECT: u32 = 0xFF1C3A58;
const COLOR_SCRIM: u32 = 0xB0000000;
const COLOR_HAIR: u32 = 0xFF243448;
const COLOR_PILL: u32 = 0xFFD0DAE6;

const TAP_SLOP: u32 = 16;
const SWIPE_MIN: u32 = 48;

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
    now_ns: u64 = 0,
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
        return TILE_LABELS[@intFromEnum(self.app_launch)];
    }

    pub fn isPhone(self: *const Gui) bool {
        return self.layout_w > 0 and self.layout_w < PHONE_W;
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
        // Keys belong to SoftShell / demos — chrome is pointer + gestures only.
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
        const launch: Launch = @enumFromInt(@as(u8, @intCast(idx)));
        self.tile = idx;
        self.app_launch = launch;
        self.stage = .app;
        self.info_open = false;
        if (self.on_launch) |cb| cb(launch);
    }

    fn goHome(self: *Gui) void {
        if (self.stage == .app) {
            if (self.on_close_app) |cb| cb();
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

        // Edge gestures (mobile shells):
        // - swipe up from bottom shelf → Home (Ubuntu Touch / webOS)
        // - swipe down from status bar → help / quick sheet
        if (self.stage == .app or self.stage == .desktop) {
            if (self.ptr_y + EDGE_H >= self.layout_h and dy_i < 0 and ady >= SWIPE_MIN and ady > adx) {
                self.goHome();
                return;
            }
            if (self.ptr_y < BAR_H + 8 and dy_i > 0 and ady >= SWIPE_MIN and ady > adx) {
                self.info_open = true;
                return;
            }
        }

        if (adx > TAP_SLOP or ady > TAP_SLOP) return;
        self.activateAt(self.ptr_x, self.ptr_y, now_ns);
    }

    fn activateAt(self: *Gui, x: u32, y: u32, now_ns: u64) void {
        const w = self.layout_w;
        const h = self.layout_h;
        if (w == 0 or h == 0) return;

        if (self.info_open) {
            const card = infoCardRect(w, h);
            if (hit(x, y, infoCloseRect(card)) or !hit(x, y, card)) {
                self.info_open = false;
                if (self.stage == .bootloader) self.resetDeadline(now_ns);
            }
            return;
        }

        if (self.stage == .desktop or self.stage == .app or self.stage == .bootloader) {
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
        }

        if (self.stage == .app) {
            if (hit(x, y, closeRect(w))) {
                if (self.on_close_app) |cb| cb();
                return;
            }
            // Center home pill or home hit
            if (hit(x, y, homePillRect(w, h)) or hit(x, y, homeTrayRect(w, h))) {
                self.goHome();
                return;
            }
            var i: u32 = 0;
            while (i < TILE_COUNT) : (i += 1) {
                if (hit(x, y, trayAppRect(w, h, i))) {
                    if (i == @intFromEnum(self.app_launch)) return;
                    self.launchTile(i);
                    return;
                }
            }
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
            if (hit(x, y, homePillRect(w, h)) or hit(x, y, homeTrayRect(w, h))) return;
            var i: u32 = 0;
            while (i < TILE_COUNT) : (i += 1) {
                if (hit(x, y, trayAppRect(w, h, i)) or hit(x, y, iconTileRect(w, h, i))) {
                    self.launchTile(i);
                    return;
                }
            }
        }
    }

    fn drawBootloader(self: *Gui, fb: []u8, width: u32, height: u32, stride: u32, now_ns: u64) void {
        fillAtmosphere(fb, stride, width, height, now_ns);
        self.drawStatusBar(fb, width, height, stride, now_ns, "boot", false);

        const phone = width < PHONE_W;
        const title = "SoftUI";
        const subtitle = if (phone) "tap to begin" else "choose a session";
        const title_y: u32 = BAR_H + if (height > BAR_H + TRAY_H + 200) (height - BAR_H - TRAY_H) / 2 -| 90 else 24;
        drawText(fb, stride, width, centerX(width, title), title_y, title, COLOR_ACCENT);
        drawText(fb, stride, width, centerX(width, subtitle), title_y + 18, subtitle, COLOR_DIM);
        const rule_w: u32 = 40;
        const rule_x: u32 = if (width > rule_w) (width - rule_w) / 2 else 0;
        fill(fb, stride, width, height, rule_x, title_y + 12, rule_w, 2, COLOR_ACCENT_DIM);

        const layout = bootChoiceLayout(width, height);
        self.drawChoiceCard(fb, stride, width, height, layout.gui, "GUI", "launcher + dock", self.choice == .gui);
        self.drawChoiceCard(fb, stride, width, height, layout.cli, "CLI", "SoftShell", self.choice == .cli);

        var msg_buf: [24]u8 = undefined;
        const msg = formatAutoMsg(&msg_buf, remainingSeconds(self.deadline_ns, now_ns, self.armed));
        const msg_y = @max(layout.gui.y, layout.cli.y) + @max(layout.gui.h, layout.cli.h) + 18;
        if (msg_y + 12 < height -| TRAY_H) {
            drawText(fb, stride, width, centerX(width, msg), msg_y, msg, COLOR_MUTED);
        }

        self.drawDock(fb, width, height, stride, false);
        if (self.info_open) self.drawInfoSheet(fb, width, height, stride);
    }

    fn drawDesktop(self: *Gui, fb: []u8, width: u32, height: u32, stride: u32, now_ns: u64) void {
        fillAtmosphere(fb, stride, width, height, now_ns);
        self.drawStatusBar(fb, width, height, stride, now_ns, "home", false);

        const phone = width < PHONE_W;
        // Brand-first homescreen (Firefox OS / webOS launcher energy)
        const brand = "SoftUI";
        const tag = if (phone) "tap an app" else "your canvas OS";
        const brand_y: u32 = BAR_H + if (phone) @as(u32, 14) else @as(u32, 18);
        drawText(fb, stride, width, 16, brand_y, brand, COLOR_ACCENT);
        drawText(fb, stride, width, 16, brand_y + 14, tag, COLOR_MUTED);
        fill(fb, stride, width, height, 16, brand_y + 26, 36, 2, COLOR_ACCENT_DIM);

        var i: u32 = 0;
        while (i < TILE_COUNT) : (i += 1) {
            self.drawAppIcon(fb, stride, width, height, iconTileRect(width, height, i), i, i == self.tile);
        }

        self.drawDock(fb, width, height, stride, false);
        if (self.info_open) self.drawInfoSheet(fb, width, height, stride);
    }

    pub fn drawAppChrome(self: *Gui, fb: []u8, width: u32, height: u32, stride: u32, now_ns: u64) void {
        self.drawStatusBar(fb, width, height, stride, now_ns, self.appTitle(), true);
        self.drawDock(fb, width, height, stride, true);
    }

    fn drawStatusBar(_: *Gui, fb: []u8, width: u32, height: u32, stride: u32, now_ns: u64, context: []const u8, show_close: bool) void {
        fill(fb, stride, width, height, 0, 0, width, BAR_H, COLOR_BAR);
        fill(fb, stride, width, height, 0, BAR_H -| 1, width, 1, COLOR_HAIR);

        fill(fb, stride, width, height, 10, (BAR_H -| 8) / 2, 8, 8, COLOR_ACCENT);
        const phone = width < PHONE_W;
        if (phone) {
            // Phone: context as title; brand is the chip only
            drawText(fb, stride, width, 24, (BAR_H -| font.GLYPH_H) / 2, context, COLOR_FG);
        } else {
            drawText(fb, stride, width, 24, (BAR_H -| font.GLYPH_H) / 2, "SoftUI", COLOR_ACCENT);
            drawText(fb, stride, width, 80, (BAR_H -| font.GLYPH_H) / 2, context, COLOR_FG);
        }

        var clock_buf: [8]u8 = undefined;
        const clock = formatClock(&clock_buf, now_ns);
        const info = infoBtnRect(width);
        const kbd = kbdBtnRect(width);
        const close = closeRect(width);
        const right_edge: u32 = if (show_close) close.x else kbd.x;
        const clock_x = right_edge -| @as(u32, @intCast(clock.len * font.GLYPH_W)) -| 10;
        if (clock_x > 70) {
            drawText(fb, stride, width, clock_x, (BAR_H -| font.GLYPH_H) / 2, clock, COLOR_DIM);
        }

        drawChip(fb, stride, width, height, kbd, "kbd", false);
        drawChip(fb, stride, width, height, info, "?", false);
        if (show_close) drawChip(fb, stride, width, height, close, "X", true);
    }

    fn drawDock(self: *Gui, fb: []u8, width: u32, height: u32, stride: u32, in_app: bool) void {
        const ty = height -| TRAY_H;
        fill(fb, stride, width, height, 0, ty, width, TRAY_H, COLOR_TRAY);
        fill(fb, stride, width, height, 0, ty, width, 1, COLOR_HAIR);

        // Gesture hint pill (webOS / modern phone home indicator)
        const pill = homePillRect(width, height);
        fill(fb, stride, width, height, pill.x, pill.y, pill.w, pill.h, COLOR_PILL);

        // Favorite apps across the dock (Firefox OS / Ubuntu launcher)
        var i: u32 = 0;
        while (i < TILE_COUNT) : (i += 1) {
            const r = trayAppRect(width, height, i);
            const active = in_app and i == @intFromEnum(self.app_launch);
            const tint = TILE_TINTS[i];
            fill(fb, stride, width, height, r.x, r.y, r.w, r.h, if (active) COLOR_SELECT else COLOR_PANEL2);
            drawBorder(fb, stride, width, height, r, if (active) tint else COLOR_HAIR);
            var gbuf: [1]u8 = .{TILE_GLYPHS[i]};
            drawText(fb, stride, width, r.x + (r.w -| font.GLYPH_W) / 2, r.y + (r.h -| font.GLYPH_H) / 2 -| 4, gbuf[0..], if (active) tint else COLOR_FG);
            if (active) {
                fill(fb, stride, width, height, r.x + 8, r.y + r.h -| 6, r.w -| 16, 3, tint);
            }
        }

        // Tiny "swipe up" cue when in an app
        if (in_app) {
            const hint = "swipe up";
            const hx = centerX(width, hint);
            if (hx + 64 < width and ty > 10) {
                drawText(fb, stride, width, hx, ty + 2, hint, COLOR_MUTED);
            }
        }
    }

    fn drawAppIcon(_: *Gui, fb: []u8, stride: u32, width: u32, height: u32, r: Rect, idx: u32, selected: bool) void {
        const tint = TILE_TINTS[idx];
        fill(fb, stride, width, height, r.x, r.y, r.w, r.h, if (selected) COLOR_SELECT else COLOR_PANEL);
        drawBorder(fb, stride, width, height, r, if (selected) tint else COLOR_HAIR);
        if (selected) fill(fb, stride, width, height, r.x, r.y, r.w, 3, tint);

        // Large touch icon plate (phone launcher)
        const plate: u32 = @min(@min(56, r.w -| 20), r.h -| 28);
        const px = r.x + (r.w -| plate) / 2;
        const py = r.y + 12;
        fill(fb, stride, width, height, px, py, plate, plate, COLOR_PANEL2);
        drawBorder(fb, stride, width, height, .{ .x = px, .y = py, .w = plate, .h = plate }, tint);
        // Inner accent wash
        fill(fb, stride, width, height, px + 2, py + 2, plate -| 4, 4, tint);
        var gbuf: [1]u8 = .{TILE_GLYPHS[idx]};
        drawText(fb, stride, width, px + (plate -| font.GLYPH_W) / 2, py + (plate -| font.GLYPH_H) / 2, gbuf[0..], COLOR_FG);

        const label = TILE_LABELS[idx];
        const lx = r.x + (r.w -| @as(u32, @intCast(label.len * font.GLYPH_W))) / 2;
        const ly = @min(r.y + r.h -| 14, py + plate + 8);
        drawText(fb, stride, width, lx, ly, label, if (selected) COLOR_FG else COLOR_DIM);
    }

    fn drawChoiceCard(_: *Gui, fb: []u8, stride: u32, width: u32, height: u32, r: Rect, title: []const u8, sub: []const u8, selected: bool) void {
        fill(fb, stride, width, height, r.x, r.y, r.w, r.h, if (selected) COLOR_SELECT else COLOR_PANEL);
        drawBorder(fb, stride, width, height, r, if (selected) COLOR_ACCENT else COLOR_HAIR);
        if (selected) fill(fb, stride, width, height, r.x, r.y, 4, r.h, COLOR_ACCENT);
        drawText(fb, stride, width, r.x + 16, r.y + r.h / 2 -| 12, title, if (selected) COLOR_ACCENT else COLOR_FG);
        drawText(fb, stride, width, r.x + 16, r.y + r.h / 2 + 6, sub, COLOR_MUTED);
    }

    fn drawInfoSheet(self: *Gui, fb: []u8, width: u32, height: u32, stride: u32) void {
        _ = self;
        fill(fb, stride, width, height, 0, 0, width, height, COLOR_SCRIM);
        const card = infoCardRect(width, height);
        fill(fb, stride, width, height, card.x, card.y, card.w, card.h, COLOR_PANEL);
        drawBorder(fb, stride, width, height, card, COLOR_ACCENT);
        fill(fb, stride, width, height, card.x, card.y, card.w, 3, COLOR_ACCENT);

        drawText(fb, stride, width, card.x + 16, card.y + 14, "SoftUI", COLOR_ACCENT);
        var res_buf: [28]u8 = undefined;
        drawText(fb, stride, width, card.x + 16, card.y + 34, formatResLine(&res_buf, width, height), COLOR_FG);

        const lines = [_][]const u8{
            "tap app         open",
            "dock icons      switch",
            "swipe up        home",
            "swipe down      help",
            "X / home pill   close",
            "kbd             keyboard",
        };
        var i: u32 = 0;
        while (i < lines.len) : (i += 1) {
            drawText(fb, stride, width, card.x + 16, card.y + 54 + i * 15, lines[i], COLOR_DIM);
        }

        const close = infoCloseRect(card);
        fill(fb, stride, width, height, close.x, close.y, close.w, close.h, COLOR_SELECT);
        drawBorder(fb, stride, width, height, close, COLOR_ACCENT);
        drawText(fb, stride, width, close.x + (close.w -| 40) / 2, close.y + (close.h -| font.GLYPH_H) / 2, "Close", COLOR_FG);
    }
};

fn drawChip(fb: []u8, stride: u32, width: u32, height: u32, r: Rect, label: []const u8, accent: bool) void {
    fill(fb, stride, width, height, r.x, r.y, r.w, r.h, if (accent) COLOR_SELECT else COLOR_PANEL2);
    drawBorder(fb, stride, width, height, r, if (accent) COLOR_ACCENT else COLOR_HAIR);
    const tw: u32 = @intCast(label.len * font.GLYPH_W);
    drawText(fb, stride, width, r.x + (r.w -| tw) / 2, r.y + (r.h -| font.GLYPH_H) / 2, label, if (accent) COLOR_ACCENT else COLOR_FG);
}

const BootLayout = struct { gui: Rect, cli: Rect };

fn bootChoiceLayout(width: u32, height: u32) BootLayout {
    // Prefer stacked full-width cards on phones (Firefox OS style).
    const stacked = width < PHONE_W;
    const btn_w: u32 = if (stacked) @max(HIT_MIN * 4, width -| 40) else 210;
    const btn_h: u32 = @max(HIT_MIN + 12, 60);
    const gap: u32 = 14;
    const title_y: u32 = BAR_H + if (height > BAR_H + TRAY_H + 200) (height - BAR_H - TRAY_H) / 2 -| 90 else 24;
    const origin_y = title_y + 52;

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
    // Phone: 2-up launcher (Firefox OS / webOS). Wider: 3.
    if (width < PHONE_W) return 2;
    return 3;
}

fn contentTop(width: u32) u32 {
    return BAR_H + if (width < PHONE_W) @as(u32, 48) else @as(u32, 56);
}

fn iconTileRect(width: u32, height: u32, index: u32) Rect {
    const cols = gridCols(width);
    const rows = (TILE_COUNT + cols - 1) / cols;
    const gap: u32 = if (width < PHONE_W) 12 else 16;
    const margin: u32 = if (width < PHONE_W) 14 else 22;
    const top = contentTop(width);
    const avail_w = width -| margin * 2;
    const avail_h = height -| top -| TRAY_H -| margin;
    const tile_w = @max(HIT_MIN * 2, (avail_w -| (cols -| 1) * gap) / cols);
    const tile_h = @max(HIT_MIN * 2, (avail_h -| (rows -| 1) * gap) / rows);
    const grid_w = cols * tile_w + (cols -| 1) * gap;
    const grid_h = rows * tile_h + (rows -| 1) * gap;
    const origin_x: u32 = if (width > grid_w) (width - grid_w) / 2 else margin;
    const origin_y: u32 = top + if (avail_h > grid_h) (avail_h - grid_h) / 3 else 0;
    const col = index % cols;
    const row = index / cols;
    return .{
        .x = origin_x + col * (tile_w + gap),
        .y = origin_y + row * (tile_h + gap),
        .w = tile_w,
        .h = tile_h,
    };
}

fn dockIconSize(height: u32) u32 {
    _ = height;
    return @max(HIT_MIN, TRAY_H -| 18);
}

fn homePillRect(width: u32, height: u32) Rect {
    // Center home indicator — primary thumb target
    const pw: u32 = if (width < PHONE_W) 56 else 72;
    const ph: u32 = 5;
    return .{
        .x = if (width > pw) (width - pw) / 2 else 8,
        .y = height -| 12,
        .w = pw,
        .h = ph,
    };
}

fn homeTrayRect(width: u32, height: u32) Rect {
    // Larger invisible hit around the pill for thumbs
    const pill = homePillRect(width, height);
    const pad_x: u32 = 24;
    return .{
        .x = pill.x -| pad_x,
        .y = height -| TRAY_H,
        .w = pill.w + pad_x * 2,
        .h = TRAY_H,
    };
}

fn trayAppRect(width: u32, height: u32, index: u32) Rect {
    const s = dockIconSize(height);
    const gap: u32 = if (width < PHONE_W) 6 else 10;
    const total = TILE_COUNT * s + (TILE_COUNT - 1) * gap;
    // Sit above the home pill, centered
    const origin_x: u32 = if (width > total) (width - total) / 2 else 8;
    const origin_y: u32 = height -| TRAY_H + 6;
    return .{
        .x = origin_x + index * (s + gap),
        .y = origin_y,
        .w = s,
        .h = s,
    };
}

fn infoBtnRect(width: u32) Rect {
    const s: u32 = @max(HIT_MIN -| 4, BAR_H -| 8);
    return .{ .x = width -| s -| 6, .y = (BAR_H -| s) / 2, .w = s, .h = s };
}

fn kbdBtnRect(width: u32) Rect {
    const info = infoBtnRect(width);
    const s = info.h;
    const w: u32 = @max(s + 4, 44);
    return .{ .x = info.x -| w -| 6, .y = info.y, .w = w, .h = s };
}

fn closeRect(width: u32) Rect {
    const kbd = kbdBtnRect(width);
    const s = kbd.h;
    return .{ .x = kbd.x -| s -| 6, .y = kbd.y, .w = s, .h = s };
}

fn infoCardRect(width: u32, height: u32) Rect {
    const w: u32 = @min(width -| 20, 360);
    const h: u32 = @min(height -| 20, 260);
    return .{
        .x = if (width > w) (width - w) / 2 else 8,
        .y = if (height > h) (height - h) / 2 else 8,
        .w = w,
        .h = h,
    };
}

fn infoCloseRect(card: Rect) Rect {
    const bw: u32 = @max(HIT_MIN * 2, 120);
    const bh: u32 = HIT_MIN;
    return .{
        .x = card.x + (card.w -| bw) / 2,
        .y = card.y + card.h -| bh -| 12,
        .w = bw,
        .h = bh,
    };
}

fn hit(x: u32, y: u32, r: Rect) bool {
    return x >= r.x and x < r.x + r.w and y >= r.y and y < r.y + r.h;
}

fn fillAtmosphere(fb: []u8, stride: u32, width: u32, height: u32, now_ns: u64) void {
    // Two opaque bands only — keep tick under a frame budget even in Debug WASM.
    const split = height / 3;
    fill(fb, stride, width, height, 0, 0, width, split, COLOR_BG_TOP);
    fill(fb, stride, width, height, 0, split, width, height -| split, COLOR_BG);
    _ = now_ns;
}

fn drawBorder(fb: []u8, stride: u32, width: u32, height: u32, r: Rect, color: u32) void {
    fill(fb, stride, width, height, r.x, r.y, r.w, 1, color);
    fill(fb, stride, width, height, r.x, r.y + r.h -| 1, r.w, 1, color);
    fill(fb, stride, width, height, r.x, r.y, 1, r.h, color);
    fill(fb, stride, width, height, r.x + r.w -| 1, r.y, 1, r.h, color);
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

fn formatClock(buf: *[8]u8, now_ns: u64) []const u8 {
    const secs: u32 = @truncate(now_ns / 1_000_000_000);
    const hh = (9 + (secs / 3600)) % 24;
    const mm = (secs / 60) % 60;
    buf[0] = '0' + @as(u8, @intCast(hh / 10));
    buf[1] = '0' + @as(u8, @intCast(hh % 10));
    buf[2] = ':';
    buf[3] = '0' + @as(u8, @intCast(mm / 10));
    buf[4] = '0' + @as(u8, @intCast(mm % 10));
    return buf[0..5];
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
    while (i < len) : (i += 1) buf[start + i] = tmp[len - 1 - i];
    return start + len;
}

fn centerX(width: u32, text: []const u8) u32 {
    const tw: u32 = @intCast(text.len * font.GLYPH_W);
    if (width <= tw) return 0;
    return (width - tw) / 2;
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
        // Opaque fast path: tight row loop (no per-pixel helper calls).
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
