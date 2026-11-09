const std = @import("std");
const builtin = @import("builtin");
const softfs = @import("softfs.zig");
const softasm_vm = @import("softasm_vm.zig");
const donut = @import("donut.zig");
const plasma = @import("plasma.zig");
const stars = @import("stars.zig");
const cube = @import("cube.zig");
const fire = @import("fire.zig");
const clock = @import("clock.zig");
const cursor = @import("cursor.zig");
const keys = @import("keys.zig");
const image = @import("image.zig");
const music = @import("music.zig");
const paint = @import("paint.zig");
const uikit = @import("uikit.zig");
const colors = @import("colors.zig");
const typo = @import("typo.zig");
const sui_app = @import("sui_app.zig");
const input = @import("input.zig");
const softshell = @import("softshell.zig");
const gui_mod = @import("gui.zig");
const osk_mod = @import("osk.zig");
const hostapi = @import("hostapi.zig");

/// Factory demo assets (fallback when SoftFS predates packing these files).
const EMBED_LOGO_SIMG = @embedFile("assets/logo.simg");
const EMBED_CALC_SUI = @embedFile("assets/calculator.sui");
const EMBED_HELLO_SUI = @embedFile("assets/hello.sui");

const MAX_WIDTH: u32 = 1920;
const MAX_HEIGHT: u32 = 1080;
const MAX_PIXELS: usize = MAX_WIDTH * MAX_HEIGHT;
const BYTES_PER_PIXEL: usize = 4;
const DISK_ARENA_SIZE: usize = 2 * 1024 * 1024;
const ALLOC_ARENA_SIZE: usize = 2 * 1024 * 1024;

/// SoftUI-owned session after bootloader: 0 = CLI, 1 = GUI.
const SESSION_CLI: u32 = 0;
const SESSION_GUI: u32 = 1;

extern fn host_log(ptr: [*]const u8, len: u32) void;
extern fn host_present() void;
extern fn host_storage_write(ptr: [*]const u8, len: u32) void;
// Additional Host ABI symbols live in hostapi.zig.

var framebuffer: [MAX_PIXELS * BYTES_PER_PIXEL]u8 align(8) = undefined;
var fb_width: u32 = 0;
var fb_height: u32 = 0;
var fb_stride: u32 = 0;
var started: bool = false;
var frame_count: u64 = 0;
var boot_ns: u64 = 0;
var session_kind: u32 = SESSION_GUI;

var disk_blob: [DISK_ARENA_SIZE]u8 align(8) = undefined;
var disk_len: usize = 0;
var disk_mounted: bool = false;

var alloc_arena: [ALLOC_ARENA_SIZE]u8 align(8) = undefined;
var alloc_used: usize = 0;

var process_arena: [softasm_vm.Vm.PROCESS_ARENA]u8 align(8) = undefined;
var vm: softasm_vm.Vm = undefined;
var vm_ready: bool = false;
var fs: softfs.Fs = undefined;
var fs_ok: bool = false;

var shell: softshell.SoftShell = .{};
var ui: gui_mod.Gui = .{};
var osk: osk_mod.Osk = .{};

fn logMsg(msg: []const u8) void {
    if (builtin.cpu.arch == .wasm32) {
        host_log(msg.ptr, @intCast(msg.len));
    }
}

fn fbBytes() []u8 {
    return framebuffer[0 .. @as(usize, fb_stride) * @as(usize, fb_height)];
}

fn putPixel(x: u32, y: u32, r: u8, g: u8, b: u8, a: u8) void {
    if (x >= fb_width or y >= fb_height) return;
    const offset: usize = @as(usize, y) * @as(usize, fb_stride) + @as(usize, x) * BYTES_PER_PIXEL;
    framebuffer[offset + 0] = r;
    framebuffer[offset + 1] = g;
    framebuffer[offset + 2] = b;
    framebuffer[offset + 3] = a;
}

fn fillRect(x0: u32, y0: u32, w: u32, h: u32, r: u8, g: u8, b: u8, a: u8) void {
    var y: u32 = y0;
    while (y < y0 + h and y < fb_height) : (y += 1) {
        var x: u32 = x0;
        while (x < x0 + w and x < fb_width) : (x += 1) {
            putPixel(x, y, r, g, b, a);
        }
    }
}

