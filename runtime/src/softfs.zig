//! SoftFS — mutable in-memory filesystem SoftShell / SoftASM can manipulate.
//! Mounts a packed SOFS image as the initial tree; `pack` serializes the live
//! tree for Host ABI persistence.

const std = @import("std");

pub const MAX_NODES: usize = 128;
pub const MAX_NAME: usize = 31;
pub const DATA_HEAP: usize = 512 * 1024;
pub const ROOT: u16 = 0;
pub const PARENT_ROOT: u16 = 0xFFFF;
pub const V1_ENTRY_SIZE: usize = 40;
pub const V2_ENTRY_SIZE: usize = 44;

pub const Kind = enum(u8) { file = 0, dir = 1 };

pub const Node = struct {
    name: [MAX_NAME + 1]u8 = @splat(0),
    name_len: u8 = 0,
    kind: Kind = .file,
    parent: u16 = ROOT,
    /// Used flag: free slots have used=false.
    used: bool = false,
    /// File payload in heap (ignored for dirs).
    data_off: u32 = 0,
    data_len: u32 = 0,
    data_cap: u32 = 0,
};

pub const Fs = struct {
    nodes: [MAX_NODES]Node = undefined,
    heap: [DATA_HEAP]u8 = undefined,
    heap_used: u32 = 0,
    cwd: u16 = ROOT,
    node_count: u16 = 0,

    pub fn initEmpty(self: *Fs) void {
        @memset(std.mem.asBytes(&self.nodes), 0);
        @memset(&self.heap, 0);
        self.heap_used = 0;
        self.cwd = ROOT;
        self.node_count = 0;
        // Root directory "/"
        self.nodes[ROOT] = .{
            .used = true,
            .kind = .dir,
            .parent = ROOT,
            .name_len = 1,
        };
        self.nodes[ROOT].name[0] = '/';
        self.node_count = 1;
    }

    /// Mount packed SoftFS image into a mutable tree.
    /// v1: flat files under `/`. v2: directory tree with parent indices.
    pub fn mount(self: *Fs, blob: []const u8) !void {
        self.initEmpty();
        if (blob.len < 8) return error.Truncated;
        if (!std.mem.eql(u8, blob[0..4], "SOFS")) return error.BadMagic;
        const version = std.mem.readInt(u16, blob[4..6], .little);
        const count = std.mem.readInt(u16, blob[6..8], .little);
        if (version == 1) {
            try self.mountV1(blob, count);
        } else if (version == 2) {
            try self.mountV2(blob, count);
        } else {
            return error.BadVersion;
        }
    }

    fn mountV1(self: *Fs, blob: []const u8, file_count: u16) !void {
        const table_bytes: usize = @as(usize, file_count) * V1_ENTRY_SIZE;
        if (blob.len < 8 + table_bytes) return error.Truncated;
        const data_base: usize = 8 + table_bytes;

        var i: usize = 0;
        while (i < file_count) : (i += 1) {
            const ent = blob[8 + i * V1_ENTRY_SIZE .. 8 + (i + 1) * V1_ENTRY_SIZE];
            const name_raw = ent[0..32];
            const name_len = std.mem.indexOfScalar(u8, name_raw, 0) orelse 32;
            const offset = std.mem.readInt(u32, ent[32..36], .little);
            const size = std.mem.readInt(u32, ent[36..40], .little);
            const start = data_base + offset;
            const end = start + size;
            if (end > blob.len) return error.Truncated;
            const name = name_raw[0..name_len];
            _ = try self.createFile(ROOT, name, blob[start..end]);
        }
    }

    fn mountV2(self: *Fs, blob: []const u8, node_count: u16) !void {
        const table_bytes: usize = @as(usize, node_count) * V2_ENTRY_SIZE;
        if (blob.len < 8 + table_bytes) return error.Truncated;
        const data_base: usize = 8 + table_bytes;
        var created: [MAX_NODES]u16 = undefined;

        var i: usize = 0;
        while (i < node_count) : (i += 1) {
            const ent = blob[8 + i * V2_ENTRY_SIZE .. 8 + (i + 1) * V2_ENTRY_SIZE];
            const name_raw = ent[0..32];
            const name_len = std.mem.indexOfScalar(u8, name_raw, 0) orelse 32;
            if (name_len == 0 or name_len > MAX_NAME) return error.BadName;
            const name = name_raw[0..name_len];
            const parent_pack = std.mem.readInt(u16, ent[32..34], .little);
            const kind_raw = ent[34];
            const offset = std.mem.readInt(u32, ent[36..40], .little);
            const size = std.mem.readInt(u32, ent[40..44], .little);

            const parent_fs: u16 = if (parent_pack == PARENT_ROOT) ROOT else blk: {
                if (parent_pack >= i) return error.BadParent;
                break :blk created[parent_pack];
            };

            if (kind_raw == @intFromEnum(Kind.dir)) {
                created[i] = try self.mkdir(parent_fs, name);
            } else if (kind_raw == @intFromEnum(Kind.file)) {
                const start = data_base + offset;
                const end = start + size;
                if (end > blob.len) return error.Truncated;
                created[i] = try self.createFile(parent_fs, name, blob[start..end]);
            } else {
                return error.BadKind;
            }
        }
    }

    /// Serialize the live tree as SoftFS v2 into `out`. Returns bytes written.
    pub fn pack(self: *const Fs, out: []u8) !usize {
        var order: [MAX_NODES]u16 = undefined;
        var order_len: usize = 0;
        var map: [MAX_NODES]u16 = @splat(PARENT_ROOT);
        var queue: [MAX_NODES]u16 = undefined;
        var qh: usize = 0;
        var qt: usize = 0;

        var i: u16 = 1;
        while (i < MAX_NODES) : (i += 1) {
            if (self.nodes[i].used and self.nodes[i].parent == ROOT) {
                queue[qt] = i;
                qt += 1;
            }
        }
        while (qh < qt) {
            const idx = queue[qh];
            qh += 1;
            map[idx] = @intCast(order_len);
            order[order_len] = idx;
            order_len += 1;
            var c: u16 = 1;
            while (c < MAX_NODES) : (c += 1) {
                if (self.nodes[c].used and self.nodes[c].parent == idx) {
                    queue[qt] = c;
                    qt += 1;
                }
            }
        }

        var data_size: u32 = 0;
        for (order[0..order_len]) |idx| {
            if (self.nodes[idx].kind == .file) data_size += self.nodes[idx].data_len;
        }
        const header: usize = 8 + order_len * V2_ENTRY_SIZE;
        const total = header + data_size;
        if (total > out.len) return error.NoSpace;

        @memset(out[0..total], 0);
        out[0] = 'S';
        out[1] = 'O';
        out[2] = 'F';
        out[3] = 'S';
        std.mem.writeInt(u16, out[4..6], 2, .little);
        std.mem.writeInt(u16, out[6..8], @intCast(order_len), .little);

        var data_off: u32 = 0;
        var ent: usize = 8;
        for (order[0..order_len]) |idx| {
            const n = &self.nodes[idx];
            const name = self.nameOf(idx);
            @memcpy(out[ent .. ent + name.len], name);
            const parent_pack: u16 = if (n.parent == ROOT) PARENT_ROOT else map[n.parent];
            std.mem.writeInt(u16, out[ent + 32 ..][0..2], parent_pack, .little);
            out[ent + 34] = @intFromEnum(n.kind);
            out[ent + 35] = 0;
            if (n.kind == .file) {
                std.mem.writeInt(u32, out[ent + 36 ..][0..4], data_off, .little);
                std.mem.writeInt(u32, out[ent + 40 ..][0..4], n.data_len, .little);
                data_off += n.data_len;
            }
            ent += V2_ENTRY_SIZE;
        }

        var copy_at = header;
        for (order[0..order_len]) |idx| {
            const n = &self.nodes[idx];
            if (n.kind != .file or n.data_len == 0) continue;
            @memcpy(out[copy_at .. copy_at + n.data_len], self.heap[n.data_off .. n.data_off + n.data_len]);
            copy_at += n.data_len;
        }
        return total;
    }

    pub fn nameOf(self: *const Fs, idx: u16) []const u8 {
        const n = &self.nodes[idx];
        return n.name[0..n.name_len];
    }

    pub fn findChild(self: *const Fs, parent: u16, name: []const u8) ?u16 {
        var i: u16 = 0;
        while (i < MAX_NODES) : (i += 1) {
            const n = &self.nodes[i];
            if (!n.used) continue;
            if (n.parent != parent) continue;
            if (i == ROOT) continue;
            if (std.mem.eql(u8, self.nameOf(i), name)) return i;
        }
        return null;
    }

    /// Resolve path relative to cwd (or absolute from /).
    pub fn resolve(self: *const Fs, path: []const u8) ?u16 {
        if (path.len == 0) return self.cwd;
        var idx: u16 = if (path[0] == '/') ROOT else self.cwd;
        var it = std.mem.tokenizeScalar(u8, path, '/');
        while (it.next()) |part| {
            if (part.len == 0 or std.mem.eql(u8, part, ".")) continue;
            if (std.mem.eql(u8, part, "..")) {
                if (idx != ROOT) idx = self.nodes[idx].parent;
                continue;
            }
            idx = self.findChild(idx, part) orelse return null;
        }
        return idx;
    }

    pub fn resolveParent(self: *const Fs, path: []const u8) ?struct { parent: u16, name: []const u8 } {
        if (path.len == 0) return null;
        if (std.mem.eql(u8, path, "/")) return null;
        const slash = std.mem.lastIndexOfScalar(u8, path, '/');
        if (slash == null) {
            return .{ .parent = self.cwd, .name = path };
        }
        const s = slash.?;
        const parent_path = if (s == 0) "/" else path[0..s];
        const name = path[s + 1 ..];
        if (name.len == 0) return null;
        const parent = self.resolve(parent_path) orelse return null;
        return .{ .parent = parent, .name = name };
    }

    fn allocNode(self: *Fs) !u16 {
        var i: u16 = 1;
        while (i < MAX_NODES) : (i += 1) {
            if (!self.nodes[i].used) {
                self.nodes[i] = .{ .used = true };
                self.node_count += 1;
                return i;
            }
        }
        return error.NoSpace;
    }

    fn allocData(self: *Fs, size: u32) !u32 {
        if (self.heap_used + size > DATA_HEAP) return error.NoSpace;
        const off = self.heap_used;
        self.heap_used += size;
        return off;
    }

    pub fn createFile(self: *Fs, parent: u16, name: []const u8, data: []const u8) !u16 {
        if (!self.nodes[parent].used or self.nodes[parent].kind != .dir) return error.NotDir;
        if (name.len == 0 or name.len > MAX_NAME) return error.BadName;
        if (self.findChild(parent, name) != null) return error.Exists;
        const idx = try self.allocNode();
        var n = &self.nodes[idx];
        n.kind = .file;
        n.parent = parent;
        n.name_len = @intCast(name.len);
        @memcpy(n.name[0..name.len], name);
        n.name[name.len] = 0;
        const cap: u32 = @intCast(@max(data.len, 16));
        const off = try self.allocData(cap);
        @memcpy(self.heap[off .. off + data.len], data);
        n.data_off = off;
        n.data_len = @intCast(data.len);
        n.data_cap = cap;
        return idx;
    }

    pub fn mkdir(self: *Fs, parent: u16, name: []const u8) !u16 {
        if (!self.nodes[parent].used or self.nodes[parent].kind != .dir) return error.NotDir;
        if (name.len == 0 or name.len > MAX_NAME) return error.BadName;
        if (self.findChild(parent, name) != null) return error.Exists;
        const idx = try self.allocNode();
        var n = &self.nodes[idx];
        n.kind = .dir;
        n.parent = parent;
        n.name_len = @intCast(name.len);
        @memcpy(n.name[0..name.len], name);
        n.name[name.len] = 0;
        return idx;
    }

    pub fn fileData(self: *const Fs, idx: u16) ?[]const u8 {
        const n = &self.nodes[idx];
        if (!n.used or n.kind != .file) return null;
        return self.heap[n.data_off .. n.data_off + n.data_len];
    }

    /// Find file by basename under cwd or absolute path (compat with old API).
    pub fn find(self: *const Fs, path: []const u8) ?[]const u8 {
        const idx = self.resolve(path) orelse return null;
        return self.fileData(idx);
    }

    pub fn writeFile(self: *Fs, idx: u16, data: []const u8, append: bool) !void {
        var n = &self.nodes[idx];
        if (!n.used or n.kind != .file) return error.NotFile;
        const new_len: u32 = if (append) n.data_len + @as(u32, @intCast(data.len)) else @intCast(data.len);
        if (new_len > n.data_cap) {
            const cap = @max(new_len, n.data_cap * 2);
            const off = try self.allocData(cap);
            if (append and n.data_len > 0) {
                @memcpy(self.heap[off .. off + n.data_len], self.heap[n.data_off .. n.data_off + n.data_len]);
            }
            n.data_off = off;
            n.data_cap = cap;
            if (!append) n.data_len = 0;
        } else if (!append) {
            n.data_len = 0;
        }
        @memcpy(self.heap[n.data_off + n.data_len .. n.data_off + n.data_len + data.len], data);
        n.data_len += @intCast(data.len);
    }

    pub fn unlink(self: *Fs, idx: u16) !void {
        if (idx == ROOT) return error.Busy;
        const n = &self.nodes[idx];
        if (!n.used) return error.NotFound;
        if (n.kind == .dir) {
            // Must be empty.
            var i: u16 = 1;
            while (i < MAX_NODES) : (i += 1) {
                if (self.nodes[i].used and self.nodes[i].parent == idx) return error.NotEmpty;
            }
        }
        n.* = .{};
        if (self.node_count > 0) self.node_count -= 1;
        if (self.cwd == idx) self.cwd = ROOT;
    }

    pub fn rename(self: *Fs, idx: u16, new_parent: u16, new_name: []const u8) !void {
        if (idx == ROOT) return error.Busy;
        if (!self.nodes[idx].used) return error.NotFound;
        if (!self.nodes[new_parent].used or self.nodes[new_parent].kind != .dir) return error.NotDir;
        if (new_name.len == 0 or new_name.len > MAX_NAME) return error.BadName;
        if (self.findChild(new_parent, new_name)) |other| {
            if (other != idx) return error.Exists;
        }
        // Prevent moving dir into itself.
        if (self.nodes[idx].kind == .dir) {
            var p = new_parent;
            while (true) {
                if (p == idx) return error.Invalid;
                if (p == ROOT) break;
                p = self.nodes[p].parent;
            }
        }
        var n = &self.nodes[idx];
        n.parent = new_parent;
        n.name_len = @intCast(new_name.len);
        @memset(n.name[0..], 0);
        @memcpy(n.name[0..new_name.len], new_name);
    }

    pub fn copyFile(self: *Fs, src: u16, dest_parent: u16, dest_name: []const u8) !u16 {
        const data = self.fileData(src) orelse return error.NotFile;
        return self.createFile(dest_parent, dest_name, data);
    }

    pub fn childCount(self: *const Fs, parent: u16) u32 {
        var c: u32 = 0;
        var i: u16 = 0;
        while (i < MAX_NODES) : (i += 1) {
            if (self.nodes[i].used and self.nodes[i].parent == parent and i != ROOT) c += 1;
        }
        return c;
    }

    pub fn df(self: *const Fs) struct { nodes_used: u16, nodes_max: u16, heap_used: u32, heap_max: u32 } {
        return .{
            .nodes_used = self.node_count,
            .nodes_max = MAX_NODES,
            .heap_used = self.heap_used,
            .heap_max = DATA_HEAP,
        };
    }

    /// Format cwd path into buf; returns slice.
    pub fn cwdPath(self: *const Fs, buf: []u8) []const u8 {
        if (self.cwd == ROOT) {
            if (buf.len == 0) return "";
            buf[0] = '/';
            return buf[0..1];
        }
        var stack: [32]u16 = undefined;
        var depth: usize = 0;
        var cur = self.cwd;
        while (cur != ROOT and depth < stack.len) {
            stack[depth] = cur;
            depth += 1;
            cur = self.nodes[cur].parent;
        }
        var out: usize = 0;
        var d: usize = depth;
        while (d > 0) {
            d -= 1;
            const name = self.nameOf(stack[d]);
            if (out >= buf.len) break;
            buf[out] = '/';
            out += 1;
            const n = @min(name.len, buf.len - out);
            @memcpy(buf[out .. out + n], name[0..n]);
            out += n;
        }
        if (out == 0) {
            buf[0] = '/';
            return buf[0..1];
        }
        return buf[0..out];
    }
};
