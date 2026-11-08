const std = @import("std");
const builtin = @import("builtin");
const softfs = @import("softfs.zig");
const softasm_vm = @import("softasm_vm.zig");
const donut = @import("donut.zig");
const plasma = @import("plasma.zig");
const stars = @import("stars.zig");
const cube = @import("cube.zig");
const fire = @import("fire.zig");
const input = @import("input.zig");
const softshell = @import("softshell.zig");

const MAX_WIDTH: u32 = 1920;
const MAX_HEIGHT: u32 = 1080;
const MAX_PIXELS: usize = MAX_WIDTH * MAX_HEIGHT;
const BYTES_PER_PIXEL: usize = 4;
const DISK_ARENA_SIZE: usize = 2 * 1024 * 1024;
const ALLOC_ARENA_SIZE: usize = 2 * 1024 * 1024;

const BOOT_CLI: u32 = 0;
const BOOT_GUI: u32 = 1;

extern fn host_log(ptr: [*]const u8, len: u32) void;
extern fn host_present() void;

var framebuffer: [MAX_PIXELS * BYTES_PER_PIXEL]u8 align(8) = undefined;
var fb_width: u32 = 0;
var fb_height: u32 = 0;
var fb_stride: u32 = 0;
var started: bool = false;
var frame_count: u64 = 0;
var boot_ns: u64 = 0;
var boot_mode: u32 = BOOT_CLI;

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

fn shellFbFill(x: u32, y: u32, w: u32, h: u32, color: u32) void {
    fillRectColor(x, y, w, h, color);
}

fn shellRefreshKinfo(k: *softshell.KernelInfo) void {
    k.frame = @truncate(frame_count);
    k.boot_ns = boot_ns;
    k.fb_w = fb_width;
    k.fb_h = fb_height;
    k.fb_stride = fb_stride;
    k.boot_mode = boot_mode;
    k.alloc_used = @intCast(alloc_used);
    k.alloc_cap = ALLOC_ARENA_SIZE;
    k.disk_len = @intCast(disk_len);
    k.disk_cap = DISK_ARENA_SIZE;
    k.process_arena = softasm_vm.Vm.PROCESS_ARENA;
}

fn shellReboot() void {
    input.reset();
    shell.start(fb_width, fb_height, if (fs_ok) &fs else null);
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

fn startCli() void {
    input.reset();
    shell.on_donut = shellDonut;
    shell.on_plasma = shellPlasma;
    shell.on_stars = shellStars;
    shell.on_cube = shellCube;
    shell.on_fire = shellFire;
    shell.on_run_sox = shellRunSox;
    shell.on_fb_fill = shellFbFill;
    shell.on_reboot_shell = shellReboot;
    shell.on_refresh_kinfo = shellRefreshKinfo;
    shell.start(fb_width, fb_height, if (fs_ok) &fs else null);
    logMsg("softui: SoftShell CLI boot");
}

export fn softui_set_boot_mode(mode: u32) void {
    boot_mode = mode;
}

export fn softui_push_key(key: u32, mods: u32) void {
    input.push(key, mods);
}

export fn softui_start(width: u32, height: u32) i32 {
    if (width == 0 or height == 0) return -1;
    if (width > MAX_WIDTH or height > MAX_HEIGHT) return -2;

    fb_width = width;
    fb_height = height;
    fb_stride = width * @as(u32, BYTES_PER_PIXEL);
    frame_count = 0;
    boot_ns = 0;
    started = true;
    vm_ready = false;
    fs_ok = false;
    alloc_used = 0;

    @memset(framebuffer[0 .. @as(usize, fb_stride) * @as(usize, fb_height)], 0);
    logMsg("softui: kernel start");
    mountFsIfNeeded();

    if (boot_mode == BOOT_GUI) {
        logMsg("softui: gui boot not implemented; using CLI");
    }
    startCli();
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

    shell.tick(@truncate(frame_count));
    shell.draw(fbBytes(), fb_width, fb_height, fb_stride);

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

pub fn panic(msg: []const u8, _: ?*std.builtin.StackTrace, _: ?usize) noreturn {
    logMsg(msg);
    while (true) {}
}
