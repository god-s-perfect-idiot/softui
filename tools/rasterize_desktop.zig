//! Generate SoftUI desktop SVG sources, then rasterize them to SIMG.
//! usage: rasterize_desktop <gen_desktop_svgs> <svg_to_simg>
const std = @import("std");

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

    try runTool(io, &.{gen_path});

    var cwd = std.Io.Dir.cwd();
    try cwd.createDirPath(io, "sysroot/generated");

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
        try runTool(io, &.{ svg2_path, in_path, out_path });
    }

    std.debug.print("desktop icons ready under sysroot/generated/\n", .{});
}

fn runTool(io: std.Io, argv: []const []const u8) !void {
    var child = try std.process.spawn(io, .{ .argv = argv });
    const term = try child.wait(io);
    if (!term.success()) {
        std.debug.print("command failed: {s}\n", .{argv[0]});
        return error.ToolFailed;
    }
}
