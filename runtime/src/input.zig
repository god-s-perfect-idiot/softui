//! SoftUI keyboard event queue (Host ABI → kernel). No host widgets.

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

pub const Event = struct {
    key: u32,
    mods: u32,
};

const CAP: usize = 64;

var q: [CAP]Event = undefined;
var head: usize = 0;
var tail: usize = 0;
var count: usize = 0;

pub fn reset() void {
    head = 0;
    tail = 0;
    count = 0;
}

pub fn push(key: u32, mods: u32) void {
    if (count == CAP) {
        // Drop oldest.
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
