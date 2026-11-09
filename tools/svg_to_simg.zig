//! Rasterize a minimal SoftUI icon SVG subset to SIMG (RGBA8).
//! Supported: svg width/height/viewBox, linearGradient + stops, rect, circle,
//! ellipse, line, polyline, polygon, path (M/L/H/V/C/Q/Z), fill/stroke/opacity.
//! usage: svg_to_simg <in.svg> <out.simg> [size]
const std = @import("std");

const Color = struct {
    r: u8 = 0,
    g: u8 = 0,
    b: u8 = 0,
    a: u8 = 255,

    fn fromArgb(c: u32) Color {
        return .{
            .r = @truncate(c >> 16),
            .g = @truncate(c >> 8),
            .b = @truncate(c),
            .a = @truncate(c >> 24),
        };
    }

    fn toU32(self: Color) u32 {
        return (@as(u32, self.a) << 24) | (@as(u32, self.r) << 16) | (@as(u32, self.g) << 8) | self.b;
    }

    fn withAlpha(self: Color, a: u8) Color {
        return .{ .r = self.r, .g = self.g, .b = self.b, .a = a };
    }

    fn mulAlpha(self: Color, opacity: f32) Color {
        const a: u8 = @intFromFloat(@as(f32, @floatFromInt(self.a)) * opacity + 0.5);
        return self.withAlpha(a);
    }
};

const GradStop = struct { offset: f32, color: Color };
const Gradient = struct {
    id: []const u8,
    x1: f32 = 0,
    y1: f32 = 0,
    x2: f32 = 0,
    y2: f32 = 1,
    stops: [8]GradStop = undefined,
    stop_n: usize = 0,

    fn sample(self: *const Gradient, t_in: f32) Color {
        if (self.stop_n == 0) return .{};
        var t = std.math.clamp(t_in, 0.0, 1.0);
        if (self.stop_n == 1) return self.stops[0].color;
        var i: usize = 0;
        while (i + 1 < self.stop_n and self.stops[i + 1].offset < t) : (i += 1) {}
        if (i + 1 >= self.stop_n) return self.stops[self.stop_n - 1].color;
        const a = self.stops[i];
        const b = self.stops[i + 1];
        const span = b.offset - a.offset;
        const u = if (span <= 0) 0.0 else (t - a.offset) / span;
        return lerpColor(a.color, b.color, u);
    }
};

const Paint = union(enum) {
    none,
    solid: Color,
    grad: usize,
};

const Canvas = struct {
    w: u32,
    h: u32,
    px: []u8,
    grads: []Gradient,

    fn put(self: *Canvas, x: i32, y: i32, c: Color) void {
        if (x < 0 or y < 0) return;
        const xu: u32 = @intCast(x);
        const yu: u32 = @intCast(y);
        if (xu >= self.w or yu >= self.h) return;
        const o: usize = (@as(usize, yu) * @as(usize, self.w) + @as(usize, xu)) * 4;
        const sa: u32 = c.a;
        if (sa == 0) return;
        if (sa == 255) {
            self.px[o + 0] = c.r;
            self.px[o + 1] = c.g;
            self.px[o + 2] = c.b;
            self.px[o + 3] = 255;
            return;
        }
        const dr: u32 = self.px[o + 0];
        const dg: u32 = self.px[o + 1];
        const db: u32 = self.px[o + 2];
        self.px[o + 0] = @truncate((@as(u32, c.r) * sa + dr * (255 - sa)) / 255);
        self.px[o + 1] = @truncate((@as(u32, c.g) * sa + dg * (255 - sa)) / 255);
        self.px[o + 2] = @truncate((@as(u32, c.b) * sa + db * (255 - sa)) / 255);
        self.px[o + 3] = 255;
    }

    fn coverPut(self: *Canvas, x: i32, y: i32, c: Color, cover: u8) void {
        if (cover == 0) return;
        const a: u8 = @truncate((@as(u32, c.a) * cover + 127) / 255);
        self.put(x, y, c.withAlpha(a));
    }
};

