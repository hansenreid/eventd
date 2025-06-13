const std = @import("std");
const assert = std.debug.assert;
const commands = @import("../io_commands.zig");

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

pub fn write(self: *IO, write_command: commands.WriteCommand, status: *commands.Status) void {
    assert(status.* == commands.Status.submitted);
    _ = self;
    _ = write_command;

    status.* = .completed;
    std.debug.print("Hello from write impl\n", .{});
}
