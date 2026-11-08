const std = @import("std");
const isa = @import("isa.zig");

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const io = init.io;

    var args = try init.minimal.args.iterateAllocator(gpa);
    defer args.deinit();
    _ = args.next();
    const in_path = args.next() orelse {
        std.debug.print("usage: softasm <in.soft> <out.sox>\n", .{});
        return error.Usage;
    };
    const out_path = args.next() orelse {
        std.debug.print("usage: softasm <in.soft> <out.sox>\n", .{});
        return error.Usage;
    };

    const src = try IoDirReadFile(io, gpa, in_path);
    defer gpa.free(src);

    var asmbler = Assembler.init(gpa);
    defer asmbler.deinit();
    try asmbler.assemble(src);

    const out = try asmbler.emitSox(gpa);
    defer gpa.free(out);

    var cwd = std.Io.Dir.cwd();
    var file = try cwd.createFile(io, out_path, .{});
    defer file.close(io);
    try file.writeStreamingAll(io, out);

    std.debug.print("wrote {s} ({d} bytes, entry=0x{x})\n", .{ out_path, out.len, asmbler.entry });
}

fn IoDirReadFile(io: std.Io, gpa: std.mem.Allocator, path: []const u8) ![]u8 {
    var cwd = std.Io.Dir.cwd();
    return cwd.readFileAlloc(io, path, gpa, .limited(4 * 1024 * 1024));
}

const Section = enum { text, rodata };