fn lerpColor(a: Color, b: Color, t: f32) Color {
    const u = std.math.clamp(t, 0.0, 1.0);
    const inv = 1.0 - u;
    return .{
        .r = @intFromFloat(@as(f32, @floatFromInt(a.r)) * inv + @as(f32, @floatFromInt(b.r)) * u + 0.5),
        .g = @intFromFloat(@as(f32, @floatFromInt(a.g)) * inv + @as(f32, @floatFromInt(b.g)) * u + 0.5),
        .b = @intFromFloat(@as(f32, @floatFromInt(a.b)) * inv + @as(f32, @floatFromInt(b.b)) * u + 0.5),
        .a = @intFromFloat(@as(f32, @floatFromInt(a.a)) * inv + @as(f32, @floatFromInt(b.a)) * u + 0.5),
    };
}

fn parseHexColor(s: []const u8) ?Color {
    var t = std.mem.trim(u8, s, " \t\r\n'\"");
    if (std.ascii.eqlIgnoreCase(t, "none")) return null;
    if (t.len > 0 and t[0] == '#') t = t[1..];
    if (t.len == 3) {
        const r = (hexNibble(t[0]) orelse return null) * 17;
        const g = (hexNibble(t[1]) orelse return null) * 17;
        const b = (hexNibble(t[2]) orelse return null) * 17;
        return .{ .r = r, .g = g, .b = b, .a = 255 };
    }
    if (t.len == 6 or t.len == 8) {
        const r = ((hexNibble(t[0]) orelse return null) << 4) | (hexNibble(t[1]) orelse return null);
        const g = ((hexNibble(t[2]) orelse return null) << 4) | (hexNibble(t[3]) orelse return null);
        const b = ((hexNibble(t[4]) orelse return null) << 4) | (hexNibble(t[5]) orelse return null);
        var a: u8 = 255;
        if (t.len == 8) {
            a = ((hexNibble(t[6]) orelse return null) << 4) | (hexNibble(t[7]) orelse return null);
        }
        return .{ .r = r, .g = g, .b = b, .a = a };
    }
    return null;
}

fn hexNibble(c: u8) ?u8 {
    return switch (c) {
        '0'...'9' => c - '0',
        'a'...'f' => c - 'a' + 10,
        'A'...'F' => c - 'A' + 10,
        else => null,
    };
}

fn attr(tag: []const u8, key: []const u8) ?[]const u8 {
    var i: usize = 0;
    while (i + key.len + 2 < tag.len) : (i += 1) {
        if (!std.mem.startsWith(u8, tag[i..], key)) continue;
        if (i > 0 and isIdent(tag[i - 1])) continue;
        var j = i + key.len;
        while (j < tag.len and (tag[j] == ' ' or tag[j] == '\t')) : (j += 1) {}
        if (j >= tag.len or tag[j] != '=') continue;
        j += 1;
        while (j < tag.len and (tag[j] == ' ' or tag[j] == '\t')) : (j += 1) {}
        if (j >= tag.len) return null;
        const quote = tag[j];
        if (quote == '"' or quote == '\'') {
            j += 1;
            const start = j;
            while (j < tag.len and tag[j] != quote) : (j += 1) {}
            return tag[start..j];
        }
        const start = j;
        while (j < tag.len and tag[j] != ' ' and tag[j] != '/' and tag[j] != '>') : (j += 1) {}
        return tag[start..j];
    }
    return null;
}