fn fillRectColor(x0: u32, y0: u32, w: u32, h: u32, color: u32) void {
    const a: u8 = @truncate(color >> 24);
    const r: u8 = @truncate(color >> 16);
    const g: u8 = @truncate(color >> 8);
    const b: u8 = @truncate(color);
    fillRect(x0, y0, w, h, r, g, b, a);
}

fn hookWrite(fd: u32, ptr: u32, len: u32, mem: []u8) void {
    if (fd != 1) return;
    if (ptr >= mem.len) return;
    const end = @min(mem.len, @as(usize, ptr) + @as(usize, len));
    logMsg(mem[ptr..end]);
}

fn hookFbFill(x: u32, y: u32, w: u32, h: u32, color: u32) void {
    fillRectColor(x, y, w, h, color);
}

fn hookFbSize() softasm_vm.FbSize {
    return .{ .w = fb_width, .h = fb_height };
}

fn hookGetFrame() u32 {
    return @truncate(frame_count);
}

fn hookFbDonut(phase_a: u32, phase_b: u32) void {
    donut.render(fbBytes(), fb_width, fb_height, fb_stride, phase_a, phase_b);
}
fn hookFbPlasma(phase: u32) void {
    plasma.render(fbBytes(), fb_width, fb_height, fb_stride, phase);
}
fn hookFbStars(phase: u32) void {
    stars.render(fbBytes(), fb_width, fb_height, fb_stride, phase);
}
fn hookFbCube(phase: u32) void {
    cube.render(fbBytes(), fb_width, fb_height, fb_stride, phase);
}
fn hookFbFire(phase: u32) void {
    fire.render(fbBytes(), fb_width, fb_height, fb_stride, phase);
}

fn shellClock(phase: u32, now_ns: u64) void {
    clock.render(fbBytes(), fb_width, fb_height, fb_stride, phase, now_ns, boot_ns);
}
fn shellCursor(phase: u32) void {
    cursor.render(fbBytes(), fb_width, fb_height, fb_stride, phase);
}
fn shellKeys(phase: u32) void {
    keys.render(fbBytes(), fb_width, fb_height, fb_stride, phase);
}
fn shellImage(phase: u32) void {
    image.render(fbBytes(), fb_width, fb_height, fb_stride, phase);
}
fn shellMusic(phase: u32) void {
    music.render(fbBytes(), fb_width, fb_height, fb_stride, phase);
}
fn shellPaint(phase: u32) void {
    paint.render(fbBytes(), fb_width, fb_height, fb_stride, phase);
}
fn shellUikit(phase: u32) void {
    uikit.render(fbBytes(), fb_width, fb_height, fb_stride, phase);
}
fn shellColors(phase: u32) void {
    colors.render(fbBytes(), fb_width, fb_height, fb_stride, phase);
}
fn shellText(phase: u32) void {
    typo.render(fbBytes(), fb_width, fb_height, fb_stride, phase);
}
fn shellSui(phase: u32) void {
    sui_app.render(fbBytes(), fb_width, fb_height, fb_stride, phase);
}
fn shellDonut(phase_a: u32, phase_b: u32) void {
    hookFbDonut(phase_a, phase_b);
}
fn shellPlasma(phase: u32) void {
    hookFbPlasma(phase);
}
fn shellStars(phase: u32) void {
    hookFbStars(phase);
}
fn shellCube(phase: u32) void {
    hookFbCube(phase);
}
fn shellFire(phase: u32) void {
    hookFbFire(phase);
}
fn shellDemoKey(mode: softshell.Mode, key: u32, mods: u32) void {
    switch (mode) {
        .keys => keys.pushKey(key, mods),
        .music => music.onKey(key),
        .paint => paint.onKey(key),
        .uikit => uikit.onKey(key),
        .colors => colors.onKey(key),
        else => {},
    }
}

fn shellFbFill(x: u32, y: u32, w: u32, h: u32, color: u32) void {
    fillRectColor(x, y, w, h, color);
}

fn shellRefreshKinfo(k: *softshell.KernelInfo) void {
    k.frame = @truncate(frame_count);
    k.boot_ns = boot_ns;
    k.fb_w = fb_width;
    k.fb_h = fb_height;
    k.fb_stride = fb_stride;
    k.boot_mode = session_kind;
    k.alloc_used = @intCast(alloc_used);
    k.alloc_cap = ALLOC_ARENA_SIZE;
    k.disk_len = @intCast(disk_len);
    k.disk_cap = DISK_ARENA_SIZE;
    k.process_arena = softasm_vm.Vm.PROCESS_ARENA;
}

