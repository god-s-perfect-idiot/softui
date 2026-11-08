//! Shared SoftASM opcode constants (assembler + VM).

pub const Op = enum(u8) {
    add = 0x01,
    sub = 0x02,
    mul = 0x03,
    @"and" = 0x04,
    @"or" = 0x05,
    xor = 0x06,
    shl = 0x07,
    shr = 0x08,
    mov = 0x10,
    li = 0x11,
    lih = 0x16, // rd = imm16 << 16
    ld = 0x12,
    st = 0x13,
    ldb = 0x14,
    stb = 0x15,
    b = 0x20,
    beq = 0x21,
    bne = 0x22,
    jal = 0x23,
    ret = 0x24,
    svc = 0x30,
};

pub const Svc = enum(u8) {
    write = 1,
    exit = 2,
    yield = 3,
    fb_fill = 10,
    fb_size = 11,
    get_frame = 12,
    fb_donut = 13, // r0=phase_a, r1=phase_b (mod 1024 = one turn)
    fb_plasma = 14, // r0=phase (mod 1024)
    fb_stars = 15, // r0=phase
    fb_cube = 16, // r0=phase (mod 1024 = one turn)
    fb_fire = 17, // r0=phase
};

pub const SoxHeader = extern struct {
    magic: [4]u8,
    version: u16,
    flags: u16,
    entry: u32,
    code_size: u32,
    rodata_size: u32,
    bss_size: u32,
    reserved: u32,

    pub const magic_value = [4]u8{ 'S', 'O', 'X', 0 };
    pub const current_version: u16 = 1;
    pub const size: usize = 28;
};

pub fn encode(op: Op, a: u8, b: u8, c: u8) u32 {
    return (@as(u32, @intFromEnum(op)) << 24) |
        (@as(u32, a) << 16) |
        (@as(u32, b) << 8) |
        @as(u32, c);
}

pub fn decode(word: u32) struct { op: u8, a: u8, b: u8, c: u8 } {
    return .{
        .op = @truncate(word >> 24),
        .a = @truncate(word >> 16),
        .b = @truncate(word >> 8),
        .c = @truncate(word),
    };
}

pub fn imm16(b: u8, c: u8) u16 {
    return (@as(u16, b) << 8) | c;
}

pub fn splitImm16(v: u16) struct { b: u8, c: u8 } {
    return .{ .b = @truncate(v >> 8), .c = @truncate(v) };
}

pub fn sext16(v: u16) i32 {
    return @as(i32, @as(i16, @bitCast(v)));
}

pub fn sext8(v: u8) i32 {
    return @as(i32, @as(i8, @bitCast(v)));
}
