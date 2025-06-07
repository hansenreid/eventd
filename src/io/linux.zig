const std = @import("std");
const assert = std.debug.assert;
const IO = @import("../io.zig");
const commands = @import("../io_commands.zig");

pub const linux_io = @This();

pub fn io(self: *linux_io) IO {
    return .{
        .ptr = self,
        .vtable = &IO.VTable{
            .tick = tick,
            .logFn = log,
            .writeFn = write,
        },
    };
}

fn tick(ptr: *anyopaque) void {
    const self: *linux_io = @ptrCast(@alignCast(ptr));
    _ = self;

    std.debug.print("IO tick\n", .{});
}

fn log(ptr: *anyopaque, msg: []const u8) void {
    const self: *linux_io = @ptrCast(@alignCast(ptr));
    _ = self;

    std.debug.print("{s}\n", .{msg});
}

fn write(ptr: *anyopaque, write_command: commands.WriteCommand, status: *commands.Status) void {
    assert(status.* == commands.Status.submitted);
    const self: *linux_io = @ptrCast(@alignCast(ptr));
    _ = self;
    _ = write_command;

    status.* = .completed;
    std.debug.print("Hello from write impl\n", .{});
}