fn isIdent(c: u8) bool {
    return (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or (c >= '0' and c <= '9') or c == '_' or c == '-' or c == ':';
}

fn parseF32(s: []const u8) f32 {
    const t = std.mem.trim(u8, s, " \t\r\npx");
    return std.fmt.parseFloat(f32, t) catch 0;
}

fn resolvePaint(raw: ?[]const u8, grads: []const Gradient, opacity: f32, fallback: Paint) Paint {
    const s0 = raw orelse {
        return switch (fallback) {
            .solid => |c| .{ .solid = c.mulAlpha(opacity) },
            else => fallback,
        };
    };
    const s = std.mem.trim(u8, s0, " \t\r\n'\"");
    if (s.len == 0 or std.ascii.eqlIgnoreCase(s, "none")) return .none;
    if (std.mem.startsWith(u8, s, "url(#") and std.mem.endsWith(u8, s, ")")) {
        const id = s[5 .. s.len - 1];
        for (grads, 0..) |g, i| {
            if (std.mem.eql(u8, g.id, id)) return .{ .grad = i };
        }
        return .none;
    }
    if (parseHexColor(s)) |c| return .{ .solid = c.mulAlpha(opacity) };
    return fallback;
}

fn paintAt(paint: Paint, grads: []const Gradient, x: f32, y: f32, bx: f32, by: f32, bw: f32, bh: f32) ?Color {
    return switch (paint) {
        .none => null,
        .solid => |c| c,
        .grad => |gi| blk: {
            const g = grads[gi];
            const x1 = bx + g.x1 * bw;
            const y1 = by + g.y1 * bh;
            const x2 = bx + g.x2 * bw;
            const y2 = by + g.y2 * bh;
            const dx = x2 - x1;
            const dy = y2 - y1;
            const den = dx * dx + dy * dy;
            const t = if (den <= 0.0001) 0.0 else ((x - x1) * dx + (y - y1) * dy) / den;
            break :blk g.sample(t);
        },
    };
}

fn fillRect(c: *Canvas, x0: f32, y0: f32, w: f32, h: f32, rx: f32, ry: f32, paint: Paint) void {
    if (w <= 0 or h <= 0) return;
    const x1 = x0 + w;
    const y1 = y0 + h;
    const rrx = @min(rx, w * 0.5);
    const rry = @min(ry, h * 0.5);
    var yi: i32 = @intFromFloat(@floor(y0));
    const y_end: i32 = @intFromFloat(@ceil(y1));
    while (yi < y_end) : (yi += 1) {
        var xi: i32 = @intFromFloat(@floor(x0));
        const x_end: i32 = @intFromFloat(@ceil(x1));
        while (xi < x_end) : (xi += 1) {
            const px = @as(f32, @floatFromInt(xi)) + 0.5;
            const py = @as(f32, @floatFromInt(yi)) + 0.5;
            if (px < x0 or px >= x1 or py < y0 or py >= y1) continue;
            var inside = true;
            if (rrx > 0.5 and rry > 0.5) {
                var cx = px;
                var cy = py;
                if (px < x0 + rrx) cx = x0 + rrx else if (px > x1 - rrx) cx = x1 - rrx;
                if (py < y0 + rry) cy = y0 + rry else if (py > y1 - rry) cy = y1 - rry;
                if (cx != px or cy != py) {
                    const nx = (px - cx) / rrx;
                    const ny = (py - cy) / rry;
                    if (nx * nx + ny * ny > 1.0) inside = false;
                }
            }
            if (!inside) continue;
            if (paintAt(paint, c.grads, px, py, x0, y0, w, h)) |col| c.put(xi, yi, col);
        }
    }
}

fn fillEllipse(c: *Canvas, cx: f32, cy: f32, rx: f32, ry: f32, paint: Paint) void {
    if (rx <= 0 or ry <= 0) return;
    const x0: i32 = @intFromFloat(@floor(cx - rx - 1));
    const y0: i32 = @intFromFloat(@floor(cy - ry - 1));
    const x1: i32 = @intFromFloat(@ceil(cx + rx + 1));
    const y1: i32 = @intFromFloat(@ceil(cy + ry + 1));
    var yi = y0;
    while (yi <= y1) : (yi += 1) {
        var xi = x0;
        while (xi <= x1) : (xi += 1) {
            const px = @as(f32, @floatFromInt(xi)) + 0.5;
            const py = @as(f32, @floatFromInt(yi)) + 0.5;
            const nx = (px - cx) / rx;
            const ny = (py - cy) / ry;
            const d = nx * nx + ny * ny;
            if (d > 1.15) continue;
            const cover: u8 = if (d <= 0.92) 255 else @intFromFloat((1.15 - d) / 0.23 * 255.0);
            if (paintAt(paint, c.grads, px, py, cx - rx, cy - ry, rx * 2, ry * 2)) |col| {
                c.coverPut(xi, yi, col, cover);
            }
        }
    }
}

fn strokeLine(c: *Canvas, x0: f32, y0: f32, x1: f32, y1: f32, width: f32, col: Color) void {
    const dx = x1 - x0;
    const dy = y1 - y0;
    const len = @sqrt(dx * dx + dy * dy);
    if (len < 0.001) return;
    const steps: i32 = @intFromFloat(@max(1.0, len * 2));
    const half = width * 0.5;
    var i: i32 = 0;
    while (i <= steps) : (i += 1) {
        const t = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(steps));
        const x = x0 + dx * t;
        const y = y0 + dy * t;
        fillEllipse(c, x, y, half, half, .{ .solid = col });
    }
}