fn shellReboot() void {
    input.reset();
    shell.start(fb_width, fb_height, if (fs_ok) &fs else null);
    shell.gui_hosted = session_kind == SESSION_GUI;
}

fn persistFs() void {
    if (!fs_ok) return;
    const n = fs.pack(disk_blob[0..]) catch {
        logMsg("softui: softfs pack failed");
        return;
    };
    disk_len = n;
    disk_mounted = true;
    if (builtin.cpu.arch == .wasm32) {
        host_storage_write(&disk_blob, @intCast(n));
    }
    logMsg("softui: softfs synced");
}

fn shellFsSync() void {
    persistFs();
}

fn shellRunSox(name: []const u8) void {
    if (!fs_ok) {
        shell.cons.write("SoftFS not mounted\n");
        return;
    }
    const sox = fs.find(name) orelse {
        shell.cons.write("not found: ");
        shell.cons.write(name);
        shell.cons.write("\n");
        return;
    };
    const hooks = softasm_vm.KernelHooks{
        .write = hookWrite,
        .fb_fill = hookFbFill,
        .fb_size = hookFbSize,
        .get_frame = hookGetFrame,
        .fb_donut = hookFbDonut,
        .fb_plasma = hookFbPlasma,
        .fb_stars = hookFbStars,
        .fb_cube = hookFbCube,
        .fb_fire = hookFbFire,
    };
    vm = softasm_vm.Vm.load(sox, process_arena[0..], hooks) catch {
        shell.cons.write("failed to load .sox\n");
        return;
    };
    vm_ready = true;
    vm.runBudget(200_000);
    vm_ready = false;
    shell.cons.write("ran ");
    shell.cons.write(name);
    shell.cons.write("\n");
}

fn mountFsIfNeeded() void {
    if (!disk_mounted or fs_ok) return;
    fs.mount(disk_blob[0..disk_len]) catch {
        logMsg("softui: softfs mount failed");
        return;
    };
    fs_ok = true;
    logMsg("softui: softfs ready");
}

fn wireShellCallbacks() void {
    shell.on_clock = shellClock;
    shell.on_cursor = shellCursor;
    shell.on_keys = shellKeys;
    shell.on_image = shellImage;
    shell.on_music = shellMusic;
    shell.on_paint = shellPaint;
    shell.on_uikit = shellUikit;
    shell.on_colors = shellColors;
    shell.on_text = shellText;
    shell.on_sui = shellSui;
    shell.on_donut = shellDonut;
    shell.on_plasma = shellPlasma;
    shell.on_stars = shellStars;
    shell.on_cube = shellCube;
    shell.on_fire = shellFire;
    shell.on_demo_key = shellDemoKey;
    shell.on_run_sox = shellRunSox;
    shell.on_fb_fill = shellFbFill;
    shell.on_reboot_shell = shellReboot;
    shell.on_refresh_kinfo = shellRefreshKinfo;
    shell.on_fs_sync = shellFsSync;
    shell.on_return_desktop = returnToDesktop;
}

fn returnToDesktop() void {
    // Home: keep sessions; stop audio spill from background music focus loss.
    hostapi.audioStop();
    ui.returnToDesktop();
    shell.content_y = 0;
    shell.enterMode(.shell);
    shell.ready = true;
    logMsg("softui: desktop (home)");
}

fn closeAppSession() void {
    hostapi.audioStop();
    // Gui.closeFocusedApp already ran session bookkeeping before this callback
    // when wired from activateAt — but on_close_app is invoked FROM gui after
    // removing the session. If gui switched to another session it will call
    // on_launch again. If none remain, stage is desktop.
    if (ui.stage == .desktop) {
        shell.content_y = 0;
        shell.enterMode(.shell);
        logMsg("softui: session closed -> desktop");
    }
}

fn goHome() void {
    returnToDesktop();
}

fn toggleOsk() void {
    if (osk.visible) {
        osk.reset();
    } else {
        osk.visible = true;
    }
}

fn enterCliSession() void {
    session_kind = SESSION_CLI;
    wireShellCallbacks();
    shell.gui_hosted = false;
    shell.content_y = 0;
    input.reset();
    shell.start(fb_width, fb_height, if (fs_ok) &fs else null);
    logMsg("softui: SoftShell CLI session");
}

