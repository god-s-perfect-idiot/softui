//! Wall clock + uptime demo (Host ABI wall time).

const gfx = @import("demo_gfx.zig");
const hostapi = @import("hostapi.zig");

pub fn render(fb: []u8, width: u32, height: u32, stride: u32, phase: u32, now_ns: u64, boot_ns: u64) void {
    _ = phase;
    gfx.clear(fb, stride, width, height, gfx.COLOR_BG);

    const wall = hostapi.wallTime();
    const local_ms: i64 = @as(i64, @intCast(wall.ms)) + @as(i64, wall.tz_min) * 60_000;
    const day_ms: i64 = @mod(local_ms, 86_400_000);
    const day_secs: u32 = @intCast(@divFloor(day_ms, 1000));
    const hh = (day_secs / 3600) % 24;
    const mm = (day_secs / 60) % 60;
    const ss = day_secs % 60;

    var wall_buf: [12]u8 = undefined;
    wall_buf[0] = '0' + @as(u8, @intCast(hh / 10));
    wall_buf[1] = '0' + @as(u8, @intCast(hh % 10));
    wall_buf[2] = ':';
    wall_buf[3] = '0' + @as(u8, @intCast(mm / 10));
    wall_buf[4] = '0' + @as(u8, @intCast(mm % 10));
    wall_buf[5] = ':';
    wall_buf[6] = '0' + @as(u8, @intCast(ss / 10));
    wall_buf[7] = '0' + @as(u8, @intCast(ss % 10));
    const wall_hms = wall_buf[0..8];

    gfx.drawText(fb, stride, width, height, centerX(width, "WALL CLOCK"), 36, "WALL CLOCK", gfx.COLOR_DIM);
    gfx.drawText(fb, stride, width, height, centerX(width, wall_hms) + 1, 81, wall_hms, gfx.COLOR_BORDER);
    gfx.drawText(fb, stride, width, height, centerX(width, wall_hms), 80, wall_hms, gfx.COLOR_FG);

    var tz_buf: [24]u8 = undefined;
    var n: usize = 0;
    const tz_pref = "tz ";
    for (tz_pref) |c| {
        tz_buf[n] = c;
        n += 1;
    }
    if (wall.tz_min < 0) {
        tz_buf[n] = '-';
        n += 1;
    } else {
        tz_buf[n] = '+';
        n += 1;
    }
    const taz: u32 = @intCast(if (wall.tz_min < 0) -wall.tz_min else wall.tz_min);
    n = gfx.writeU32(&tz_buf, n, taz / 60);
    tz_buf[n] = ':';
    n += 1;
    const tzm = taz % 60;
    tz_buf[n] = '0' + @as(u8, @intCast(tzm / 10));
    n += 1;
    tz_buf[n] = '0' + @as(u8, @intCast(tzm % 10));
    n += 1;
    gfx.drawText(fb, stride, width, height, centerX(width, tz_buf[0..n]), 100, tz_buf[0..n], gfx.COLOR_ACCENT);

    const elapsed_ns: u64 = if (now_ns >= boot_ns) now_ns - boot_ns else 0;
    const up_secs: u32 = @truncate(elapsed_ns / 1_000_000_000);
    var up_buf: [12]u8 = undefined;
    const up_hms = gfx.formatHMS(&up_buf, up_secs);
    gfx.drawText(fb, stride, width, height, 12, 140, "uptime", gfx.COLOR_DIM);
    gfx.drawText(fb, stride, width, height, 12, 156, up_hms, gfx.COLOR_FG);
    gfx.drawText(fb, stride, width, height, 12, 180, "source: host_time_wall_ms", gfx.COLOR_DIM);
    gfx.drawText(fb, stride, width, height, 12, 196, "Esc / exit to leave", gfx.COLOR_DIM);

    const bar_w = if (width > 24) width - 24 else width;
    const fill_w = (bar_w * ss) / 60;
    gfx.rect(fb, stride, width, height, 12, height -| 28, bar_w, 10, gfx.COLOR_BORDER);
    gfx.fill(fb, stride, width, height, 12, height -| 28, fill_w, 10, gfx.COLOR_ACCENT);
}

fn centerX(width: u32, text: []const u8) u32 {
    const tw = @import("font.zig").textWidth(text);
    if (tw >= width) return 0;
    return (width - tw) / 2;
}