const Pt = struct { x: f32, y: f32 };

fn fillPolygon(c: *Canvas, pts: []const Pt, paint: Paint) void {
    if (pts.len < 3) return;
    var min_x = pts[0].x;
    var max_x = pts[0].x;
    var min_y = pts[0].y;
    var max_y = pts[0].y;
    for (pts[1..]) |p| {
        min_x = @min(min_x, p.x);
        max_x = @max(max_x, p.x);
        min_y = @min(min_y, p.y);
        max_y = @max(max_y, p.y);
    }
    const y0: i32 = @intFromFloat(@floor(min_y));
    const y1: i32 = @intFromFloat(@ceil(max_y));
    const x0: i32 = @intFromFloat(@floor(min_x));
    const x1: i32 = @intFromFloat(@ceil(max_x));
    var yi = y0;
    while (yi <= y1) : (yi += 1) {
        var xi = x0;
        while (xi <= x1) : (xi += 1) {
            const px = @as(f32, @floatFromInt(xi)) + 0.5;
            const py = @as(f32, @floatFromInt(yi)) + 0.5;
            if (pointInPoly(pts, px, py)) {
                if (paintAt(paint, c.grads, px, py, min_x, min_y, max_x - min_x, max_y - min_y)) |col| {
                    c.put(xi, yi, col);
                }
            }
        }
    }
}

fn pointInPoly(pts: []const Pt, x: f32, y: f32) bool {
    var inside = false;
    var i: usize = 0;
    var j = pts.len - 1;
    while (i < pts.len) : ({
        j = i;
        i += 1;
    }) {
        const yi = pts[i].y;
        const yj = pts[j].y;
        const xi = pts[i].x;
        const xj = pts[j].x;
        const intersect = ((yi > y) != (yj > y)) and (x < (xj - xi) * (y - yi) / (yj - yi + 0.0000001) + xi);
        if (intersect) inside = !inside;
    }
    return inside;
}

fn appendPt(list: *std.ArrayList(Pt), gpa: std.mem.Allocator, x: f32, y: f32) !void {
    try list.append(gpa, .{ .x = x, .y = y });
}

