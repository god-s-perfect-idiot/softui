const std = @import("std");
const isa = @import("isa");

pub const FbSize = struct { w: u32, h: u32 };

pub const KernelHooks = struct {
    write: *const fn (fd: u32, ptr: u32, len: u32, mem: []u8) void,
    fb_fill: *const fn (x: u32, y: u32, w: u32, h: u32, color: u32) void,
    fb_size: *const fn () FbSize,
    get_frame: *const fn () u32,
    fb_donut: *const fn (phase_a: u32, phase_b: u32) void,
    fb_plasma: *const fn (phase: u32) void,
    fb_stars: *const fn (phase: u32) void,
    fb_cube: *const fn (phase: u32) void,
    fb_fire: *const fn (phase: u32) void,
};

pub const Status = enum {
    running,
    yielded,
    exited,
    fault,
};

pub const Vm = struct {
    regs: [32]u32 = @splat(0),
    pc: u32 = 0,
    mem: []u8 = &.{},
    image_size: u32 = 0,
    status: Status = .running,
    exit_code: u32 = 0,
    fault_reason: []const u8 = "",
    hooks: KernelHooks,

    pub const PROCESS_ARENA = 256 * 1024;
    pub const STACK_SIZE = 16 * 1024;

    pub fn load(sox: []const u8, arena: []u8, hooks: KernelHooks) !Vm {
        if (sox.len < isa.SoxHeader.size) return error.Truncated;
        if (!std.mem.eql(u8, sox[0..4], &isa.SoxHeader.magic_value)) return error.BadMagic;
        const version = std.mem.readInt(u16, sox[4..6], .little);
        if (version != 1) return error.BadVersion;

        const entry = std.mem.readInt(u32, sox[8..12], .little);
        const code_size = std.mem.readInt(u32, sox[12..16], .little);
        const rodata_size = std.mem.readInt(u32, sox[16..20], .little);
        const bss_size = std.mem.readInt(u32, sox[20..24], .little);
        const payload = code_size + rodata_size;
        if (isa.SoxHeader.size + payload > sox.len) return error.Truncated;

        const image_need = payload + bss_size;
        if (image_need + STACK_SIZE > arena.len) return error.OutOfMemory;

        @memset(arena, 0);
        @memcpy(arena[0..payload], sox[isa.SoxHeader.size .. isa.SoxHeader.size + payload]);

        var vm: Vm = .{
            .mem = arena,
            .image_size = image_need,
            .pc = entry,
            .hooks = hooks,
            .status = .running,
        };
        vm.regs[31] = @intCast(arena.len); // sp at top
        return vm;
    }

    pub fn runBudget(self: *Vm, max_ops: u32) void {
        if (self.status != .running and self.status != .yielded) return;
        self.status = .running;
        var ops: u32 = 0;
        while (ops < max_ops and self.status == .running) : (ops += 1) {
            self.step();
        }
    }

    fn step(self: *Vm) void {
        if (self.pc + 4 > self.image_size) {
            self.fault("pc out of bounds");
            return;
        }
        const word = std.mem.readInt(u32, self.mem[self.pc..][0..4], .little);
        const d = isa.decode(word);
        const next = self.pc + 4;
        self.pc = next;

        switch (d.op) {
            @intFromEnum(isa.Op.add) => self.regs[d.a] = self.regs[d.b] +% self.regs[d.c],
            @intFromEnum(isa.Op.sub) => self.regs[d.a] = self.regs[d.b] -% self.regs[d.c],
            @intFromEnum(isa.Op.mul) => self.regs[d.a] = self.regs[d.b] *% self.regs[d.c],
            @intFromEnum(isa.Op.@"and") => self.regs[d.a] = self.regs[d.b] & self.regs[d.c],
            @intFromEnum(isa.Op.@"or") => self.regs[d.a] = self.regs[d.b] | self.regs[d.c],
            @intFromEnum(isa.Op.xor) => self.regs[d.a] = self.regs[d.b] ^ self.regs[d.c],
            @intFromEnum(isa.Op.shl) => self.regs[d.a] = self.regs[d.b] << @as(u5, @truncate(self.regs[d.c])),
            @intFromEnum(isa.Op.shr) => self.regs[d.a] = self.regs[d.b] >> @as(u5, @truncate(self.regs[d.c])),
            @intFromEnum(isa.Op.mov) => self.regs[d.a] = self.regs[d.b],
            @intFromEnum(isa.Op.li) => self.regs[d.a] = isa.imm16(d.b, d.c),
            @intFromEnum(isa.Op.lih) => self.regs[d.a] = @as(u32, isa.imm16(d.b, d.c)) << 16,
            @intFromEnum(isa.Op.ld) => {
                const addr = self.regs[d.b] +% self.regs[d.c];
                self.regs[d.a] = self.read32(addr) orelse return;
            },
            @intFromEnum(isa.Op.st) => {
                const addr = self.regs[d.b] +% self.regs[d.c];
                self.write32(addr, self.regs[d.a]) orelse return;
            },
            @intFromEnum(isa.Op.ldb) => {
                const addr = self.regs[d.b] +% self.regs[d.c];
                self.regs[d.a] = self.read8(addr) orelse return;
            },
            @intFromEnum(isa.Op.stb) => {
                const addr = self.regs[d.b] +% self.regs[d.c];
                self.write8(addr, @truncate(self.regs[d.a])) orelse return;
            },
            @intFromEnum(isa.Op.b) => {
                const off = isa.sext16(isa.imm16(d.b, d.c));
                self.pc = @intCast(@as(i32, @intCast(next)) + off);
            },
            @intFromEnum(isa.Op.beq) => {
                if (self.regs[d.a] == self.regs[d.b]) {
                    self.pc = @intCast(@as(i32, @intCast(next)) + isa.sext8(d.c));
                }
            },
            @intFromEnum(isa.Op.bne) => {
                if (self.regs[d.a] != self.regs[d.b]) {
                    self.pc = @intCast(@as(i32, @intCast(next)) + isa.sext8(d.c));
                }
            },
            @intFromEnum(isa.Op.jal) => {
                const off = isa.sext16(isa.imm16(d.b, d.c));
                self.regs[d.a] = next;
                self.pc = @intCast(@as(i32, @intCast(next)) + off);
            },
            @intFromEnum(isa.Op.ret) => {
                self.pc = self.regs[d.a];
            },
            @intFromEnum(isa.Op.svc) => self.svc(d.c),
            else => self.fault("illegal opcode"),
        }
    }

    fn svc(self: *Vm, code: u8) void {
        switch (code) {
            @intFromEnum(isa.Svc.write) => {
                self.hooks.write(self.regs[0], self.regs[1], self.regs[2], self.mem);
                self.regs[0] = self.regs[2];
            },
            @intFromEnum(isa.Svc.exit) => {
                self.exit_code = self.regs[0];
                self.status = .exited;
            },
            @intFromEnum(isa.Svc.yield) => {
                self.status = .yielded;
            },
            @intFromEnum(isa.Svc.fb_fill) => {
                self.hooks.fb_fill(self.regs[0], self.regs[1], self.regs[2], self.regs[3], self.regs[4]);
                self.regs[0] = 0;
            },
            @intFromEnum(isa.Svc.fb_size) => {
                const sz = self.hooks.fb_size();
                self.regs[0] = sz.w;
                self.regs[1] = sz.h;
            },
            @intFromEnum(isa.Svc.get_frame) => {
                self.regs[0] = self.hooks.get_frame();
            },
            @intFromEnum(isa.Svc.fb_donut) => {
                self.hooks.fb_donut(self.regs[0], self.regs[1]);
                self.regs[0] = 0;
            },
            @intFromEnum(isa.Svc.fb_plasma) => {
                self.hooks.fb_plasma(self.regs[0]);
                self.regs[0] = 0;
            },
            @intFromEnum(isa.Svc.fb_stars) => {
                self.hooks.fb_stars(self.regs[0]);
                self.regs[0] = 0;
            },
            @intFromEnum(isa.Svc.fb_cube) => {
                self.hooks.fb_cube(self.regs[0]);
                self.regs[0] = 0;
            },
            @intFromEnum(isa.Svc.fb_fire) => {
                self.hooks.fb_fire(self.regs[0]);
                self.regs[0] = 0;
            },
            else => self.fault("bad svc"),
        }
    }

    fn fault(self: *Vm, reason: []const u8) void {
        self.status = .fault;
        self.fault_reason = reason;
    }

    fn read32(self: *Vm, addr: u32) ?u32 {
        if (addr + 4 > self.mem.len) {
            self.fault("load oob");
            return null;
        }
        return std.mem.readInt(u32, self.mem[addr..][0..4], .little);
    }

    fn write32(self: *Vm, addr: u32, val: u32) ?void {
        if (addr + 4 > self.mem.len) {
            self.fault("store oob");
            return null;
        }
        std.mem.writeInt(u32, self.mem[addr..][0..4], val, .little);
        return {};
    }

    fn read8(self: *Vm, addr: u32) ?u32 {
        if (addr >= self.mem.len) {
            self.fault("load oob");
            return null;
        }
        return self.mem[addr];
    }

    fn write8(self: *Vm, addr: u32, val: u8) ?void {
        if (addr >= self.mem.len) {
            self.fault("store oob");
            return null;
        }
        self.mem[addr] = val;
        return {};
    }
};
