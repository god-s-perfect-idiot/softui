//! Classic plasma for SoftASM `svc fb_plasma`.
//! SoftASM passes integer phase (mod 1024 = one cycle).

const TAU: f32 = 6.28318530718;
const PHASE: f32 = TAU / 1024.0;

pub fn render(
    fb: []u8,
    width: u32,
    height: u32,
    stride: u32,
    phase: u32,
) void {
    const w: usize = width;
    const h: usize = height;
    if (w == 0 or h == 0) return;

    const t = @as(f32, @floatFromInt(phase & 1023)) * PHASE;
    const inv_w = 1.0 / @as(f32, @floatFromInt(width));
    const inv_h = 1.0 / @as(f32, @floatFromInt(height));

    var y: usize = 0;
    while (y < h) : (y += 1) {
        const fy = @as(f32, @floatFromInt(y)) * inv_h;
        const sy = @sin(fy * 6.0 + t * 1.3);
        var x: usize = 0;
        while (x < w) : (x += 1) {
            const fx = @as(f32, @floatFromInt(x)) * inv_w;
            const v1 = @sin(fx * 8.0 + t);
            const v2 = sy;
            const v3 = @sin((fx + fy) * 7.0 + t * 0.7);
            const dx = fx - 0.5 - 0.2 * @sin(t * 0.5);
            const dy = fy - 0.5 - 0.2 * @cos(t * 0.4);
            const v4 = @sin(@sqrt(dx * dx + dy * dy) * 14.0 - t * 1.6);
            const v = (v1 + v2 + v3 + v4) * 0.25; // -1..1

            // Cool teal → violet palette (not purple-on-white AI default).
            const u = v * 0.5 + 0.5;
            const r: u8 = @intFromFloat(20.0 + u * 90.0 + @sin(u * TAU + t) * 40.0);
            const g: u8 = @intFromFloat(40.0 + (1.0 - u) * 140.0 + @cos(u * TAU) * 30.0);
            const b: u8 = @intFromFloat(80.0 + u * 160.0);

            const o = y * @as(usize, stride) + x * 4;
            fb[o + 0] = r;
            fb[o + 1] = g;
            fb[o + 2] = b;
            fb[o + 3] = 255;
        }
    }
}