fn enterGuiSession() void {
    session_kind = SESSION_GUI;
    wireShellCallbacks();
    shell.gui_hosted = true;
    shell.ready = false;
    shell.content_y = 0;
    logMsg("softui: GUI desktop session");
}

fn launchFromDesktop(launch: gui_mod.Launch) void {
    wireShellCallbacks();
    shell.gui_hosted = true;
    const fs_ptr: ?*softfs.Fs = if (fs_ok) &fs else null;
    switch (launch) {
        .shell => {
            input.reset();
            shell.content_y = gui_mod.BAR_H;
            shell.start(fb_width, fb_height, fs_ptr);
            shell.gui_hosted = true;
            logMsg("softui: launch SoftShell");
        },
        .clock => launchCapDemo(fs_ptr, .clock),
        .cursor => launchCapDemo(fs_ptr, .cursor),
        .keys => {
            keys.reset();
            launchCapDemo(fs_ptr, .keys);
        },
        .image => launchCapDemo(fs_ptr, .image),
        .music => {
            music.reset();
            launchCapDemo(fs_ptr, .music);
        },
        .paint => {
            paint.reset();
            launchCapDemo(fs_ptr, .paint);
        },
        .uikit => {
            uikit.reset();
            launchCapDemo(fs_ptr, .uikit);
        },
        .colors => {
            colors.reset();
            launchCapDemo(fs_ptr, .colors);
        },
        .text => launchCapDemo(fs_ptr, .text),
        .donut => launchCapDemo(fs_ptr, .donut),
        .plasma => launchCapDemo(fs_ptr, .plasma),
        .stars => launchCapDemo(fs_ptr, .stars),
        .cube => launchCapDemo(fs_ptr, .cube),
        .fire => launchCapDemo(fs_ptr, .fire),
        .calc => launchSuiApp(fs_ptr, "calculator.sui"),
        .hello => launchSuiApp(fs_ptr, "hello.sui"),
    }
}

fn launchCapDemo(fs_ptr: ?*softfs.Fs, mode: softshell.Mode) void {
    ensureShellForDemo(fs_ptr);
    if (mode == .image) loadImageAsset();
    shell.enterMode(mode);
    logMsg("softui: launch demo");
}

fn launchSuiApp(fs_ptr: ?*softfs.Fs, path: []const u8) void {
    ensureShellForDemo(fs_ptr);
    sui_app.reset();
    var loaded = false;
    if (fs_ok) {
        if (fs.find(path)) |data| {
            sui_app.loadSource(path, data);
            loaded = true;
        }
    }
    if (!loaded) {
        if (std.mem.eql(u8, path, "calculator.sui")) {
            sui_app.loadSource(path, EMBED_CALC_SUI);
            loaded = true;
        } else if (std.mem.eql(u8, path, "hello.sui")) {
            sui_app.loadSource(path, EMBED_HELLO_SUI);
            loaded = true;
        }
    }
    if (!loaded) logMsg("softui: missing .sui");
    shell.enterMode(.sui);
    logMsg("softui: launch sui");
}

fn loadImageAsset() void {
    image.reset();
    if (fs_ok) {
        if (fs.find("logo.simg")) |data| {
            image.loadBytes("logo.simg", data);
            return;
        }
        if (fs.find("sample.png")) |data| {
            image.loadBytes("sample.png", data);
            return;
        }
    }
    image.loadBytes("logo.simg", EMBED_LOGO_SIMG);
}

fn ensureShellForDemo(fs_ptr: ?*softfs.Fs) void {
    shell.content_y = 0;
    if (!shell.ready) {
        input.reset();
        shell.start(fb_width, fb_height, fs_ptr);
    }
    shell.gui_hosted = true;
}

fn startBootloader() void {
    session_kind = SESSION_GUI;
    ui.on_choose_cli = enterCliSession;
    ui.on_choose_gui = enterGuiSession;
    ui.on_launch = launchFromDesktop;
    ui.on_close_app = closeAppSession;
    ui.on_home = goHome;
    ui.on_toggle_osk = toggleOsk;
    ui.start();
    logMsg("softui: bootloader");
}

fn applyFbSize(width: u32, height: u32) i32 {
    if (width == 0 or height == 0) return -1;
    if (width > MAX_WIDTH or height > MAX_HEIGHT) return -2;
    fb_width = width;
    fb_height = height;
    fb_stride = width * @as(u32, BYTES_PER_PIXEL);
    @memset(framebuffer[0 .. @as(usize, fb_stride) * @as(usize, fb_height)], 0);
    if (shell.ready) {
        shell.resizeFb(fb_width, fb_height);
    }
    return 0;
}

