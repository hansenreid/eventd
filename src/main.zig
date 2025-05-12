const builtin = @import("builtin");
const linux_io = @import("io/linux.zig");

pub fn main() !void {
    var io_impl = comptime blk: {
        switch (builtin.os.tag) {
            .linux => break :blk linux_io{},
            else => @compileError("Target not supported"),
        }
    };

    const io = io_impl.io();
    const msg: []const u8 = "Hello from impl";
    io.log(msg);
}
