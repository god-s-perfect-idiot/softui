//! SoftUI bootloader + hybrid shell desktop.
//! Desktop: black debug bar, wallpaper, skeuomorphic app-drawer shade.

const font = @import("font.zig");
const gfx = @import("demo_gfx.zig");
const icons = @import("icons.zig");
const input = @import("input.zig");

pub const BOOT_TIMEOUT_NS: u64 = 10_000_000_000;
pub const BAR_H: u32 = 28;
pub const DOCK_H: u32 = 56;
pub const TRAY_H: u32 = DOCK_H;
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
};

const TILE_COUNT: u32 = 15;
const TILE_LABELS = [_][]const u8{
    "Shell",  "Clock",  "Cursor", "Keys",   "Image",
    "Music",  "Paint",  "UIKit",  "Colors", "Text",
    "Donut",  "Plasma", "Stars",  "Cube",   "Fire",
};
pub const ICON_NAMES = [_][]const u8{
    "shell",  "clock",  "cursor", "keys",   "image",
    "music",  "paint",  "uikit",  "colors", "text",
    "donut",  "plasma", "stars",  "cube",   "fire",
};
pub const DRAWER_ICON: usize = TILE_COUNT; // slot after last app icon

const COLOR_BG: u32 = 0xFF000000;
const COLOR_FG: u32 = 0xFFFFFFFF;
const COLOR_DIM: u32 = 0xFFAAAAAA;
const SHADE_TOP: u32 = 0xFF4A4A4A;
const SHADE_BOT: u32 = 0xFF2C2C2C;
const TILE_FACE_TOP: u32 = 0xFF5A5A5A;
const TILE_FACE_BOT: u32 = 0xFF343434;
const TILE_RIM: u32 = 0xFF1A1A1A;
const PRIMARY: u32 = 0xFF5078A0;

const TAP_SLOP: u32 = 16;
const LIST_PAD_X: u32 = 12;
const LIST_ROW_H: u32 = font.GLYPH_H + 8;

const GRID_PAD: u32 = 16;
const GRID_GAP: u32 = 12;
const CELL_W: u32 = 72;
const CELL_ICON: u32 = 48;
const CELL_TILE: u32 = 56;
const CELL_H: u32 = CELL_TILE + 4 + font.GLYPH_H;

const Rect = struct { x: u32, y: u32, w: u32, h: u32 };

