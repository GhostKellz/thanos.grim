const std = @import("std");
pub fn main() !void {
    var buf: [10]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);
    _ = stream;
}