fn parsePath(gpa: std.mem.Allocator, d: []const u8) ![]Pt {
    var pts: std.ArrayList(Pt) = .empty;
    errdefer pts.deinit(gpa);
    var i: usize = 0;
    var cx: f32 = 0;
    var cy: f32 = 0;
    var start_x: f32 = 0;
    var start_y: f32 = 0;
    var cmd: u8 = 'M';

    while (i < d.len) {
        const c = d[i];
        if (std.ascii.isAlphabetic(c)) {
            cmd = c;
            i += 1;
            continue;
        }
        if (c == ' ' or c == ',' or c == '\t' or c == '\n' or c == '\r') {
            i += 1;
            continue;
        }
        const n0 = try readNumber(d, &i);
        switch (cmd) {
            'M', 'm' => {
                var x = n0;
                var y = try readNumber(d, &i);
                if (cmd == 'm') {
                    x += cx;
                    y += cy;
                }
                cx = x;
                cy = y;
                start_x = x;
                start_y = y;
                try appendPt(&pts, gpa, x, y);
                cmd = if (cmd == 'M') 'L' else 'l';
            },
            'L', 'l' => {
                var x = n0;
                var y = try readNumber(d, &i);
                if (cmd == 'l') {
                    x += cx;
                    y += cy;
                }
                cx = x;
                cy = y;
                try appendPt(&pts, gpa, x, y);
            },
            'H', 'h' => {
                var x = n0;
                if (cmd == 'h') x += cx;
                cx = x;
                try appendPt(&pts, gpa, cx, cy);
            },
            'V', 'v' => {
                var y = n0;
                if (cmd == 'v') y += cy;
                cy = y;
                try appendPt(&pts, gpa, cx, cy);
            },
            'Z', 'z' => {
                cx = start_x;
                cy = start_y;
                try appendPt(&pts, gpa, cx, cy);
            },
            'C', 'c' => {
                var x1 = n0;
                var y1 = try readNumber(d, &i);
                var x2 = try readNumber(d, &i);
                var y2 = try readNumber(d, &i);
                var x = try readNumber(d, &i);
                var y = try readNumber(d, &i);
                if (cmd == 'c') {
                    x1 += cx;
                    y1 += cy;
                    x2 += cx;
                    y2 += cy;
                    x += cx;
                    y += cy;
                }
                try subdivideCubic(&pts, gpa, cx, cy, x1, y1, x2, y2, x, y, 8);
                cx = x;
                cy = y;
            },
            'Q', 'q' => {
                var x1 = n0;
                var y1 = try readNumber(d, &i);
                var x = try readNumber(d, &i);
                var y = try readNumber(d, &i);
                if (cmd == 'q') {
                    x1 += cx;
                    y1 += cy;
                    x += cx;
                    y += cy;
                }
                try subdivideQuad(&pts, gpa, cx, cy, x1, y1, x, y, 8);
                cx = x;
                cy = y;
            },
            else => {},
        }
    }
    return try pts.toOwnedSlice(gpa);
}

fn readNumber(d: []const u8, i: *usize) !f32 {
    while (i.* < d.len and (d[i.*] == ' ' or d[i.*] == ',' or d[i.*] == '\t' or d[i.*] == '\n' or d[i.*] == '\r')) : (i.* += 1) {}
    if (i.* >= d.len) return error.BadPath;
    const start = i.*;
    if (d[i.*] == '-' or d[i.*] == '+') i.* += 1;
    while (i.* < d.len and ((d[i.*] >= '0' and d[i.*] <= '9') or d[i.*] == '.' or d[i.*] == 'e' or d[i.*] == 'E')) : (i.* += 1) {}
    if (start == i.*) return error.BadPath;
    return std.fmt.parseFloat(f32, d[start..i.*]) catch error.BadPath;
}

fn subdivideCubic(pts: *std.ArrayList(Pt), gpa: std.mem.Allocator, x0: f32, y0: f32, x1: f32, y1: f32, x2: f32, y2: f32, x3: f32, y3: f32, n: usize) !void {
    var s: usize = 1;
    while (s <= n) : (s += 1) {
        const t = @as(f32, @floatFromInt(s)) / @as(f32, @floatFromInt(n));
        const u = 1.0 - t;
        const x = u * u * u * x0 + 3 * u * u * t * x1 + 3 * u * t * t * x2 + t * t * t * x3;
        const y = u * u * u * y0 + 3 * u * u * t * y1 + 3 * u * t * t * y2 + t * t * t * y3;
        try appendPt(pts, gpa, x, y);
    }
}