pub const Gui = struct {
    stage: Stage = .bootloader,
    choice: Choice = .gui,
    tile: u32 = 0,
    drawer_open: bool = false,
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
        self.drawer_open = false;
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
        self.drawer_open = false;
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
        icons.tickPending();
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
        self.drawer_open = false;
        if (self.on_choose_gui) |cb| cb();
    }

    fn commitCli(self: *Gui) void {
        self.stage = .cli;
        if (self.on_choose_cli) |cb| cb();
    }

    fn handleDesktopKey(self: *Gui, ev: input.Event) void {
        const key = ev.key;
        if (key == input.KEY_ESCAPE) {
            self.drawer_open = false;
            return;
        }
        if (!self.drawer_open) {
            if (key == input.KEY_ENTER or key == ' ') {
                self.drawer_open = true;
                return;
            }
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
        if (key == input.KEY_LEFT) {
            if (self.tile == 0) self.tile = TILE_COUNT - 1 else self.tile -= 1;
            return;
        }
        if (key == input.KEY_RIGHT) {
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
        self.drawer_open = false;
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
        self.drawer_open = false;
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
            if (hit(x, y, drawerBtnRect(w, h))) {
                self.drawer_open = !self.drawer_open;
                return;
            }
            if (hit(x, y, trayRect(w, h))) {
                self.activateTrayAt(x, y);
                return;
            }
            if (self.drawer_open) {
                var i: u32 = 0;
                while (i < TILE_COUNT) : (i += 1) {
                    if (hit(x, y, appCellRect(w, h, i))) {
                        self.launchTile(i);
                        return;
                    }
                }
                // Tap empty shade dismisses.
                if (y >= BAR_H and y < h -| DOCK_H) {
                    self.drawer_open = false;
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
        // Wallpaper over content area; fallback gradient if image not ready.
        const content_h = height -| BAR_H;
        if (icons.wallpaperReady()) {
            icons.blitWallpaper(fb, stride, width, height, 0, BAR_H, width, content_h);
        } else {
            gfx.fillRoundVGrad(fb, stride, width, height, 0, BAR_H, width, content_h, 0, 0xFF1A2A48, 0xFF8AA0B8);
        }

        if (self.drawer_open) {
            self.drawAppDrawer(fb, width, height, stride);
        }

        self.drawTopBar(fb, width, height, stride, now_ns, "SoftUI", .desktop);
        self.drawDock(fb, width, height, stride);
    }

    fn drawAppDrawer(self: *Gui, fb: []u8, width: u32, height: u32, stride: u32) void {
        const shade_h = height -| BAR_H -| DOCK_H;
        if (shade_h == 0) return;
        gfx.fillRoundVGrad(fb, stride, width, height, 0, BAR_H, width, shade_h, 0, SHADE_TOP, SHADE_BOT);

        // Soft top bevel on the shade plate.
        gfx.hline(fb, stride, width, height, 0, BAR_H, width, 0x33FFFFFF);
        gfx.hline(fb, stride, width, height, 0, BAR_H + 1, width, 0x22000000);

        var i: u32 = 0;
        while (i < TILE_COUNT) : (i += 1) {
            const cell = appCellRect(width, height, i);
            if (cell.w == 0 or cell.h == 0) continue;
            const selected = i == self.tile;
            drawAppTile(fb, stride, width, height, cell, i, selected);
        }
    }

    fn drawAppTile(fb: []u8, stride: u32, width: u32, height: u32, cell: Rect, index: u32, selected: bool) void {
        const tile_x = cell.x + (cell.w -| CELL_TILE) / 2;
        const tile_y = cell.y;
        const face_top = if (selected) gfx.lighten(PRIMARY, 40) else TILE_FACE_TOP;
        const face_bot = if (selected) gfx.darken(PRIMARY, 20) else TILE_FACE_BOT;
        const rim = if (selected) gfx.lighten(PRIMARY, 10) else TILE_RIM;
        gfx.raisedRound(fb, stride, width, height, tile_x, tile_y, CELL_TILE, CELL_TILE, 12, face_top, face_bot, rim);

        const icon_x = tile_x + (CELL_TILE -| CELL_ICON) / 2;
        const icon_y = tile_y + (CELL_TILE -| CELL_ICON) / 2;
        if (icons.slotReady(index)) {
            icons.blit(fb, stride, width, height, icon_x, icon_y, CELL_ICON, CELL_ICON, index);
        } else {
            // Fallback glyph plate while icons decode.
            gfx.fillRound(fb, stride, width, height, icon_x + 4, icon_y + 4, CELL_ICON -| 8, CELL_ICON -| 8, 8, 0xFF2A2A2A);
            const label = TILE_LABELS[index];
            if (label.len > 0) {
                drawText(fb, stride, width, icon_x + (CELL_ICON -| font.GLYPH_W) / 2, icon_y + (CELL_ICON -| font.GLYPH_H) / 2, label[0..1], COLOR_FG);
            }
        }

        const name = TILE_LABELS[index];
        const tw = font.textWidth(name);
        const tx = cell.x + (cell.w -| tw) / 2;
        const ty = tile_y + CELL_TILE + 4;
        if (ty + font.GLYPH_H <= height -| DOCK_H) {
            drawText(fb, stride, width, tx, ty, name, if (selected) COLOR_FG else 0xFFF2F2F2);
        }
    }

    fn drawDock(self: *Gui, fb: []u8, width: u32, height: u32, stride: u32) void {
        const tr = trayRect(width, height);
        if (tr.h == 0 or tr.y >= height) return;

        // Frosted dock plate.
        gfx.fillRoundVGrad(fb, stride, width, height, tr.x, tr.y, tr.w, tr.h, 0, 0xCC3A3A3A, 0xCC222222);
        gfx.hline(fb, stride, width, height, tr.x, tr.y, tr.w, 0x44FFFFFF);

        // Running session chips on the left.
        var x: u32 = LIST_PAD_X;
        const chip_y = tr.y + (tr.h -| 28) / 2;
        var i: u32 = 0;
        while (i < MAX_SESSIONS) : (i += 1) {
            if (!self.session_used[i]) continue;
            const focused = self.stage == .app and i == self.session_focus;
            const launch_i = @intFromEnum(self.session_launches[i]);
            gfx.raisedRound(
                fb,
                stride,
                width,
                height,
                x,
                chip_y,
                28,
                28,
                6,
                if (focused) gfx.lighten(PRIMARY, 30) else 0xFF5A5A5A,
                if (focused) gfx.darken(PRIMARY, 25) else 0xFF303030,
                0xFF1A1A1A,
            );
            if (icons.slotReady(launch_i)) {
                icons.blit(fb, stride, width, height, x + 4, chip_y + 4, 20, 20, launch_i);
            }
            x += 34;
            if (x + 40 >= drawerBtnRect(width, height).x) break;
        }

        // Center skeuomorphic app-drawer affordance.
        const db = drawerBtnRect(width, height);
        const pressed = self.drawer_open;
        gfx.raisedRound(
            fb,
            stride,
            width,
            height,
            db.x,
            db.y,
            db.w,
            db.h,
            12,
            if (pressed) 0xFF3A3A3A else 0xFF6A727C,
            if (pressed) 0xFF222222 else 0xFF2E343C,
            0xFF101010,
        );
        if (icons.slotReady(DRAWER_ICON)) {
            const iw: u32 = 36;
            icons.blit(fb, stride, width, height, db.x + (db.w -| iw) / 2, db.y + (db.h -| iw) / 2, iw, iw, DRAWER_ICON);
        } else {
            drawDrawerGlyph(fb, stride, width, height, db);
        }
    }

    pub fn drawAppChrome(self: *Gui, fb: []u8, width: u32, height: u32, stride: u32, now_ns: u64) void {
        self.drawTopBar(fb, width, height, stride, now_ns, self.appTitle(), .app);
        self.drawDock(fb, width, height, stride);
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
};

fn drawDrawerGlyph(fb: []u8, stride: u32, width: u32, height: u32, db: Rect) void {
    const gap: u32 = 5;
    const dot: u32 = 6;
    const grid: u32 = dot * 3 + gap * 2;
    const ox = db.x + (db.w -| grid) / 2;
    const oy = db.y + (db.h -| grid) / 2;
    var row: u32 = 0;
    while (row < 3) : (row += 1) {
        var col: u32 = 0;
        while (col < 3) : (col += 1) {
            const x = ox + col * (dot + gap);
            const y = oy + row * (dot + gap);
            gfx.raisedRound(fb, stride, width, height, x, y, dot, dot, 2, 0xFFE8EEF4, 0xFF9AA4B0, 0xFF303038);
        }
    }
}

fn gridCols(width: u32) u32 {
    const usable = width -| GRID_PAD * 2;
    const cols = if (usable < CELL_W) 1 else (usable + GRID_GAP) / (CELL_W + GRID_GAP);
    return @max(1, @min(cols, 6));
}

fn appCellRect(width: u32, height: u32, index: u32) Rect {
    const cols = gridCols(width);
    const shade_h = height -| BAR_H -| DOCK_H;
    if (shade_h < CELL_H) return .{ .x = 0, .y = 0, .w = 0, .h = 0 };
    const col = index % cols;
    const row = index / cols;
    const total_w = cols * CELL_W + (cols -| 1) * GRID_GAP;
    const origin_x = (width -| total_w) / 2;
    const origin_y = BAR_H + GRID_PAD;
    const x = origin_x + col * (CELL_W + GRID_GAP);
    const y = origin_y + row * (CELL_H + GRID_GAP);
    if (y + CELL_H > BAR_H + shade_h) return .{ .x = 0, .y = 0, .w = 0, .h = 0 };
    return .{ .x = x, .y = y, .w = CELL_W, .h = CELL_H };
}

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

pub fn trayRect(width: u32, height: u32) Rect {
    return .{
        .x = 0,
        .y = height -| DOCK_H,
        .w = width,
        .h = DOCK_H,
    };
}

fn drawerBtnRect(width: u32, height: u32) Rect {
    const size: u32 = 44;
    return .{
        .x = (width -| size) / 2,
        .y = height -| DOCK_H + (DOCK_H -| size) / 2,
        .w = size,
        .h = size,
    };
}

fn trayHitSession(self: *const Gui, x: u32, y: u32, width: u32, height: u32) ?u32 {
    const tr = trayRect(width, height);
    if (!hit(x, y, tr)) return null;
    const db = drawerBtnRect(width, height);
    var cx: u32 = LIST_PAD_X;
    const chip_y = tr.y + (tr.h -| 28) / 2;
    var i: u32 = 0;
    while (i < MAX_SESSIONS) : (i += 1) {
        if (!self.session_used[i]) continue;
        const r = Rect{ .x = cx, .y = chip_y, .w = 28, .h = 28 };
        if (cx + 40 >= db.x) break;
        if (hit(x, y, r)) return i;
        cx += 34;
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
