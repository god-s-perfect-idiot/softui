//! SoftShell — SoftUI CLI with SoftFS manipulation + kernel surface + demos.

const std = @import("std");
const console_mod = @import("console.zig");
const input = @import("input.zig");
const softfs = @import("softfs.zig");

pub const Mode = enum { shell, donut, plasma, stars, cube, fire };

pub const KernelInfo = struct {
    frame: u32 = 0,
    boot_ns: u64 = 0,
    fb_w: u32 = 0,
    fb_h: u32 = 0,
    fb_stride: u32 = 0,
    boot_mode: u32 = 0,
    alloc_used: u32 = 0,
    alloc_cap: u32 = 0,
    disk_len: u32 = 0,
    disk_cap: u32 = 0,
    process_arena: u32 = 0,
};

pub const SoftShell = struct {
    cons: console_mod.Console = .{},
    mode: Mode = .shell,
    line: [240]u8 = undefined,
    line_len: usize = 0,
    prompt_buf: [96]u8 = undefined,
    prompt_len: usize = 8,
    ready: bool = false,
    fs: ?*softfs.Fs = null,
    frame: u32 = 0,
    kinfo: KernelInfo = .{},
    on_donut: ?*const fn (phase_a: u32, phase_b: u32) void = null,
    on_plasma: ?*const fn (phase: u32) void = null,
    on_stars: ?*const fn (phase: u32) void = null,
    on_cube: ?*const fn (phase: u32) void = null,
    on_fire: ?*const fn (phase: u32) void = null,
    on_run_sox: ?*const fn (name: []const u8) void = null,
    on_fb_fill: ?*const fn (x: u32, y: u32, w: u32, h: u32, color: u32) void = null,
    on_reboot_shell: ?*const fn () void = null,
    on_refresh_kinfo: ?*const fn (*KernelInfo) void = null,

    pub fn start(self: *SoftShell, fb_w: u32, fb_h: u32, fs: ?*softfs.Fs) void {
        self.cons.init(fb_w, fb_h);
        self.fs = fs;
        self.kinfo.fb_w = fb_w;
        self.kinfo.fb_h = fb_h;
        self.line_len = 0;
        self.mode = .shell;
        self.ready = true;
        self.cons.write("SoftUI kernel - SoftShell CLI\n");
        self.cons.write("Type 'help' or 'help fs' / 'help kernel'.\n\n");
        self.updatePrompt();
        self.refreshInput();
    }

    fn prompt(self: *const SoftShell) []const u8 {
        return self.prompt_buf[0..self.prompt_len];
    }

    fn updatePrompt(self: *SoftShell) void {
        var path_buf: [64]u8 = undefined;
        const path = if (self.fs) |f| f.cwdPath(&path_buf) else "/";
        const prefix = "softui:";
        var i: usize = 0;
        for (prefix) |c| {
            if (i >= self.prompt_buf.len) break;
            self.prompt_buf[i] = c;
            i += 1;
        }
        const plen = @min(path.len, self.prompt_buf.len - i - 2);
        @memcpy(self.prompt_buf[i .. i + plen], path[0..plen]);
        i += plen;
        if (i + 2 <= self.prompt_buf.len) {
            self.prompt_buf[i] = '>';
            self.prompt_buf[i + 1] = ' ';
            i += 2;
        }
        self.prompt_len = i;
    }

    pub fn refreshInput(self: *SoftShell) void {
        self.cons.setInputLine(self.prompt(), self.line[0..self.line_len]);
    }

    pub fn tick(self: *SoftShell, frame: u32) void {
        if (!self.ready) return;
        self.frame = frame;
        self.kinfo.frame = frame;
        while (input.pop()) |ev| self.handleKey(ev);
        if (self.mode == .shell) self.cons.tickBlink();
    }

    pub fn draw(self: *SoftShell, fb: []u8, width: u32, height: u32, stride: u32) void {
        if (!self.ready) return;
        switch (self.mode) {
            .shell => self.cons.draw(fb, width, height, stride, true),
            .donut => if (self.on_donut) |d| d(self.frame *% 7, self.frame *% 5),
            .plasma => if (self.on_plasma) |d| d(self.frame),
            .stars => if (self.on_stars) |d| d(self.frame),
            .cube => if (self.on_cube) |d| d(self.frame *% 3),
            .fire => if (self.on_fire) |d| d(self.frame),
        }
    }

    fn handleKey(self: *SoftShell, ev: input.Event) void {
        if (self.mode != .shell) {
            self.mode = .shell;
            self.cons.write("\n(back to SoftShell)\n");
            self.refreshInput();
            return;
        }
        const key = ev.key;
        if (key == input.KEY_ENTER) {
            self.cons.writeChar('\n');
            self.execLine(self.line[0..self.line_len]);
            self.line_len = 0;
            self.updatePrompt();
            self.refreshInput();
            return;
        }
        if (key == input.KEY_BACKSPACE) {
            if (self.line_len > 0) {
                self.line_len -= 1;
                self.refreshInput();
            }
            return;
        }
        if (key == input.KEY_ESCAPE) {
            self.line_len = 0;
            self.refreshInput();
            return;
        }
        if (key >= 32 and key < 127) {
            if (self.line_len + 1 < self.line.len) {
                self.line[self.line_len] = @truncate(key);
                self.line_len += 1;
                self.refreshInput();
            }
        }
    }

    fn execLine(self: *SoftShell, raw: []const u8) void {
        const line = trim(raw);
        if (line.len == 0) return;
        var rest = line;
        while (rest.len > 0) {
            const semi = std.mem.indexOfScalar(u8, rest, ';');
            const piece = if (semi) |s| trim(rest[0..s]) else rest;
            rest = if (semi) |s| trim(rest[s + 1 ..]) else "";
            if (piece.len == 0) continue;
            self.execOne(piece);
        }
    }

    fn execOne(self: *SoftShell, line: []const u8) void {
        var argv: [12][]const u8 = undefined;
        const argc = tokenize(line, &argv);
        if (argc == 0) return;
        const cmd = argv[0];

        if (eql(cmd, "help")) return self.cmdHelp(if (argc > 1) argv[1] else "");
        if (eql(cmd, "echo")) return self.cmdEcho(argv[1..argc]);
        if (eql(cmd, "clear")) {
            self.cons.clear();
            return;
        }
        if (eql(cmd, "info") or eql(cmd, "uname")) return self.cmdInfo();
        if (eql(cmd, "pwd")) return self.cmdPwd();
        if (eql(cmd, "cd")) return self.cmdCd(if (argc > 1) argv[1] else "/");
        if (eql(cmd, "ls")) return self.cmdLs(if (argc > 1) argv[1] else ".");
        if (eql(cmd, "tree")) return self.cmdTree(if (argc > 1) argv[1] else ".");
        if (eql(cmd, "cat")) {
            if (argc < 2) return self.err("usage: cat <path>");
            return self.cmdCat(argv[1]);
        }
        if (eql(cmd, "hexdump") or eql(cmd, "hd")) {
            if (argc < 2) return self.err("usage: hexdump <path>");
            return self.cmdHex(argv[1]);
        }
        if (eql(cmd, "stat")) {
            if (argc < 2) return self.err("usage: stat <path>");
            return self.cmdStat(argv[1]);
        }
        if (eql(cmd, "touch")) {
            if (argc < 2) return self.err("usage: touch <path>");
            return self.cmdTouch(argv[1]);
        }
        if (eql(cmd, "mkdir")) {
            if (argc < 2) return self.err("usage: mkdir <path>");
            return self.cmdMkdir(argv[1]);
        }
        if (eql(cmd, "rm")) {
            if (argc < 2) return self.err("usage: rm <path>");
            return self.cmdRm(argv[1]);
        }
        if (eql(cmd, "rmdir")) {
            if (argc < 2) return self.err("usage: rmdir <path>");
            return self.cmdRmdir(argv[1]);
        }
        if (eql(cmd, "mv")) {
            if (argc < 3) return self.err("usage: mv <src> <dst>");
            return self.cmdMv(argv[1], argv[2]);
        }
        if (eql(cmd, "cp")) {
            if (argc < 3) return self.err("usage: cp <src> <dst>");
            return self.cmdCp(argv[1], argv[2]);
        }
        if (eql(cmd, "write") or eql(cmd, "printf")) {
            if (argc < 3) return self.err("usage: write <path> <text...>");
            return self.cmdWrite(argv[1], argv[2..argc], false);
        }
        if (eql(cmd, "append")) {
            if (argc < 3) return self.err("usage: append <path> <text...>");
            return self.cmdWrite(argv[1], argv[2..argc], true);
        }
        if (eql(cmd, "df")) return self.cmdDf();
        if (eql(cmd, "wc")) {
            if (argc < 2) return self.err("usage: wc <path>");
            return self.cmdWc(argv[1]);
        }

        if (eql(cmd, "donut")) {
            self.cons.write("donut demo - press any key to return\n");
            self.mode = .donut;
            return;
        }
        if (eql(cmd, "plasma")) {
            self.cons.write("plasma demo - press any key to return\n");
            self.mode = .plasma;
            return;
        }
        if (eql(cmd, "stars")) {
            self.cons.write("stars demo - press any key to return\n");
            self.mode = .stars;
            return;
        }
        if (eql(cmd, "cube")) {
            self.cons.write("cube demo - press any key to return\n");
            self.mode = .cube;
            return;
        }
        if (eql(cmd, "fire")) {
            self.cons.write("fire demo - press any key to return\n");
            self.mode = .fire;
            return;
        }
        if (eql(cmd, "run")) {
            if (argc < 2) return self.err("usage: run <file.sox>");
            if (self.on_run_sox) |r| r(argv[1]) else self.err("run not wired");
            return;
        }

        if (eql(cmd, "kinfo") or eql(cmd, "sysinfo")) return self.cmdKinfo();
        if (eql(cmd, "mem")) return self.cmdMem();
        if (eql(cmd, "ticks")) {
            self.cons.write("frame ");
            self.writeU32(self.frame);
            self.cons.write("\n");
            return;
        }
        if (eql(cmd, "svc")) return self.cmdSvc();
        if (eql(cmd, "fb")) return self.cmdFb(argv[1..argc]);
        if (eql(cmd, "reboot")) {
            if (self.on_reboot_shell) |r| r();
            self.cons.write("shell reinitialized\n");
            return;
        }
        if (eql(cmd, "capabilities") or eql(cmd, "caps")) return self.cmdCaps();

        self.cons.write("unknown: ");
        self.cons.write(cmd);
        self.cons.write(" (try help)\n");
    }

    fn cmdHelp(self: *SoftShell, topic: []const u8) void {
        if (eql(topic, "fs")) {
            self.cons.write("Filesystem:\n");
            self.cons.write("  pwd cd ls tree cat hexdump|hd stat wc df\n");
            self.cons.write("  touch mkdir rm rmdir mv cp\n");
            self.cons.write("  write|printf <path> <text...>  append ...\n");
            self.cons.write("  Chain: mkdir a; cd a; touch f\n");
            return;
        }
        if (eql(topic, "kernel") or eql(topic, "k")) {
            self.cons.write("Kernel surface:\n");
            self.cons.write("  kinfo|sysinfo mem ticks svc reboot caps\n");
            self.cons.write("  fb clear <color> | fb fill x y w h color\n");
            self.cons.write("  demos: donut plasma stars cube fire\n");
            self.cons.write("  run <file.sox>\n");
            return;
        }
        self.cons.write("SoftShell - help [fs|kernel|capabilities]\n");
        self.cons.write("  fs: pwd cd ls tree cat touch mkdir rm mv cp write df\n");
        self.cons.write("  k:  kinfo mem ticks svc fb reboot run caps\n");
        self.cons.write("  demos: donut plasma stars cube fire\n");
    }

    fn cmdCaps(self: *SoftShell) void {
        self.cons.write("Full catalog: docs/softshell.md\n");
        self.cons.write("Shipped: SoftFS CRUD+dirs, fb poke, kinfo/mem,\n");
        self.cons.write("  demos, SoftASM run, ';' chaining.\n");
        self.cons.write("Planned: scripts/vars/pipes, disk sync, net,\n");
        self.cons.write("  sched/proc, SoftASM debug, peek/poke.\n");
    }

    fn cmdEcho(self: *SoftShell, args: []const []const u8) void {
        var i: usize = 0;
        while (i < args.len) : (i += 1) {
            if (i > 0) self.cons.write(" ");
            self.cons.write(args[i]);
        }
        self.cons.write("\n");
    }

    fn cmdInfo(self: *SoftShell) void {
        self.cons.write("SoftUI guest OS / SoftShell\n");
        self.cons.write("framebuffer ");
        self.writeU32(self.kinfo.fb_w);
        self.cons.write("x");
        self.writeU32(self.kinfo.fb_h);
        self.cons.write("\nrenderer: SoftUI glyphs (no host text)\n");
    }

    fn requireFs(self: *SoftShell) ?*softfs.Fs {
        return self.fs orelse {
            self.err("SoftFS not mounted");
            return null;
        };
    }

    fn cmdPwd(self: *SoftShell) void {
        const fs = self.requireFs() orelse return;
        var buf: [96]u8 = undefined;
        self.cons.write(fs.cwdPath(&buf));
        self.cons.write("\n");
    }

    fn cmdCd(self: *SoftShell, path: []const u8) void {
        const fs = self.requireFs() orelse return;
        const idx = fs.resolve(path) orelse return self.err("no such path");
        if (fs.nodes[idx].kind != .dir) return self.err("not a directory");
        fs.cwd = idx;
    }

    fn cmdLs(self: *SoftShell, path: []const u8) void {
        const fs = self.requireFs() orelse return;
        const idx = fs.resolve(path) orelse return self.err("no such path");
        if (fs.nodes[idx].kind != .dir) {
            self.cons.write("  ");
            self.cons.write(fs.nameOf(idx));
            self.cons.write("\n");
            return;
        }
        var i: u16 = 0;
        var any = false;
        while (i < softfs.MAX_NODES) : (i += 1) {
            if (!fs.nodes[i].used or fs.nodes[i].parent != idx or i == softfs.ROOT) continue;
            any = true;
            self.cons.write("  ");
            if (fs.nodes[i].kind == .dir) {
                self.cons.write("[dir] ");
            } else {
                self.cons.write("[file] ");
            }
            self.cons.write(fs.nameOf(i));
            if (fs.nodes[i].kind == .file) {
                self.cons.write(" ");
                self.writeU32(fs.nodes[i].data_len);
                self.cons.write("b");
            }
            self.cons.write("\n");
        }
        if (!any) self.cons.write("(empty)\n");
    }

    fn cmdTree(self: *SoftShell, path: []const u8) void {
        const fs = self.requireFs() orelse return;
        const idx = fs.resolve(path) orelse return self.err("no such path");
        self.treeWalk(fs, idx, 0);
    }

    fn treeWalk(self: *SoftShell, fs: *softfs.Fs, idx: u16, depth: u32) void {
        if (depth > 8) return;
        var pad: u32 = 0;
        while (pad < depth) : (pad += 1) self.cons.write("  ");
        if (idx == softfs.ROOT) {
            self.cons.write("/\n");
        } else {
            self.cons.write(fs.nameOf(idx));
            if (fs.nodes[idx].kind == .dir) self.cons.write("/");
            self.cons.write("\n");
        }
        if (fs.nodes[idx].kind != .dir) return;
        var i: u16 = 0;
        while (i < softfs.MAX_NODES) : (i += 1) {
            if (!fs.nodes[i].used or fs.nodes[i].parent != idx or i == softfs.ROOT) continue;
            self.treeWalk(fs, i, depth + 1);
        }
    }

    fn cmdCat(self: *SoftShell, path: []const u8) void {
        const fs = self.requireFs() orelse return;
        const idx = fs.resolve(path) orelse return self.err("not found");
        const data = fs.fileData(idx) orelse return self.err("not a file");
        const n = @min(data.len, @as(usize, 1024));
        if (n > 0) self.cons.write(data[0..n]);
        if (n == 0 or data[n - 1] != '\n') self.cons.write("\n");
        if (data.len > n) self.cons.write("...(truncated)\n");
    }

    fn cmdHex(self: *SoftShell, path: []const u8) void {
        const fs = self.requireFs() orelse return;
        const idx = fs.resolve(path) orelse return self.err("not found");
        const data = fs.fileData(idx) orelse return self.err("not a file");
        const n = @min(data.len, @as(usize, 64));
        var i: usize = 0;
        while (i < n) : (i += 1) {
            self.writeHexByte(data[i]);
            self.cons.write(if ((i + 1) % 8 == 0) "\n" else " ");
        }
        if (n % 8 != 0) self.cons.write("\n");
        if (data.len > n) self.cons.write("...(truncated)\n");
    }

    fn cmdStat(self: *SoftShell, path: []const u8) void {
        const fs = self.requireFs() orelse return;
        const idx = fs.resolve(path) orelse return self.err("not found");
        const n = &fs.nodes[idx];
        self.cons.write("name ");
        self.cons.write(fs.nameOf(idx));
        self.cons.write("\nkind ");
        self.cons.write(if (n.kind == .dir) "dir\n" else "file\n");
        self.cons.write("node ");
        self.writeU32(idx);
        self.cons.write(" parent ");
        self.writeU32(n.parent);
        self.cons.write("\n");
        if (n.kind == .file) {
            self.cons.write("size ");
            self.writeU32(n.data_len);
            self.cons.write("\n");
        } else {
            self.cons.write("children ");
            self.writeU32(fs.childCount(idx));
            self.cons.write("\n");
        }
    }

    fn cmdTouch(self: *SoftShell, path: []const u8) void {
        const fs = self.requireFs() orelse return;
        if (fs.resolve(path)) |idx| {
            if (fs.nodes[idx].kind != .file) return self.err("exists (not file)");
            return;
        }
        const pp = fs.resolveParent(path) orelse return self.err("bad path");
        _ = fs.createFile(pp.parent, pp.name, &.{}) catch |e| return self.fsErr(e);
    }

    fn cmdMkdir(self: *SoftShell, path: []const u8) void {
        const fs = self.requireFs() orelse return;
        if (fs.resolve(path) != null) return self.err("exists");
        const pp = fs.resolveParent(path) orelse return self.err("bad path");
        _ = fs.mkdir(pp.parent, pp.name) catch |e| return self.fsErr(e);
    }

    fn cmdRm(self: *SoftShell, path: []const u8) void {
        const fs = self.requireFs() orelse return;
        const idx = fs.resolve(path) orelse return self.err("not found");
        if (fs.nodes[idx].kind == .dir) return self.err("is directory (use rmdir)");
        fs.unlink(idx) catch |e| return self.fsErr(e);
    }

    fn cmdRmdir(self: *SoftShell, path: []const u8) void {
        const fs = self.requireFs() orelse return;
        const idx = fs.resolve(path) orelse return self.err("not found");
        if (fs.nodes[idx].kind != .dir) return self.err("not a directory");
        fs.unlink(idx) catch |e| return self.fsErr(e);
    }

    fn cmdMv(self: *SoftShell, src: []const u8, dst: []const u8) void {
        const fs = self.requireFs() orelse return;
        const sidx = fs.resolve(src) orelse return self.err("src not found");
        if (fs.resolve(dst) != null) return self.err("dst exists");
        const pp = fs.resolveParent(dst) orelse return self.err("bad dst");
        fs.rename(sidx, pp.parent, pp.name) catch |e| return self.fsErr(e);
    }

    fn cmdCp(self: *SoftShell, src: []const u8, dst: []const u8) void {
        const fs = self.requireFs() orelse return;
        const sidx = fs.resolve(src) orelse return self.err("src not found");
        if (fs.nodes[sidx].kind != .file) return self.err("src not a file");
        if (fs.resolve(dst) != null) return self.err("dst exists");
        const pp = fs.resolveParent(dst) orelse return self.err("bad dst");
        _ = fs.copyFile(sidx, pp.parent, pp.name) catch |e| return self.fsErr(e);
    }

    fn cmdWrite(self: *SoftShell, path: []const u8, words: []const []const u8, append: bool) void {
        const fs = self.requireFs() orelse return;
        var text_buf: [200]u8 = undefined;
        var tlen: usize = 0;
        var i: usize = 0;
        while (i < words.len) : (i += 1) {
            if (i > 0 and tlen < text_buf.len) {
                text_buf[tlen] = ' ';
                tlen += 1;
            }
            const w = words[i];
            const n = @min(w.len, text_buf.len - tlen);
            @memcpy(text_buf[tlen .. tlen + n], w[0..n]);
            tlen += n;
        }
        if (tlen < text_buf.len) {
            text_buf[tlen] = '\n';
            tlen += 1;
        }
        const text = text_buf[0..tlen];
        if (fs.resolve(path)) |idx| {
            if (fs.nodes[idx].kind != .file) return self.err("not a file");
            fs.writeFile(idx, text, append) catch |e| return self.fsErr(e);
        } else {
            const pp = fs.resolveParent(path) orelse return self.err("bad path");
            const idx = fs.createFile(pp.parent, pp.name, &.{}) catch |e| return self.fsErr(e);
            fs.writeFile(idx, text, false) catch |e| return self.fsErr(e);
        }
    }

    fn cmdDf(self: *SoftShell) void {
        const fs = self.requireFs() orelse return;
        const d = fs.df();
        self.cons.write("nodes ");
        self.writeU32(d.nodes_used);
        self.cons.write("/");
        self.writeU32(d.nodes_max);
        self.cons.write("  heap ");
        self.writeU32(d.heap_used);
        self.cons.write("/");
        self.writeU32(d.heap_max);
        self.cons.write("\n");
    }

    fn cmdWc(self: *SoftShell, path: []const u8) void {
        const fs = self.requireFs() orelse return;
        const idx = fs.resolve(path) orelse return self.err("not found");
        const data = fs.fileData(idx) orelse return self.err("not a file");
        var lines: u32 = 0;
        var words: u32 = 0;
        var in_word = false;
        for (data) |c| {
            if (c == '\n') lines += 1;
            const sp = c == ' ' or c == '\t' or c == '\n' or c == '\r';
            if (sp) {
                in_word = false;
            } else if (!in_word) {
                in_word = true;
                words += 1;
            }
        }
        self.writeU32(lines);
        self.cons.write(" ");
        self.writeU32(words);
        self.cons.write(" ");
        self.writeU32(@intCast(data.len));
        self.cons.write(" ");
        self.cons.write(path);
        self.cons.write("\n");
    }

    fn cmdKinfo(self: *SoftShell) void {
        if (self.on_refresh_kinfo) |r| r(&self.kinfo);
        self.cons.write("SoftUI kernel\n");
        self.cons.write("frame ");
        self.writeU32(self.kinfo.frame);
        self.cons.write(" boot_mode ");
        self.writeU32(self.kinfo.boot_mode);
        self.cons.write("\nfb ");
        self.writeU32(self.kinfo.fb_w);
        self.cons.write("x");
        self.writeU32(self.kinfo.fb_h);
        self.cons.write(" stride ");
        self.writeU32(self.kinfo.fb_stride);
        self.cons.write("\n");
    }

    fn cmdMem(self: *SoftShell) void {
        if (self.on_refresh_kinfo) |r| r(&self.kinfo);
        self.cons.write("alloc ");
        self.writeU32(self.kinfo.alloc_used);
        self.cons.write("/");
        self.writeU32(self.kinfo.alloc_cap);
        self.cons.write("\ndisk ");
        self.writeU32(self.kinfo.disk_len);
        self.cons.write("/");
        self.writeU32(self.kinfo.disk_cap);
        self.cons.write("\nprocess_arena ");
        self.writeU32(self.kinfo.process_arena);
        self.cons.write("\n");
        if (self.fs) |fs| {
            const d = fs.df();
            self.cons.write("softfs heap ");
            self.writeU32(d.heap_used);
            self.cons.write("/");
            self.writeU32(d.heap_max);
            self.cons.write("\n");
        }
    }

    fn cmdSvc(self: *SoftShell) void {
        self.cons.write("SoftASM svc codes:\n");
        self.cons.write("  1 write  2 exit  3 yield\n");
        self.cons.write("  10 fb_fill  11 fb_size  12 get_frame\n");
        self.cons.write("  13 donut  14 plasma  15 stars\n");
        self.cons.write("  16 cube   17 fire\n");
    }

    fn cmdFb(self: *SoftShell, args: []const []const u8) void {
        if (args.len == 0) return self.err("usage: fb clear|fill ...");
        if (eql(args[0], "clear")) {
            const color: u32 = if (args.len > 1) parseU32(args[1]) orelse 0xFF0B0E12 else 0xFF0B0E12;
            if (self.on_fb_fill) |f| f(0, 0, self.kinfo.fb_w, self.kinfo.fb_h, color);
            self.cons.write("(fb cleared - shell redraw may override)\n");
            return;
        }
        if (eql(args[0], "fill")) {
            if (args.len < 6) return self.err("usage: fb fill x y w h color");
            const x = parseU32(args[1]) orelse return self.err("bad x");
            const y = parseU32(args[2]) orelse return self.err("bad y");
            const w = parseU32(args[3]) orelse return self.err("bad w");
            const h = parseU32(args[4]) orelse return self.err("bad h");
            const color = parseU32(args[5]) orelse return self.err("bad color");
            if (self.on_fb_fill) |f| f(x, y, w, h, color);
            self.cons.write("ok\n");
            return;
        }
        self.err("usage: fb clear|fill ...");
    }

    fn err(self: *SoftShell, msg: []const u8) void {
        self.cons.write(msg);
        self.cons.write("\n");
    }

    fn fsErr(self: *SoftShell, e: anyerror) void {
        self.cons.write("fs error: ");
        self.cons.write(@errorName(e));
        self.cons.write("\n");
    }

    fn writeU32(self: *SoftShell, v: u32) void {
        var buf: [10]u8 = undefined;
        var x = v;
        var i: usize = 0;
        if (x == 0) {
            self.cons.write("0");
            return;
        }
        while (x > 0 and i < buf.len) : (i += 1) {
            buf[buf.len - 1 - i] = @truncate('0' + (x % 10));
            x /= 10;
        }
        self.cons.write(buf[buf.len - i ..]);
    }

    fn writeHexByte(self: *SoftShell, b: u8) void {
        const hex = "0123456789abcdef";
        var pair: [2]u8 = .{ hex[b >> 4], hex[b & 0xf] };
        self.cons.write(&pair);
    }
};

fn trim(s: []const u8) []const u8 {
    var a: usize = 0;
    var b: usize = s.len;
    while (a < b and (s[a] == ' ' or s[a] == '\t')) a += 1;
    while (b > a and (s[b - 1] == ' ' or s[b - 1] == '\t')) b -= 1;
    return s[a..b];
}

fn eql(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}

fn tokenize(line: []const u8, out: [][]const u8) usize {
    var n: usize = 0;
    var i: usize = 0;
    while (i < line.len and n < out.len) {
        while (i < line.len and (line[i] == ' ' or line[i] == '\t')) i += 1;
        if (i >= line.len) break;
        const start = i;
        while (i < line.len and line[i] != ' ' and line[i] != '\t') i += 1;
        out[n] = line[start..i];
        n += 1;
    }
    return n;
}

fn parseU32(s: []const u8) ?u32 {
    return std.fmt.parseInt(u32, s, 0) catch null;
}