const Assembler = struct {
    gpa: std.mem.Allocator,
    code: std.ArrayList(u32),
    rodata: std.ArrayList(u8),
    labels: std.StringHashMap(u32),
    fixups: std.ArrayList(Fixup),
    entry: u32,
    entry_name: ?[]const u8,
    section: Section,
    bss_size: u32,

    const FixupKind = enum { branch16, branch8, abs16 };

    const Fixup = struct {
        kind: FixupKind,
        code_index: usize,
        label: []const u8,
    };

    fn init(gpa: std.mem.Allocator) Assembler {
        return .{
            .gpa = gpa,
            .code = .empty,
            .rodata = .empty,
            .labels = std.StringHashMap(u32).init(gpa),
            .fixups = .empty,
            .entry = 0,
            .entry_name = null,
            .section = .text,
            .bss_size = 0,
        };
    }

    fn deinit(self: *Assembler) void {
        var it = self.labels.iterator();
        while (it.next()) |e| self.gpa.free(e.key_ptr.*);
        self.labels.deinit();
        for (self.fixups.items) |f| self.gpa.free(f.label);
        self.fixups.deinit(self.gpa);
        self.code.deinit(self.gpa);
        self.rodata.deinit(self.gpa);
        if (self.entry_name) |n| self.gpa.free(n);
    }

    fn assemble(self: *Assembler, src: []const u8) !void {
        var lines = std.mem.splitScalar(u8, src, '\n');
        var line_no: usize = 0;
        while (lines.next()) |raw_line| {
            line_no += 1;
            const line = trimComment(raw_line);
            if (line.len == 0) continue;
            self.parseLine(line) catch |err| {
                std.debug.print("asm error line {d}: {s}\n", .{ line_no, line });
                return err;
            };
        }
        try self.resolveFixups();
        if (self.entry_name) |name| {
            self.entry = self.labels.get(name) orelse return error.MissingEntry;
        }
    }

    fn parseLine(self: *Assembler, line: []const u8) !void {
        var rest = line;
        if (splitLeadingLabel(line)) |parts| {
            try self.defineLabel(parts.name);
            rest = parts.rest;
            if (rest.len == 0) return;
        }

        if (rest.len > 0 and rest[0] == '.') {
            if (self.section == .rodata and isRodataDirective(rest)) {
                return self.parseRodata(rest);
            }
            return self.directive(rest);
        }

        if (self.section == .rodata) {
            return self.parseRodata(rest);
        }
        return self.parseInstr(rest);
    }

    fn splitLeadingLabel(line: []const u8) ?struct { name: []const u8, rest: []const u8 } {
        if (line.len == 0 or line[0] == '.' or line[0] == '"') return null;
        var i: usize = 0;
        while (i < line.len) : (i += 1) {
            const c = line[i];
            const ok = (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or
                (c >= '0' and c <= '9') or c == '_' or c == '.';
            if (!ok) break;
        }
        if (i == 0 or i >= line.len or line[i] != ':') return null;
        return .{
            .name = line[0..i],
            .rest = std.mem.trim(u8, line[i + 1 ..], " \t"),
        };
    }

    fn isRodataDirective(line: []const u8) bool {
        return std.mem.startsWith(u8, line, ".ascii") or
            std.mem.startsWith(u8, line, ".asciz") or
            std.mem.startsWith(u8, line, ".byte") or
            std.mem.startsWith(u8, line, ".word");
    }

    fn directive(self: *Assembler, line: []const u8) !void {
        var it = tokenize(line);
        const dir = it.next() orelse return error.Syntax;
        if (std.mem.eql(u8, dir, ".text")) {
            self.section = .text;
        } else if (std.mem.eql(u8, dir, ".rodata")) {
            self.section = .rodata;
        } else if (std.mem.eql(u8, dir, ".entry")) {
            const name = it.next() orelse return error.Syntax;
            if (self.entry_name) |old| self.gpa.free(old);
            self.entry_name = try self.gpa.dupe(u8, name);
        } else if (std.mem.eql(u8, dir, ".bss")) {
            const n = it.next() orelse return error.Syntax;
            self.bss_size = try std.fmt.parseInt(u32, n, 0);
        } else return error.UnknownDirective;
    }

    fn parseRodata(self: *Assembler, line: []const u8) !void {
        var it = tokenize(line);
        const op = it.next() orelse return;
        if (std.mem.eql(u8, op, ".ascii") or std.mem.eql(u8, op, ".asciz")) {
            const lit = it.next() orelse return error.Syntax;
            const bytes = try parseStringLiteral(self.gpa, lit);
            defer self.gpa.free(bytes);
            try self.rodata.appendSlice(self.gpa, bytes);
            if (std.mem.eql(u8, op, ".asciz")) try self.rodata.append(self.gpa, 0);
        } else if (std.mem.eql(u8, op, ".byte")) {
            while (it.next()) |tok| {
                const v = try std.fmt.parseInt(u8, tok, 0);
                try self.rodata.append(self.gpa, v);
            }
        } else if (std.mem.eql(u8, op, ".word")) {
            while (it.next()) |tok| {
                const v = try std.fmt.parseInt(u32, tok, 0);
                var buf: [4]u8 = undefined;
                std.mem.writeInt(u32, &buf, v, .little);
                try self.rodata.appendSlice(self.gpa, &buf);
            }
        } else return error.UnknownRodata;
    }

    fn parseInstr(self: *Assembler, line: []const u8) !void {
        var it = tokenize(line);
        const mnem = it.next() orelse return;

        if (std.mem.eql(u8, mnem, "add")) return self.emitR(.add, &it);
        if (std.mem.eql(u8, mnem, "sub")) return self.emitR(.sub, &it);
        if (std.mem.eql(u8, mnem, "mul")) return self.emitR(.mul, &it);
        if (std.mem.eql(u8, mnem, "and")) return self.emitR(.@"and", &it);
        if (std.mem.eql(u8, mnem, "or")) return self.emitR(.@"or", &it);
        if (std.mem.eql(u8, mnem, "xor")) return self.emitR(.xor, &it);
        if (std.mem.eql(u8, mnem, "shl")) return self.emitR(.shl, &it);
        if (std.mem.eql(u8, mnem, "shr")) return self.emitR(.shr, &it);
        if (std.mem.eql(u8, mnem, "mov")) {
            const rd = try parseReg(it.next() orelse return error.Syntax);
            const rs = try parseReg(it.next() orelse return error.Syntax);
            try self.emit(isa.encode(.mov, rd, rs, 0));
            return;
        }
        if (std.mem.eql(u8, mnem, "li") or std.mem.eql(u8, mnem, "lih") or std.mem.eql(u8, mnem, "li32")) {
            const rd = try parseReg(it.next() orelse return error.Syntax);
            const imm_tok = it.next() orelse return error.Syntax;
            if (std.mem.eql(u8, mnem, "li32")) {
                const imm = try std.fmt.parseInt(u32, imm_tok, 0);
                const lo = isa.splitImm16(@truncate(imm));
                const hi = isa.splitImm16(@truncate(imm >> 16));
                try self.emit(isa.encode(.lih, rd, hi.b, hi.c));
                // OR with low half via scratch r29 if needed.
                if (lo.b != 0 or lo.c != 0) {
                    try self.emit(isa.encode(.li, 29, lo.b, lo.c));
                    try self.emit(isa.encode(.@"or", rd, rd, 29));
                }
                return;
            }
            if (isIdent(imm_tok)) {
                if (!std.mem.eql(u8, mnem, "li")) return error.LabelNeedsLi;
                const idx = self.code.items.len;
                try self.emit(isa.encode(.li, rd, 0, 0));
                try self.fixups.append(self.gpa, .{
                    .kind = .abs16,
                    .code_index = idx,
                    .label = try self.gpa.dupe(u8, imm_tok),
                });
            } else {
                const imm = try std.fmt.parseInt(u32, imm_tok, 0);
                if (imm > 0xffff) return error.ImmTooLarge;
                const parts = isa.splitImm16(@intCast(imm));
                const op: isa.Op = if (std.mem.eql(u8, mnem, "lih")) .lih else .li;
                try self.emit(isa.encode(op, rd, parts.b, parts.c));
            }
            return;
        }
        if (std.mem.eql(u8, mnem, "ld") or std.mem.eql(u8, mnem, "ldb")) {
            const op: isa.Op = if (std.mem.eql(u8, mnem, "ld")) .ld else .ldb;
            const rd = try parseReg(it.next() orelse return error.Syntax);
            const base = try parseReg(it.next() orelse return error.Syntax);
            const idx = try parseReg(it.next() orelse return error.Syntax);
            try self.emit(isa.encode(op, rd, base, idx));
            return;
        }
        if (std.mem.eql(u8, mnem, "st") or std.mem.eql(u8, mnem, "stb")) {
            const op: isa.Op = if (std.mem.eql(u8, mnem, "st")) .st else .stb;
            const rs = try parseReg(it.next() orelse return error.Syntax);
            const base = try parseReg(it.next() orelse return error.Syntax);
            const idx = try parseReg(it.next() orelse return error.Syntax);
            try self.emit(isa.encode(op, rs, base, idx));
            return;
        }
        if (std.mem.eql(u8, mnem, "b")) {
            const target = it.next() orelse return error.Syntax;
            const idx = self.code.items.len;
            try self.emit(isa.encode(.b, 0, 0, 0));
            try self.fixups.append(self.gpa, .{
                .kind = .branch16,
                .code_index = idx,
                .label = try self.gpa.dupe(u8, target),
            });
            return;
        }
        if (std.mem.eql(u8, mnem, "beq") or std.mem.eql(u8, mnem, "bne")) {
            const op: isa.Op = if (std.mem.eql(u8, mnem, "beq")) .beq else .bne;
            const rs1 = try parseReg(it.next() orelse return error.Syntax);
            const rs2 = try parseReg(it.next() orelse return error.Syntax);
            const target = it.next() orelse return error.Syntax;
            const idx = self.code.items.len;
            try self.emit(isa.encode(op, rs1, rs2, 0));
            try self.fixups.append(self.gpa, .{
                .kind = .branch8,
                .code_index = idx,
                .label = try self.gpa.dupe(u8, target),
            });
            return;
        }
        if (std.mem.eql(u8, mnem, "jal")) {
            const rd = try parseReg(it.next() orelse return error.Syntax);
            const target = it.next() orelse return error.Syntax;
            const idx = self.code.items.len;
            try self.emit(isa.encode(.jal, rd, 0, 0));
            try self.fixups.append(self.gpa, .{
                .kind = .branch16,
                .code_index = idx,
                .label = try self.gpa.dupe(u8, target),
            });
            return;
        }
        if (std.mem.eql(u8, mnem, "ret")) {
            const rs = try parseReg(it.next() orelse return error.Syntax);
            try self.emit(isa.encode(.ret, rs, 0, 0));
            return;
        }
        if (std.mem.eql(u8, mnem, "svc")) {
            const imm_tok = it.next() orelse return error.Syntax;
            const imm = try std.fmt.parseInt(u8, imm_tok, 0);
            try self.emit(isa.encode(.svc, 0, 0, imm));
            return;
        }
        if (std.mem.eql(u8, mnem, "nop")) {
            try self.emit(isa.encode(.mov, 0, 0, 0));
            return;
        }
        return error.UnknownMnemonic;
    }

    fn emitR(self: *Assembler, op: isa.Op, it: *TokenIt) !void {
        const rd = try parseReg(it.next() orelse return error.Syntax);
        const rs1 = try parseReg(it.next() orelse return error.Syntax);
        const rs2 = try parseReg(it.next() orelse return error.Syntax);
        try self.emit(isa.encode(op, rd, rs1, rs2));
    }

    fn emit(self: *Assembler, word: u32) !void {
        try self.code.append(self.gpa, word);
    }

    fn defineLabel(self: *Assembler, name: []const u8) !void {
        const addr: u32 = switch (self.section) {
            .text => @intCast(self.code.items.len * 4),
            .rodata => @intCast(self.codeByteSize() + self.rodata.items.len),
        };
        const key = try self.gpa.dupe(u8, name);
        const gop = try self.labels.getOrPut(key);
        if (gop.found_existing) {
            self.gpa.free(key);
            return error.DuplicateLabel;
        }
        gop.value_ptr.* = addr;
    }

    fn codeByteSize(self: *Assembler) u32 {
        return @intCast(self.code.items.len * 4);
    }

    fn resolveFixups(self: *Assembler) !void {
        for (self.fixups.items) |f| {
            const target = self.labels.get(f.label) orelse return error.UndefinedLabel;
            const here: i32 = @intCast((f.code_index + 1) * 4);
            const delta: i32 = @as(i32, @intCast(target)) - here;
            var word = self.code.items[f.code_index];
            const parts = isa.decode(word);
            switch (f.kind) {
                .branch16 => {
                    if (delta < -32768 or delta > 32767) return error.BranchTooFar;
                    const u: u16 = @bitCast(@as(i16, @intCast(delta)));
                    const s = isa.splitImm16(u);
                    word = isa.encode(@enumFromInt(parts.op), parts.a, s.b, s.c);
                },
                .branch8 => {
                    if (delta < -128 or delta > 127) return error.BranchTooFar;
                    const u: u8 = @bitCast(@as(i8, @intCast(delta)));
                    word = isa.encode(@enumFromInt(parts.op), parts.a, parts.b, u);
                },
                .abs16 => {
                    if (target > 0xffff) return error.AddrTooLarge;
                    const s = isa.splitImm16(@intCast(target));
                    word = isa.encode(.li, parts.a, s.b, s.c);
                },
            }
            self.code.items[f.code_index] = word;
        }
    }

    fn emitSox(self: *Assembler, gpa: std.mem.Allocator) ![]u8 {
        const code_bytes = self.codeByteSize();
        const ro_bytes: u32 = @intCast(self.rodata.items.len);
        const total = isa.SoxHeader.size + code_bytes + ro_bytes;
        var out = try gpa.alloc(u8, total);
        @memset(out, 0);

        var hdr: isa.SoxHeader = .{
            .magic = isa.SoxHeader.magic_value,
            .version = isa.SoxHeader.current_version,
            .flags = 0,
            .entry = self.entry,
            .code_size = code_bytes,
            .rodata_size = ro_bytes,
            .bss_size = self.bss_size,
            .reserved = 0,
        };
        @memcpy(out[0..isa.SoxHeader.size], std.mem.asBytes(&hdr));

        var off: usize = isa.SoxHeader.size;
        for (self.code.items) |w| {
            std.mem.writeInt(u32, out[off..][0..4], w, .little);
            off += 4;
        }
        @memcpy(out[off .. off + self.rodata.items.len], self.rodata.items);
        return out;
    }
};

const TokenIt = struct {
    buf: []const u8,
    fn next(self: *TokenIt) ?[]const u8 {
        self.buf = std.mem.trimStart(u8, self.buf, " \t,");
        if (self.buf.len == 0) return null;
        if (self.buf[0] == '"') {
            var i: usize = 1;
            while (i < self.buf.len) : (i += 1) {
                if (self.buf[i] == '"' and self.buf[i - 1] != '\\') {
                    const tok = self.buf[0 .. i + 1];
                    self.buf = self.buf[i + 1 ..];
                    return tok;
                }
            }
            const tok = self.buf;
            self.buf = &.{};
            return tok;
        }
        var i: usize = 0;
        while (i < self.buf.len and self.buf[i] != ' ' and self.buf[i] != '\t' and self.buf[i] != ',') : (i += 1) {}
        const tok = self.buf[0..i];
        self.buf = self.buf[i..];
        return tok;
    }
};

fn tokenize(line: []const u8) TokenIt {
    return .{ .buf = line };
}

fn trimComment(line: []const u8) []const u8 {
    var s = std.mem.trim(u8, line, " \t\r");
    if (std.mem.indexOfScalar(u8, s, ';')) |i| {
        s = std.mem.trimEnd(u8, s[0..i], " \t");
    }
    return s;
}

fn parseReg(tok: []const u8) !u8 {
    if (tok.len < 2 or tok[0] != 'r') return error.BadReg;
    const n = try std.fmt.parseInt(u8, tok[1..], 10);
    if (n > 31) return error.BadReg;
    return n;
}

fn isIdent(tok: []const u8) bool {
    if (tok.len == 0) return false;
    if (tok[0] >= '0' and tok[0] <= '9') return false;
    if (tok[0] == '-' or tok[0] == '+') return false;
    if (std.mem.startsWith(u8, tok, "0x") or std.mem.startsWith(u8, tok, "0X")) return false;
    return true;
}

fn parseStringLiteral(gpa: std.mem.Allocator, lit: []const u8) ![]u8 {
    if (lit.len < 2 or lit[0] != '"' or lit[lit.len - 1] != '"') return error.BadString;
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);
    var i: usize = 1;
    while (i + 1 < lit.len) : (i += 1) {
        const c = lit[i];
        if (c == '\\') {
            i += 1;
            if (i + 1 >= lit.len) return error.BadString;
            const e = lit[i];
            const b: u8 = switch (e) {
                'n' => '\n',
                't' => '\t',
                '0' => 0,
                '\\' => '\\',
                '"' => '"',
                else => return error.BadEscape,
            };
            try out.append(gpa, b);
        } else {
            try out.append(gpa, c);
        }
    }
    return out.toOwnedSlice(gpa);
}
