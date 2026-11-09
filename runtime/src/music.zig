//! Music player — synthesizes PCM and queues via Host ABI audio.

const gfx = @import("demo_gfx.zig");
const hostapi = @import("hostapi.zig");

var playing: bool = true;
var track: u32 = 0;
var last_queue_phase: u32 = 0xFFFFFFFF;
var audio_ok: bool = false;

const TRACKS = [_][]const u8{ "SoftPulse", "TickWave", "TriTone" };
const SAMPLE_RATE: u32 = 22050;
const CHUNK_SAMPLES: usize = 2048;
var pcm_buf: [CHUNK_SAMPLES * 2]u8 = undefined; // s16le mono

// Simple note tables (Hz * 100 for integer math avoided — use f32).
const PULSE_NOTES = [_]f32{ 262.0, 330.0, 392.0, 523.0, 392.0, 330.0 };
const WAVE_NOTES = [_]f32{ 196.0, 247.0, 294.0, 370.0, 294.0, 247.0 };
const TRI_NOTES = [_]f32{ 440.0, 554.0, 659.0, 880.0, 659.0, 554.0 };

pub fn reset() void {
    playing = true;
    track = 0;
    last_queue_phase = 0xFFFFFFFF;
    audio_ok = false;
    hostapi.audioStop();
}

pub fn onKey(key: u32) void {
    if (key == ' ' or key == 13) {
        playing = !playing;
        if (!playing) hostapi.audioStop();
        last_queue_phase = 0xFFFFFFFF;
        return;
    }
    if (key == 'n' or key == 'N' or key == 0x101) {
        track = (track + 1) % TRACKS.len;
        last_queue_phase = 0xFFFFFFFF;
        return;
    }
    if (key == 'p' or key == 'P' or key == 0x100) {
        track = if (track == 0) TRACKS.len - 1 else track - 1;
        last_queue_phase = 0xFFFFFFFF;
    }
}

pub fn render(fb: []u8, width: u32, height: u32, stride: u32, phase: u32) void {
    if (playing and phase != last_queue_phase and (phase % 4) == 0) {
        last_queue_phase = phase;
        synthesizeAndQueue(phase);
    }

    gfx.clear(fb, stride, width, height, gfx.COLOR_BG);
    gfx.drawText(fb, stride, width, height, 12, 36, "MUSIC PLAYER", gfx.COLOR_DIM);
    gfx.drawText(fb, stride, width, height, 12, 52, "Space play/pause  N/P track", gfx.COLOR_DIM);

    const name = TRACKS[track];
    gfx.drawText(fb, stride, width, height, 12, 80, name, gfx.COLOR_FG);

    const status = if (playing)
        (if (audio_ok) "PLAYING + audio" else "PLAYING (no host audio)")
    else
        "PAUSED";
    gfx.drawText(fb, stride, width, height, 12, 96, status, if (playing and audio_ok) gfx.COLOR_OK else gfx.COLOR_WARN);

    const bar_x: u32 = 12;
    const bar_y: u32 = 120;
    const bar_w = if (width > 24) width - 24 else width;
    const fill_w = (bar_w * (phase % 240)) / 240;
    gfx.rect(fb, stride, width, height, bar_x, bar_y, bar_w, 8, gfx.COLOR_BORDER);
    gfx.fill(fb, stride, width, height, bar_x, bar_y, fill_w, 8, gfx.COLOR_ACCENT);

    const wave_y: u32 = 160;
    const wave_h: u32 = 64;
    gfx.rect(fb, stride, width, height, 12, wave_y, bar_w, wave_h, gfx.COLOR_BORDER);
    var x: u32 = 0;
    while (x < bar_w) : (x += 2) {
        const t = @as(f32, @floatFromInt(x + (if (playing) phase else 0)));
        const s1 = @sin(t * 0.08);
        const s2 = @sin(t * 0.19 + 1.2);
        const amp = if (playing) (s1 * 0.6 + s2 * 0.4) else s1 * 0.15;
        const mid = wave_y + wave_h / 2;
        const dy: i32 = @intFromFloat(amp * @as(f32, @floatFromInt(wave_h / 2 - 2)));
        const y: u32 = if (dy >= 0)
            mid -| @as(u32, @intCast(dy))
        else
            mid +| @as(u32, @intCast(-dy));
        gfx.put(fb, stride, width, height, 12 + x, y, gfx.COLOR_ACCENT);
    }

    gfx.drawText(fb, stride, width, height, 12, height -| 36, "host_audio_queue PCM s16le", gfx.COLOR_DIM);
    gfx.drawText(fb, stride, width, height, 12, height -| 20, "Esc / exit to leave", gfx.COLOR_DIM);
}

fn notesForTrack() []const f32 {
    return switch (track) {
        0 => &PULSE_NOTES,
        1 => &WAVE_NOTES,
        else => &TRI_NOTES,
    };
}

fn synthesizeAndQueue(phase: u32) void {
    const notes = notesForTrack();
    const note = notes[(phase / 16) % notes.len];
    const step = note / @as(f32, @floatFromInt(SAMPLE_RATE));
    var phase_acc: f32 = 0;
    var i: usize = 0;
    while (i < CHUNK_SAMPLES) : (i += 1) {
        const t = phase_acc;
        phase_acc += step;
        if (phase_acc >= 1.0) phase_acc -= 1.0;
        var sample: f32 = 0;
        switch (track) {
            0 => sample = if (t < 0.5) 0.25 else -0.25, // square
            1 => sample = @sin(t * 6.2831853) * 0.3, // sine
            else => sample = (if (t < 0.5) (t * 4.0 - 1.0) else (3.0 - t * 4.0)) * 0.25, // triangle-ish
        }
        // Soft envelope to avoid clicks.
        const env_edge: f32 = 64.0;
        var env: f32 = 1.0;
        if (i < 64) env = @as(f32, @floatFromInt(i)) / env_edge;
        if (i + 64 > CHUNK_SAMPLES) env = @as(f32, @floatFromInt(CHUNK_SAMPLES - i)) / env_edge;
        const s16: i16 = @intFromFloat(sample * env * 30000.0);
        pcm_buf[i * 2] = @truncate(@as(u16, @bitCast(s16)));
        pcm_buf[i * 2 + 1] = @truncate(@as(u16, @bitCast(s16)) >> 8);
    }
    const rc = hostapi.audioQueue(pcm_buf[0..], SAMPLE_RATE, 1);
    audio_ok = rc == 0;
}
