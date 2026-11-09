//! SoftUI → Host ABI wrappers (wasm32 only; stubs elsewhere).

const builtin = @import("builtin");

pub const WallTime = struct {
    ms: u64,
    tz_min: i32,
};

pub fn wallTime() WallTime {
    if (builtin.cpu.arch == .wasm32) {
        return .{
            .ms = host_time_wall_ms(),
            .tz_min = host_time_tz_min(),
        };
    }
    return .{ .ms = 0, .tz_min = 0 };
}

pub fn audioQueue(pcm: []const u8, sample_rate: u32, channels: u32) i32 {
    if (builtin.cpu.arch != .wasm32) return -1;
    if (pcm.len == 0) return -1;
    return host_audio_queue(pcm.ptr, @intCast(pcm.len), sample_rate, channels);
}

pub fn audioStop() void {
    if (builtin.cpu.arch == .wasm32) host_audio_stop();
}

/// Decode image bytes into RGBA8 dst. Returns true on success.
pub fn imageDecode(src: []const u8, dst: []u8, out_w: *u32, out_h: *u32) bool {
    if (builtin.cpu.arch != .wasm32) return false;
    if (src.len == 0 or dst.len == 0) return false;
    const rc = host_image_decode(src.ptr, @intCast(src.len), dst.ptr, @intCast(dst.len), out_w, out_h);
    return rc >= 0;
}

/// Paint suigui source into SoftUI FB. ev: 0=none 1=move 2=down/click.
pub fn suiPaint(src: []const u8, fb: []u8, w: u32, h: u32, stride: u32, ev: u32, x: u32, y: u32) i32 {
    if (builtin.cpu.arch != .wasm32) return -1;
    if (src.len == 0) return -1;
    return host_sui_paint(src.ptr, @intCast(src.len), fb.ptr, w, h, stride, ev, x, y);
}

extern fn host_time_wall_ms() u64;
extern fn host_time_tz_min() i32;
extern fn host_audio_queue(ptr: [*]const u8, len: u32, sample_rate: u32, channels: u32) i32;
extern fn host_audio_stop() void;
extern fn host_image_decode(
    src: [*]const u8,
    src_len: u32,
    dst: [*]u8,
    dst_cap: u32,
    out_w: *u32,
    out_h: *u32,
) i32;
extern fn host_sui_paint(
    src: [*]const u8,
    src_len: u32,
    fb: [*]u8,
    w: u32,
    h: u32,
    stride: u32,
    ev: u32,
    x: u32,
    y: u32,
) i32;
