const std = @import("std");
const Io = std.Io;

const PORT: u16 = 8080;
const DEFAULT_ROOT = "bootstrap/web";

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const io = init.io;

    var args = try init.minimal.args.iterateAllocator(gpa);
    defer args.deinit();
    _ = args.next(); // argv0
    const root_path = args.next() orelse DEFAULT_ROOT;

    var root_dir = try Io.Dir.cwd().openDir(io, root_path, .{});
    defer root_dir.close(io);

    const address = try Io.net.IpAddress.parse("127.0.0.1", PORT);
    var server = try address.listen(io, .{
        .reuse_address = true,
    });
    defer server.deinit(io);

    std.debug.print("SoftUI serving {s} at http://127.0.0.1:{d}/\n", .{ root_path, PORT });

    while (true) {
        const stream = server.accept(io) catch |err| {
            std.debug.print("accept error: {s}\n", .{@errorName(err)});
            continue;
        };
        handleConnection(gpa, io, stream, root_dir) catch |err| {
            std.debug.print("request error: {s}\n", .{@errorName(err)});
        };
        stream.close(io);
    }
}

fn handleConnection(gpa: std.mem.Allocator, io: Io, stream: Io.net.Stream, root_dir: Io.Dir) !void {
    var recv_buf: [8192]u8 = undefined;
    var chunks: [1][]u8 = .{recv_buf[0..]};
    const result = try stream.readWithControl(io, &chunks, &.{});
    if (result.data_len == 0) return;

    const request = recv_buf[0..result.data_len];
    const path = try parsePath(request);

    const rel = if (std.mem.eql(u8, path, "/"))
        "index.html"
    else if (path.len > 0 and path[0] == '/')
        path[1..]
    else
        path;

    if (std.mem.indexOfScalar(u8, rel, '\\') != null or std.mem.indexOf(u8, rel, "..") != null) {
        try writeResponse(io, stream, 400, "text/plain", "bad request");
        return;
    }

    const body = root_dir.readFileAlloc(io, rel, gpa, .limited(64 * 1024 * 1024)) catch {
        try writeResponse(io, stream, 404, "text/plain", "not found");
        return;
    };
    defer gpa.free(body);

    try writeResponse(io, stream, 200, contentType(rel), body);
}

fn parsePath(request: []const u8) ![]const u8 {
    const line_end = std.mem.indexOf(u8, request, "\r\n") orelse return error.BadRequest;
    const line = request[0..line_end];
    var it = std.mem.tokenizeScalar(u8, line, ' ');
    const method = it.next() orelse return error.BadRequest;
    if (!std.mem.eql(u8, method, "GET") and !std.mem.eql(u8, method, "HEAD")) return error.BadRequest;
    const target = it.next() orelse return error.BadRequest;
    const q = std.mem.indexOfScalar(u8, target, '?') orelse target.len;
    return target[0..q];
}

fn contentType(path: []const u8) []const u8 {
    if (std.mem.endsWith(u8, path, ".html")) return "text/html; charset=utf-8";
    if (std.mem.endsWith(u8, path, ".js")) return "application/javascript; charset=utf-8";
    if (std.mem.endsWith(u8, path, ".wasm")) return "application/wasm";
    if (std.mem.endsWith(u8, path, ".css")) return "text/css; charset=utf-8";
    if (std.mem.endsWith(u8, path, ".svg")) return "image/svg+xml";
    if (std.mem.endsWith(u8, path, ".json")) return "application/json";
    return "application/octet-stream";
}

fn writeResponse(io: Io, stream: Io.net.Stream, status: u16, ctype: []const u8, body: []const u8) !void {
    const reason: []const u8 = switch (status) {
        200 => "OK",
        400 => "Bad Request",
        404 => "Not Found",
        else => "Error",
    };

    var header_buf: [512]u8 = undefined;
    const header = try std.fmt.bufPrint(
        &header_buf,
        "HTTP/1.1 {d} {s}\r\nContent-Type: {s}\r\nContent-Length: {d}\r\nCache-Control: no-cache\r\nConnection: close\r\nCross-Origin-Opener-Policy: same-origin\r\nCross-Origin-Embedder-Policy: require-corp\r\n\r\n",
        .{ status, reason, ctype, body.len },
    );

    var out_buf: [1024]u8 = undefined;
    var writer = stream.writer(io, &out_buf);
    try writer.interface.writeAll(header);
    try writer.interface.writeAll(body);
    try writer.interface.flush();
}
