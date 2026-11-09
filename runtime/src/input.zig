//! SoftUI keyboard + pointer queues (Host ABI → kernel). No host widgets.

pub const KEY_BACKSPACE: u32 = 8;
pub const KEY_TAB: u32 = 9;
pub const KEY_ENTER: u32 = 13;
pub const KEY_ESCAPE: u32 = 27;
pub const KEY_LEFT: u32 = 0x100;
pub const KEY_RIGHT: u32 = 0x101;
pub const KEY_UP: u32 = 0x102;
pub const KEY_DOWN: u32 = 0x103;
pub const KEY_HOME: u32 = 0x104;
pub const KEY_END: u32 = 0x105;
pub const KEY_DELETE: u32 = 0x106;

pub const PTR_MOVE: u32 = 0;
pub const PTR_DOWN: u32 = 1;
pub const PTR_UP: u32 = 2;

pub const Event = struct {
    key: u32,
    mods: u32,
};

pub const Pointer = struct {
    x: u32,
    y: u32,
    buttons: u32,
    kind: u32,
};

const CAP: usize = 64;

var q: [CAP]Event = undefined;
var head: usize = 0;
var tail: usize = 0;
var count: usize = 0;

var pq: [CAP]Pointer = undefined;
var p_head: usize = 0;
var p_tail: usize = 0;
var p_count: usize = 0;

/// Most recent pointer sample (updated on every push, even if the queue drops).
pub var latest: Pointer = .{ .x = 0, .y = 0, .buttons = 0, .kind = 0 };

pub fn reset() void {
    head = 0;
    tail = 0;
    count = 0;
    p_head = 0;
    p_tail = 0;
    p_count = 0;
    latest = .{ .x = 0, .y = 0, .buttons = 0, .kind = 0 };
}

pub fn push(key: u32, mods: u32) void {
    if (count == CAP) {
        head = (head + 1) % CAP;
        count -= 1;
    }
    q[tail] = .{ .key = key, .mods = mods };
    tail = (tail + 1) % CAP;
    count += 1;
}

pub fn pop() ?Event {
    if (count == 0) return null;
    const e = q[head];
    head = (head + 1) % CAP;
    count -= 1;
    return e;
}

pub fn pending() usize {
    return count;
}

pub fn pushPointer(x: u32, y: u32, buttons: u32, kind: u32) void {
    latest = .{ .x = x, .y = y, .buttons = buttons, .kind = kind };
    if (p_count == CAP) {
        p_head = (p_head + 1) % CAP;
        p_count -= 1;
    }
    pq[p_tail] = latest;
    p_tail = (p_tail + 1) % CAP;
    p_count += 1;
}

pub fn popPointer() ?Pointer {
    if (p_count == 0) return null;
    const e = pq[p_head];
    p_head = (p_head + 1) % CAP;
    p_count -= 1;
    return e;
}