fn subdivideQuad(pts: *std.ArrayList(Pt), gpa: std.mem.Allocator, x0: f32, y0: f32, x1: f32, y1: f32, x2: f32, y2: f32, n: usize) !void {
    var s: usize = 1;
    while (s <= n) : (s += 1) {
        const t = @as(f32, @floatFromInt(s)) / @as(f32, @floatFromInt(n));
        const u = 1.0 - t;
        const x = u * u * x0 + 2 * u * t * x1 + t * t * x2;
        const y = u * u * y0 + 2 * u * t * y1 + t * t * y2;
        try appendPt(pts, gpa, x, y);
    }
}

fn parsePolyline(gpa: std.mem.Allocator, points: []const u8) ![]Pt {
    var pts: std.ArrayList(Pt) = .empty;
    errdefer pts.deinit(gpa);
    var i: usize = 0;
    while (i < points.len) {
        while (i < points.len and (points[i] == ' ' or points[i] == ',' or points[i] == '\t' or points[i] == '\n')) : (i += 1) {}
        if (i >= points.len) break;
        const x = try readNumber(points, &i);
        const y = try readNumber(points, &i);
        try appendPt(&pts, gpa, x, y);
    }
    return try pts.toOwnedSlice(gpa);
}

fn tagName(tag: []const u8) []const u8 {
    var i: usize = 0;
    while (i < tag.len and tag[i] != ' ' and tag[i] != '\t' and tag[i] != '/' and tag[i] != '>') : (i += 1) {}
    return tag[0..i];
}

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const io = init.io;

    var args = try init.minimal.args.iterateAllocator(gpa);
    defer args.deinit();
    _ = args.next();

    const in_path = args.next() orelse {
        std.debug.print("usage: svg_to_simg <in.svg> <out.simg> [size]\n", .{});
        return error.Usage;
    };
    const out_path = args.next() orelse return error.Usage;
    const size_override: ?u32 = if (args.next()) |s| try std.fmt.parseInt(u32, s, 10) else null;

    var cwd = std.Io.Dir.cwd();
    const svg = try cwd.readFileAlloc(io, in_path, gpa, .limited(2 * 1024 * 1024));
    defer gpa.free(svg);

    var width: u32 = size_override orelse 64;
    var height: u32 = size_override orelse 64;

    // First pass: dimensions + gradients
    var grads: std.ArrayList(Gradient) = .empty;
    defer {
        for (grads.items) |g| gpa.free(g.id);
        grads.deinit(gpa);
    }

    var i: usize = 0;
    while (i < svg.len) {
        const lt = std.mem.indexOfScalarPos(u8, svg, i, '<') orelse break;
        const gt = std.mem.indexOfScalarPos(u8, svg, lt, '>') orelse break;
        const raw = svg[lt + 1 .. gt];
        i = gt + 1;
        if (raw.len == 0 or raw[0] == '?' or raw[0] == '!') continue;
        const closing = raw[0] == '/';
        const body = if (closing) raw[1..] else raw;
        const name = tagName(body);
        if (std.mem.eql(u8, name, "svg")) {
            if (attr(body, "width")) |w| width = size_override orelse @intFromFloat(@max(1.0, parseF32(w)));
            if (attr(body, "height")) |h| height = size_override orelse @intFromFloat(@max(1.0, parseF32(h)));
            if (size_override) |s| {
                width = s;
                height = s;
            }
        } else if (std.mem.eql(u8, name, "linearGradient")) {
            const id = attr(body, "id") orelse continue;
            var g: Gradient = .{ .id = try gpa.dupe(u8, id) };
            if (attr(body, "x1")) |v| g.x1 = parseF32(v);
            if (attr(body, "y1")) |v| g.y1 = parseF32(v);
            if (attr(body, "x2")) |v| g.x2 = parseF32(v);
            if (attr(body, "y2")) |v| g.y2 = parseF32(v);
            // unit objectBoundingBox assumed 0..1
            // Collect nested stops until </linearGradient>
            var j = i;
            while (j < svg.len) {
                const lt2 = std.mem.indexOfScalarPos(u8, svg, j, '<') orelse break;
                const gt2 = std.mem.indexOfScalarPos(u8, svg, lt2, '>') orelse break;
                const raw2 = svg[lt2 + 1 .. gt2];
                j = gt2 + 1;
                const name2 = tagName(if (raw2.len > 0 and raw2[0] == '/') raw2[1..] else raw2);
                if (raw2.len > 0 and raw2[0] == '/' and std.mem.eql(u8, name2, "linearGradient")) {
                    i = j;
                    break;
                }
                if (std.mem.eql(u8, name2, "stop") and g.stop_n < g.stops.len) {
                    const off = if (attr(raw2, "offset")) |o| parseF32(o) else 0;
                    var col = Color{ .r = 0, .g = 0, .b = 0, .a = 255 };
                    if (attr(raw2, "stop-color")) |sc| {
                        if (parseHexColor(sc)) |c| col = c;
                    }
                    if (attr(raw2, "stop-opacity")) |so| {
                        col = col.mulAlpha(parseF32(so));
                    }
                    // style="stop-color:#..;stop-opacity:.."
                    if (attr(raw2, "style")) |style| {
                        if (std.mem.indexOf(u8, style, "stop-color:")) |p| {
                            var q = p + 11;
                            while (q < style.len and style[q] != ';' and style[q] != '"') : (q += 1) {}
                            if (parseHexColor(style[p + 11 .. q])) |c| col = c;
                        }
                    }
                    g.stops[g.stop_n] = .{ .offset = off, .color = col };
                    g.stop_n += 1;
                }
            }
            try grads.append(gpa, g);
        }
    }

    const pixels = try gpa.alloc(u8, @as(usize, width) * @as(usize, height) * 4);
    defer gpa.free(pixels);
    @memset(pixels, 0);

    var canvas = Canvas{ .w = width, .h = height, .px = pixels, .grads = grads.items };

    // Second pass: draw shapes
    i = 0;
    while (i < svg.len) {
        const lt = std.mem.indexOfScalarPos(u8, svg, i, '<') orelse break;
        const gt = std.mem.indexOfScalarPos(u8, svg, lt, '>') orelse break;
        const raw = svg[lt + 1 .. gt];
        i = gt + 1;
        if (raw.len == 0 or raw[0] == '?' or raw[0] == '!' or raw[0] == '/') continue;
        const name = tagName(raw);
        const opacity: f32 = if (attr(raw, "opacity")) |o| parseF32(o) else 1.0;
        const fill_paint = resolvePaint(attr(raw, "fill"), grads.items, opacity, .{ .solid = .{ .r = 0, .g = 0, .b = 0, .a = 255 } });
        const stroke_paint = resolvePaint(attr(raw, "stroke"), grads.items, opacity, .none);
        const sw = if (attr(raw, "stroke-width")) |v| parseF32(v) else 1.0;

        if (std.mem.eql(u8, name, "rect")) {
            const x = if (attr(raw, "x")) |v| parseF32(v) else 0;
            const y = if (attr(raw, "y")) |v| parseF32(v) else 0;
            const w = if (attr(raw, "width")) |v| parseF32(v) else 0;
            const h = if (attr(raw, "height")) |v| parseF32(v) else 0;
            const rx = if (attr(raw, "rx")) |v| parseF32(v) else 0;
            const ry = if (attr(raw, "ry")) |v| parseF32(v) else rx;
            fillRect(&canvas, x, y, w, h, rx, ry, fill_paint);
            if (stroke_paint == .solid) {
                // simple stroke as inset outline approx
                const col = stroke_paint.solid;
                fillRect(&canvas, x, y, w, sw, 0, 0, .{ .solid = col });
                fillRect(&canvas, x, y + h - sw, w, sw, 0, 0, .{ .solid = col });
                fillRect(&canvas, x, y, sw, h, 0, 0, .{ .solid = col });
                fillRect(&canvas, x + w - sw, y, sw, h, 0, 0, .{ .solid = col });
            }
        } else if (std.mem.eql(u8, name, "circle")) {
            const cx = if (attr(raw, "cx")) |v| parseF32(v) else 0;
            const cy = if (attr(raw, "cy")) |v| parseF32(v) else 0;
            const r = if (attr(raw, "r")) |v| parseF32(v) else 0;
            fillEllipse(&canvas, cx, cy, r, r, fill_paint);
            if (stroke_paint == .solid) {
                // ring approx
                const col = stroke_paint.solid;
                const steps: i32 = @intFromFloat(@max(16.0, r * 6));
                var s: i32 = 0;
                while (s < steps) : (s += 1) {
                    const a0 = @as(f32, @floatFromInt(s)) / @as(f32, @floatFromInt(steps)) * std.math.tau;
                    const a1 = @as(f32, @floatFromInt(s + 1)) / @as(f32, @floatFromInt(steps)) * std.math.tau;
                    strokeLine(&canvas, cx + @cos(a0) * r, cy + @sin(a0) * r, cx + @cos(a1) * r, cy + @sin(a1) * r, sw, col);
                }
            }
        } else if (std.mem.eql(u8, name, "ellipse")) {
            const cx = if (attr(raw, "cx")) |v| parseF32(v) else 0;
            const cy = if (attr(raw, "cy")) |v| parseF32(v) else 0;
            const rx = if (attr(raw, "rx")) |v| parseF32(v) else 0;
            const ry = if (attr(raw, "ry")) |v| parseF32(v) else 0;
            fillEllipse(&canvas, cx, cy, rx, ry, fill_paint);
        } else if (std.mem.eql(u8, name, "line")) {
            if (stroke_paint == .solid) {
                const x1 = if (attr(raw, "x1")) |v| parseF32(v) else 0;
                const y1 = if (attr(raw, "y1")) |v| parseF32(v) else 0;
                const x2 = if (attr(raw, "x2")) |v| parseF32(v) else 0;
                const y2 = if (attr(raw, "y2")) |v| parseF32(v) else 0;
                strokeLine(&canvas, x1, y1, x2, y2, sw, stroke_paint.solid);
            }
        } else if (std.mem.eql(u8, name, "polygon") or std.mem.eql(u8, name, "polyline")) {
            if (attr(raw, "points")) |pts_s| {
                const pts = try parsePolyline(gpa, pts_s);
                defer gpa.free(pts);
                if (fill_paint != .none) fillPolygon(&canvas, pts, fill_paint);
                if (stroke_paint == .solid and pts.len > 1) {
                    var p: usize = 0;
                    while (p + 1 < pts.len) : (p += 1) {
                        strokeLine(&canvas, pts[p].x, pts[p].y, pts[p + 1].x, pts[p + 1].y, sw, stroke_paint.solid);
                    }
                    if (std.mem.eql(u8, name, "polygon") and pts.len > 2) {
                        strokeLine(&canvas, pts[pts.len - 1].x, pts[pts.len - 1].y, pts[0].x, pts[0].y, sw, stroke_paint.solid);
                    }
                }
            }
        } else if (std.mem.eql(u8, name, "path")) {
            if (attr(raw, "d")) |d| {
                const pts = try parsePath(gpa, d);
                defer gpa.free(pts);
                if (fill_paint != .none) fillPolygon(&canvas, pts, fill_paint);
                if (stroke_paint == .solid and pts.len > 1) {
                    var p: usize = 0;
                    while (p + 1 < pts.len) : (p += 1) {
                        strokeLine(&canvas, pts[p].x, pts[p].y, pts[p + 1].x, pts[p + 1].y, sw, stroke_paint.solid);
                    }
                }
            }
        }
    }

    var out = try gpa.alloc(u8, 12 + pixels.len);
    defer gpa.free(out);
    @memcpy(out[0..4], "SIMG");
    std.mem.writeInt(u32, out[4..8], width, .little);
    std.mem.writeInt(u32, out[8..12], height, .little);
    @memcpy(out[12..], pixels);

    try cwd.writeFile(.{ .sub_path = out_path, .data = out });
    std.debug.print("wrote {s} ({d}x{d}, {d} bytes)\n", .{ out_path, width, height, out.len });
}
