//! Generate SoftUI desktop SVG sources, then rasterize them to SIMG.
//! usage: rasterize_desktop
const std = @import("std");

// Re-use the SVG emitter by shelling out would be heavy; instead invoke the
// same write routines via a child process of gen_desktop_svgs + svg_to_simg.
// This driver assumes those tools are passed as argv[1]=gen, argv[2]=svg2simg.

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const io = init.io;

    var args = try init.minimal.args.iterateAllocator(gpa);
    defer args.deinit();
    _ = args.next();

    const gen_path = args.next() orelse {
        std.debug.print("usage: rasterize_desktop <gen_desktop_svgs> <svg_to_simg>\n", .{});
        return error.Usage;
    };
    const svg2_path = args.next() orelse return error.Usage;

    // 1) Emit SVG sources
    {
        var child = std.process.Child.init(&.{ gen_path }, gpa);
        child.stdout_behavior = .Inherit;
        child.stderr_behavior = .Inherit;
        const term = try child.spawnAndWait();
        switch (term) {
            .Exited => |code| if (code != 0) return error.GenFailed,
            else => return error.GenFailed,
        }
    }

    var cwd = std.Io.Dir.cwd();
    try cwd.makePath("sysroot/generated");

    const icon_names = [_][]const u8{
        "shell",  "clock",  "cursor", "keys",   "image",
        "music",  "paint",  "uikit",  "colors", "text",
        "donut",  "plasma", "stars",  "cube",   "fire",
        "calc",   "hello",  "drawer",
    };

    for (icon_names) |name| {
        var in_buf: [64]u8 = undefined;
        var out_buf: [80]u8 = undefined;
        const in_path = try std.fmt.bufPrint(&in_buf, "sysroot/icons/{s}.svg", .{name});
        const out_path = try std.fmt.bufPrint(&out_buf, "sysroot/generated/icon_{s}.simg", .{name});
        var child = std.process.Child.init(&.{ svg2_path, in_path, out_path }, gpa);
        child.stdout_behavior = .Inherit;
        child.stderr_behavior = .Inherit;
        const term = try child.spawnAndWait();
        switch (term) {
            .Exited => |code| if (code != 0) {
                std.debug.print("failed: {s}\n", .{name});
                return error.RasterFailed;
            },
            else => return error.RasterFailed,
        }
    }

    {
        var child = std.process.Child.init(&.{
            svg2_path,
            "sysroot/wallpaper.svg",
            "sysroot/generated/wallpaper.simg",
        }, gpa);
        child.stdout_behavior = .Inherit;
        child.stderr_behavior = .Inherit;
        const term = try child.spawnAndWait();
        switch (term) {
            .Exited => |code| if (code != 0) return error.RasterFailed,
            else => return error.RasterFailed,
        }
    }

    _ = io;
    std.debug.print("desktop assets ready under sysroot/generated/\n", .{});
}
