const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Command = union(enum) {
    write: WriteCommand,
};

pub const Status = enum {
    submitted,
    waiting,
    completed,
};

pub const WriteCommand = struct {
    // TODO figure out file descriptor type
    fd: usize,
    buffer: []const u8,

    pub fn init(buffer: []const u8) !Command {
        const write = WriteCommand{
            .fd = 1,
            .buffer = buffer,
        };

        return Command{ .write = write };
    }
};
