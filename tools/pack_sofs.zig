const std = @import("std");
const Io = std.Io;

const Entry = struct {
    name: [32]u8,
    offset: u32,
    size: u32,
};

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const io = init.io;

    var args = try init.minimal.args.iterateAllocator(gpa);
    defer args.deinit();
    _ = args.next();

    const out_path = args.next() orelse {
        std.debug.print("usage: pack_sofs <out.sofs> <name=path> [name=path...]\n", .{});
        return error.Usage;
    };

    var names: std.ArrayList([]const u8) = .empty;
    defer {
        for (names.items) |n| gpa.free(n);
        names.deinit(gpa);
    }
    var bodies: std.ArrayList([]u8) = .empty;
    defer {
        for (bodies.items) |b| gpa.free(b);
        bodies.deinit(gpa);
    }

    var cwd = Io.Dir.cwd();
    while (args.next()) |spec| {
        const eq = std.mem.indexOfScalar(u8, spec, '=') orelse return error.BadSpec;
        const name = spec[0..eq];
        const path = spec[eq + 1 ..];
        if (name.len == 0 or name.len >= 32) return error.BadName;
        const data = try cwd.readFileAlloc(io, path, gpa, .limited(16 * 1024 * 1024));
        try names.append(gpa, try gpa.dupe(u8, name));
        try bodies.append(gpa, data);
    }
    if (names.items.len == 0) return error.NoFiles;

    var data_size: u32 = 0;
    for (bodies.items) |b| data_size += @intCast(b.len);

    const header_size: usize = 8 + names.items.len * 40;
    const total = header_size + data_size;
    var out = try gpa.alloc(u8, total);
    defer gpa.free(out);
    @memset(out, 0);

    out[0] = 'S';
    out[1] = 'O';
    out[2] = 'F';
    out[3] = 'S';
    std.mem.writeInt(u16, out[4..6], 1, .little);
    std.mem.writeInt(u16, out[6..8], @intCast(names.items.len), .little);

    var data_off: u32 = 0;
    var ent_off: usize = 8;
    for (names.items, bodies.items) |name, body| {
        @memset(out[ent_off .. ent_off + 32], 0);
        @memcpy(out[ent_off .. ent_off + name.len], name);
        std.mem.writeInt(u32, out[ent_off + 32 ..][0..4], data_off, .little);
        std.mem.writeInt(u32, out[ent_off + 36 ..][0..4], @intCast(body.len), .little);
        ent_off += 40;
        data_off += @intCast(body.len);
    }

    var copy_off = header_size;
    for (bodies.items) |body| {
        @memcpy(out[copy_off .. copy_off + body.len], body);
        copy_off += body.len;
    }

    var file = try cwd.createFile(io, out_path, .{});
    defer file.close(io);
    try file.writeStreamingAll(io, out);
    std.debug.print("wrote {s} ({d} bytes, {d} files)\n", .{ out_path, out.len, names.items.len });
}
