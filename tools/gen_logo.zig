//! Generate sysroot/logo.simg — SoftUI raw image (RGBA8).
//! Layout: magic "SIMG" + u32le w + u32le h + w*h*4 RGBA pixels.
const std = @import("std");

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const w: u32 = 96;
    const h: u32 = 64;
    const pixels = w * h * 4;
    var out = try gpa.alloc(u8, 12 + pixels);
    defer gpa.free(out);

    @memcpy(out[0..4], "SIMG");
    std.mem.writeInt(u32, out[4..8], w, .little);
    std.mem.writeInt(u32, out[8..12], h, .little);

    var y: u32 = 0;
    while (y < h) : (y += 1) {
        var x: u32 = 0;
        while (x < w) : (x += 1) {
            const t = @as(f32, @floatFromInt(x)) / @as(f32, @floatFromInt(w - 1));
            var r: u8 = @intFromFloat(20.0 + t * 60.0);
            var g: u8 = @intFromFloat(40.0 + (1.0 - t) * 100.0);
            var b: u8 = @intFromFloat(80.0 + t * 140.0);
            if (y >= 28 and y <= 36) {
                r = 80;
                g = 180;
                b = 255;
            }
            // Soft brand mark: soft rectangle outline
            if ((x == 8 or x == w - 9) and y >= 12 and y <= h - 13) {
                r = 255;
                g = 255;
                b = 255;
            }
            if ((y == 12 or y == h - 13) and x >= 8 and x <= w - 9) {
                r = 255;
                g = 255;
                b = 255;
            }
            const o: usize = 12 + (@as(usize, y) * @as(usize, w) + @as(usize, x)) * 4;
            out[o + 0] = r;
            out[o + 1] = g;
            out[o + 2] = b;
            out[o + 3] = 255;
        }
    }

    try std.fs.cwd().makePath("sysroot");
    try std.fs.cwd().writeFile(.{ .sub_path = "sysroot/logo.simg", .data = out });
    std.debug.print("wrote sysroot/logo.simg ({d} bytes)\n", .{out.len});
}