export fn softui_push_key(key: u32, mods: u32) void {
    if (osk.handleHotkey(key, mods)) return;
    input.push(key, mods);
}

/// Pointer into SoftUI FB coords. kind: 0=move 1=down 2=up. buttons bit0=primary.
export fn softui_push_pointer(x: u32, y: u32, buttons: u32, kind: u32) void {
    if (osk.handlePointer(x, y, buttons, kind, fb_width, fb_height)) return;
    input.pushPointer(x, y, buttons, kind);
}

export fn softui_start(width: u32, height: u32) i32 {
    const rc = applyFbSize(width, height);
    if (rc != 0) return rc;

    frame_count = 0;
    boot_ns = 0;
    started = true;
    vm_ready = false;
    fs_ok = false;
    alloc_used = 0;
    shell.ready = false;
    shell.content_y = 0;
    osk.reset();

    logMsg("softui: kernel start");
    mountFsIfNeeded();
    startBootloader();
    return 0;
}

/// Change framebuffer geometry to match host viewport. Keeps session/stage.
export fn softui_resize(width: u32, height: u32) i32 {
    if (!started) return -1;
    if (width == fb_width and height == fb_height) return 0;
    const rc = applyFbSize(width, height);
    if (rc != 0) return rc;
    logMsg("softui: fb resize");
    return 0;
}

export fn softui_tick(now_ns: u64) i32 {
    if (!started) return -1;
    if (boot_ns == 0) boot_ns = now_ns;
    frame_count += 1;

    mountFsIfNeeded();
    if (fs_ok and shell.ready and shell.fs == null) {
        shell.fs = &fs;
    }

    if (session_kind == SESSION_CLI) {
        shell.tick(@truncate(frame_count), now_ns);
        shell.draw(fbBytes(), fb_width, fb_height, fb_stride);
    } else {
        ui.tick(now_ns, fb_width, fb_height);
        if (ui.stage == .app) {
            shell.tick(@truncate(frame_count), now_ns);
        } else if (ui.stage == .cli) {
            shell.tick(@truncate(frame_count), now_ns);
        }
        switch (ui.stage) {
            .bootloader, .desktop => {
                ui.draw(fbBytes(), fb_width, fb_height, fb_stride, now_ns);
            },
            .app => {
                shell.draw(fbBytes(), fb_width, fb_height, fb_stride);
                ui.drawAppChrome(fbBytes(), fb_width, fb_height, fb_stride, now_ns);
            },
            .cli => {
                shell.draw(fbBytes(), fb_width, fb_height, fb_stride);
            },
        }
    }

    // Overlay last so the keyboard sits above bootloader / desktop / shell.
    osk.draw(fbBytes(), fb_width, fb_height, fb_stride);

    if (builtin.cpu.arch == .wasm32) {
        host_present();
    }
    return 0;
}

export fn softui_fb_ptr() u32 {
    return @intCast(@intFromPtr(&framebuffer));
}

export fn softui_fb_width() u32 {
    return fb_width;
}

export fn softui_fb_height() u32 {
    return fb_height;
}

export fn softui_fb_stride() u32 {
    return fb_stride;
}

export fn softui_alloc(size: u32) u32 {
    const align_size = (size + 7) & ~@as(u32, 7);
    if (alloc_used + align_size > alloc_arena.len) return 0;
    const ptr = @intFromPtr(&alloc_arena) + alloc_used;
    alloc_used += align_size;
    return @intCast(ptr);
}

export fn softui_mount_disk(ptr: u32, len: u32) i32 {
    if (len == 0 or len > disk_blob.len) return -1;
    const src: [*]const u8 = @ptrFromInt(ptr);
    @memcpy(disk_blob[0..len], src[0..len]);
    disk_len = len;
    disk_mounted = true;
    fs_ok = false;
    vm_ready = false;
    logMsg("softui: disk mounted");
    if (started) mountFsIfNeeded();
    return 0;
}

/// Pack SoftFS and push to host storage. Returns 0 on success.
export fn softui_persist() i32 {
    if (!fs_ok) return -1;
    persistFs();
    return 0;
}

pub fn panic(msg: []const u8, _: ?*std.builtin.StackTrace, _: ?usize) noreturn {
    logMsg(msg);
    while (true) {}
}
