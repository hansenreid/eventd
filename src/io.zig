const std = @import("std");
const assert = std.debug.assert;
const commands = @import("io_commands.zig");

pub const IO = @This();

vtable: *const VTable,
ptr: *anyopaque,

pub const VTable = struct {
    tick: *const fn (ptr: *anyopaque) void,
    logFn: *const fn (ptr: *anyopaque, msg: []const u8) void,
    writeFn: *const fn (ptr: *anyopaque, write_command: commands.WriteCommand, status: *commands.Status) void,
};

pub fn tick(self: *IO) void {
    self.vtable.tick(self.ptr);
}

pub fn log(self: *IO, msg: []const u8) void {
    self.vtable.logFn(self.ptr, msg);
}

pub fn write(self: *IO, write_command: commands.WriteCommand, status: *commands.Status) void {
    assert(status.* == commands.Status.submitted);
    self.vtable.writeFn(self.ptr, write_command, status);
    assert(status.* == commands.Status.waiting or status.* == commands.Status.completed);
}
