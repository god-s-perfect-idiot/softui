//! Emit SoftUI desktop SVG sources (icons + wallpaper) under sysroot/.
//! Icons are skeuomorphic 64×64 plates; wallpaper is a soft scenic gradient plate.
const std = @import("std");

const Icon = struct { name: []const u8, face_top: []const u8, face_bot: []const u8, glyph: []const u8 };

const ICONS = [_]Icon{
    .{ .name = "shell", .face_top = "#6A9AC8", .face_bot = "#3A5A80", .glyph =
        \\  <rect x="18" y="20" width="28" height="22" rx="3" fill="#1A2430" opacity="0.85"/>
        \\  <rect x="20" y="22" width="24" height="18" rx="2" fill="#0C1218"/>
        \\  <rect x="22" y="28" width="10" height="2" fill="#7DFFB0"/>
        \\  <rect x="22" y="32" width="16" height="2" fill="#5078A0"/>
    },
    .{ .name = "clock", .face_top = "#F0E6C8", .face_bot = "#C8A86A", .glyph =
        \\  <circle cx="32" cy="32" r="14" fill="#FFF8E8"/>
        \\  <circle cx="32" cy="32" r="14" fill="none" stroke="#8A7040" stroke-width="2"/>
        \\  <line x1="32" y1="32" x2="32" y2="22" stroke="#3A3020" stroke-width="2"/>
        \\  <line x1="32" y1="32" x2="40" y2="36" stroke="#3A3020" stroke-width="2"/>
        \\  <circle cx="32" cy="32" r="2" fill="#C04040"/>
    },
    .{ .name = "cursor", .face_top = "#E8EEF4", .face_bot = "#8A96A8", .glyph =
        \\  <path d="M24 18 L24 46 L32 38 L38 50 L42 48 L36 36 L46 36 Z" fill="#2A3340"/>
        \\  <path d="M26 22 L26 40 L32 34 L37 44 L39 43 L34 33 L42 33 Z" fill="#F8FBFF"/>
    },
    .{ .name = "keys", .face_top = "#7A8490", .face_bot = "#3A424C", .glyph =
        \\  <rect x="16" y="24" width="32" height="20" rx="3" fill="#1E242C"/>
        \\  <rect x="19" y="28" width="6" height="5" rx="1" fill="#D8DEE8"/>
        \\  <rect x="27" y="28" width="6" height="5" rx="1" fill="#D8DEE8"/>
        \\  <rect x="35" y="28" width="6" height="5" rx="1" fill="#D8DEE8"/>
        \\  <rect x="19" y="36" width="26" height="5" rx="1" fill="#B0B8C4"/>
    },
    .{ .name = "image", .face_top = "#70B8A0", .face_bot = "#3A7060", .glyph =
        \\  <rect x="16" y="18" width="32" height="28" rx="3" fill="#F4F7FA"/>
        \\  <rect x="16" y="18" width="32" height="28" rx="3" fill="none" stroke="#2A4038" stroke-width="2"/>
        \\  <circle cx="26" cy="28" r="4" fill="#E8C84A"/>
        \\  <path d="M18 42 L28 32 L36 38 L42 30 L46 42 Z" fill="#3A8A70"/>
    },
    .{ .name = "music", .face_top = "#B070D0", .face_bot = "#603888", .glyph =
        \\  <line x1="38" y1="16" x2="38" y2="40" stroke="#F8F0FF" stroke-width="3"/>
        \\  <path d="M38 16 L50 20 L50 28 L38 24 Z" fill="#F8F0FF"/>
        \\  <ellipse cx="30" cy="42" rx="8" ry="6" fill="#2A1838"/>
        \\  <ellipse cx="30" cy="42" rx="5" ry="3.5" fill="#E8C84A"/>
    },
    .{ .name = "paint", .face_top = "#F0A070", .face_bot = "#A05030", .glyph =
        \\  <circle cx="28" cy="28" r="12" fill="#F8F0E8"/>
        \\  <circle cx="22" cy="24" r="4" fill="#E05050"/>
        \\  <circle cx="30" cy="22" r="4" fill="#5078A0"/>
        \\  <circle cx="34" cy="30" r="4" fill="#E8C84A"/>
        \\  <circle cx="26" cy="34" r="4" fill="#3DDC97"/>
        \\  <rect x="36" y="34" width="4" height="14" rx="1" fill="#C8A080"/>
    },
    .{ .name = "uikit", .face_top = "#70A0C8", .face_bot = "#385878", .glyph =
        \\  <rect x="16" y="20" width="32" height="10" rx="3" fill="#E8EEF4"/>
        \\  <rect x="16" y="34" width="14" height="10" rx="3" fill="#5078A0"/>
        \\  <rect x="34" y="34" width="14" height="10" rx="5" fill="#2A3848"/>
        \\  <circle cx="44" cy="39" r="3" fill="#E8EEF4"/>
    },
    .{ .name = "colors", .face_top = "#909090", .face_bot = "#404040", .glyph =
        \\  <circle cx="24" cy="26" r="8" fill="#E05050"/>
        \\  <circle cx="40" cy="26" r="8" fill="#5078A0"/>
        \\  <circle cx="24" cy="40" r="8" fill="#E8C84A"/>
        \\  <circle cx="40" cy="40" r="8" fill="#3DDC97"/>
    },
    .{ .name = "text", .face_top = "#D0D6E0", .face_bot = "#687088", .glyph =
        \\  <rect x="20" y="18" width="24" height="28" rx="2" fill="#F8FAFC"/>
        \\  <rect x="24" y="24" width="16" height="3" fill="#2A3340"/>
        \\  <rect x="24" y="30" width="12" height="2" fill="#687088"/>
        \\  <rect x="24" y="36" width="14" height="2" fill="#687088"/>
        \\  <rect x="24" y="42" width="10" height="2" fill="#687088"/>
    },
    .{ .name = "donut", .face_top = "#E090B0", .face_bot = "#804060", .glyph =
        \\  <circle cx="32" cy="32" r="14" fill="#F8C0D8"/>
        \\  <circle cx="32" cy="32" r="14" fill="none" stroke="#603040" stroke-width="2"/>
        \\  <circle cx="32" cy="32" r="6" fill="#4A4A4A"/>
        \\  <circle cx="26" cy="26" r="2" fill="#FFFFFF" opacity="0.7"/>
    },
    .{ .name = "plasma", .face_top = "#50C8C8", .face_bot = "#206868", .glyph =
        \\  <ellipse cx="32" cy="32" rx="16" ry="10" fill="#20A0A0" opacity="0.9"/>
        \\  <ellipse cx="28" cy="28" rx="10" ry="6" fill="#80FFF0" opacity="0.7"/>
        \\  <ellipse cx="38" cy="36" rx="8" ry="5" fill="#106060" opacity="0.8"/>
        \\  <circle cx="24" cy="34" r="3" fill="#E8C84A"/>
    },
    .{ .name = "stars", .face_top = "#4050A0", .face_bot = "#182040", .glyph =
        \\  <polygon points="32,16 35,26 46,26 37,33 40,44 32,37 24,44 27,33 18,26 29,26" fill="#E8C84A"/>
        \\  <circle cx="18" cy="20" r="1.5" fill="#FFFFFF"/>
        \\  <circle cx="46" cy="18" r="1.2" fill="#FFFFFF"/>
        \\  <circle cx="48" cy="40" r="1" fill="#FFFFFF"/>
    },
    .{ .name = "cube", .face_top = "#80B0E0", .face_bot = "#406088", .glyph =
        \\  <polygon points="32,16 48,24 48,40 32,48 16,40 16,24" fill="#A8D0F0"/>
        \\  <polygon points="32,16 48,24 32,32 16,24" fill="#D8ECFF"/>
        \\  <polygon points="32,32 48,24 48,40 32,48" fill="#6088B0"/>
        \\  <polygon points="32,32 16,24 16,40 32,48" fill="#5078A0"/>
    },
    .{ .name = "fire", .face_top = "#F08040", .face_bot = "#A02810", .glyph =
        \\  <path d="M32 14 C28 24 20 28 20 38 C20 46 26 50 32 50 C38 50 44 46 44 38 C44 28 36 24 32 14 Z" fill="#FFD060"/>
        \\  <path d="M32 24 C30 30 26 32 26 38 C26 42 29 45 32 45 C35 45 38 42 38 38 C38 32 34 30 32 24 Z" fill="#FF6030"/>
        \\  <path d="M32 34 C31 36 30 37 30 39 C30 41 31 42 32 42 C33 42 34 41 34 39 C34 37 33 36 32 34 Z" fill="#FFF0C0"/>
    },
    .{ .name = "calc", .face_top = "#A8B0BC", .face_bot = "#505860", .glyph =
        \\  <rect x="18" y="14" width="28" height="36" rx="3" fill="#2A3038"/>
        \\  <rect x="21" y="18" width="22" height="8" rx="1" fill="#C8F0D0"/>
        \\  <rect x="21" y="30" width="6" height="5" rx="1" fill="#D0D6E0"/>
        \\  <rect x="29" y="30" width="6" height="5" rx="1" fill="#D0D6E0"/>
        \\  <rect x="37" y="30" width="6" height="5" rx="1" fill="#5078A0"/>
        \\  <rect x="21" y="38" width="6" height="5" rx="1" fill="#D0D6E0"/>
        \\  <rect x="29" y="38" width="6" height="5" rx="1" fill="#D0D6E0"/>
        \\  <rect x="37" y="38" width="6" height="5" rx="1" fill="#E8C84A"/>
    },
    .{ .name = "hello", .face_top = "#70C890", .face_bot = "#387850", .glyph =
        \\  <ellipse cx="30" cy="30" rx="14" ry="12" fill="#F4FFF8"/>
        \\  <path d="M22 40 L18 48 L28 42 Z" fill="#F4FFF8"/>
        \\  <circle cx="26" cy="28" r="2" fill="#2A4030"/>
        \\  <circle cx="34" cy="28" r="2" fill="#2A4030"/>
        \\  <path d="M24 34 Q30 38 36 34" fill="none" stroke="#2A4030" stroke-width="2"/>
    },
    .{ .name = "drawer", .face_top = "#6A727C", .face_bot = "#2E343C", .glyph =
        \\  <rect x="18" y="18" width="8" height="8" rx="2" fill="#E8EEF4"/>
        \\  <rect x="28" y="18" width="8" height="8" rx="2" fill="#E8EEF4"/>
        \\  <rect x="38" y="18" width="8" height="8" rx="2" fill="#E8EEF4"/>
        \\  <rect x="18" y="28" width="8" height="8" rx="2" fill="#E8EEF4"/>
        \\  <rect x="28" y="28" width="8" height="8" rx="2" fill="#5078A0"/>
        \\  <rect x="38" y="28" width="8" height="8" rx="2" fill="#E8EEF4"/>
        \\  <rect x="18" y="38" width="8" height="8" rx="2" fill="#E8EEF4"/>
        \\  <rect x="28" y="38" width="8" height="8" rx="2" fill="#E8EEF4"/>
        \\  <rect x="38" y="38" width="8" height="8" rx="2" fill="#E8EEF4"/>
    },
};

