//! Root documentation.
/// Reads bytes, unchanged.
pub fn read(buf: []u8) usize {
    return buf.len;
}
/// A nested container.
pub const Box = struct {
    /// Opens a file.
    pub fn openFile() void {}
    pub const Mode = enum { one, two };
};
pub const child = @import("child.zig");
pub var counter: usize = 0;
const hidden = 1;
pub const ErrorSet = error{Bad};
pub const ErrorValue = error.Bad;
