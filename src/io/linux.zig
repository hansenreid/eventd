const std = @import("std");
const assert = std.debug.assert;

const io_impl = @import("../io.zig");
const Command = io_impl.Command;
const Status = @import("../io_loop.zig").Continuation.Status;

pub const IO = @This();

pub fn init() IO {
    return .{};
}

pub fn tick(self: *IO) void {
    _ = self;

    std.debug.print("IO tick\n", .{});
}

pub fn log(self: *IO, msg: []const u8) void {
    _ = self;

    std.debug.print("{s}\n", .{msg});
}

pub fn write(self: *IO, write_command: io_impl.WriteCmd, status: *Status) void {
    assert(status.* == Status.submitted);
    _ = self;
    _ = write_command;

    status.* = .completed;
    std.debug.print("Hello from write impl\n", .{});
}