fn writeIcon(gpa: std.mem.Allocator, cwd: std.Io.Dir, icon: Icon) !void {
    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(gpa);
    try buf.writer(gpa).print(
        \\<?xml version="1.0" encoding="UTF-8"?>
        \\<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" viewBox="0 0 64 64">
        \\  <defs>
        \\    <linearGradient id="face" x1="0" y1="0" x2="0" y2="1">
        \\      <stop offset="0" stop-color="{s}"/>
        \\      <stop offset="1" stop-color="{s}"/>
        \\    </linearGradient>
        \\    <linearGradient id="sheen" x1="0" y1="0" x2="0" y2="1">
        \\      <stop offset="0" stop-color="#FFFFFF" stop-opacity="0.45"/>
        \\      <stop offset="1" stop-color="#FFFFFF" stop-opacity="0"/>
        \\    </linearGradient>
        \\  </defs>
        \\  <rect x="4" y="6" width="56" height="56" rx="12" fill="#000000" opacity="0.28"/>
        \\  <rect x="2" y="2" width="56" height="56" rx="12" fill="#1A1A1A"/>
        \\  <rect x="3" y="3" width="54" height="54" rx="11" fill="url(#face)"/>
        \\  <rect x="6" y="5" width="48" height="16" rx="8" fill="url(#sheen)"/>
        \\  <rect x="4" y="4" width="52" height="2" rx="1" fill="#FFFFFF" opacity="0.35"/>
        \\{s}
        \\</svg>
        \\
    , .{ icon.face_top, icon.face_bot, icon.glyph });

    var path_buf: [64]u8 = undefined;
    const path = try std.fmt.bufPrint(&path_buf, "sysroot/icons/{s}.svg", .{icon.name});
    try cwd.writeFile(.{ .sub_path = path, .data = buf.items });
}

