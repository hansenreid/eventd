const std = @import("std");
const IO = @import("../io.zig");

pub const linux_io = @This();

pub fn io(self: *linux_io) IO {
    const vtable = IO.VTable{
        .logFn = log,
    };
    return .{
        .ptr = self,
        .vtable = &vtable,
    };
}

fn log(ptr: *anyopaque, msg: []const u8) void {
    const self: *linux_io = @ptrCast(@alignCast(ptr));
    _ = self;

    std.debug.print("{s}\n", .{msg});
}
