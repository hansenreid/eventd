const std = @import("std");

pub const IO = @This();

vtable: *const VTable,
ptr: *anyopaque,

pub const VTable = struct {
    logFn: *const fn (ptr: *anyopaque, msg: []const u8) void,
};

pub fn log(self: IO, msg: []const u8) void {
    self.vtable.logFn(self.ptr, msg);
}