fn writeWallpaper(cwd: std.Io.Dir) !void {
    const svg =
        \\<?xml version="1.0" encoding="UTF-8"?>
        \\<svg xmlns="http://www.w3.org/2000/svg" width="160" height="100" viewBox="0 0 160 100">
        \\  <defs>
        \\    <linearGradient id="sky" x1="0" y1="0" x2="0" y2="1">
        \\      <stop offset="0" stop-color="#1A2A48"/>
        \\      <stop offset="0.55" stop-color="#3A5080"/>
        \\      <stop offset="1" stop-color="#8AA0B8"/>
        \\    </linearGradient>
        \\    <linearGradient id="hill" x1="0" y1="0" x2="0" y2="1">
        \\      <stop offset="0" stop-color="#3A5A48"/>
        \\      <stop offset="1" stop-color="#1A2A24"/>
        \\    </linearGradient>
        \\  </defs>
        \\  <rect width="160" height="100" fill="url(#sky)"/>
        \\  <circle cx="125" cy="24" r="14" fill="#E8D090" opacity="0.9"/>
        \\  <circle cx="125" cy="24" r="17" fill="#E8D090" opacity="0.2"/>
        \\  <ellipse cx="30" cy="35" rx="20" ry="6" fill="#FFFFFF" opacity="0.12"/>
        \\  <ellipse cx="70" cy="25" rx="25" ry="7" fill="#FFFFFF" opacity="0.10"/>
        \\  <path d="M0 70 C20 60 40 75 60 65 C80 55 100 75 120 64 C140 55 150 65 160 60 L160 100 L0 100 Z" fill="url(#hill)"/>
        \\  <path d="M0 80 C25 74 45 85 70 78 C95 70 115 84 140 75 C150 72 156 75 160 73 L160 100 L0 100 Z" fill="#142018" opacity="0.85"/>
        \\</svg>
        \\
    ;
    try cwd.writeFile(.{ .sub_path = "sysroot/wallpaper.svg", .data = svg });
}

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    var cwd = std.Io.Dir.cwd();
    try cwd.makePath("sysroot/icons");
    try cwd.makePath("sysroot/generated");
    for (ICONS) |icon| try writeIcon(gpa, cwd, icon);
    try writeWallpaper(cwd);
    std.debug.print("wrote {d} icons + wallpaper.svg\n", .{ICONS.len});
}
