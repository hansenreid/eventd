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
    result: *WriteResult,

    pub const WriteResult = struct {
        code: u8,
    };

    pub fn init(allocator: Allocator, buffer: []const u8) !Command {
        const result = try allocator.create(WriteResult);

        const write = WriteCommand{
            .fd = 1,
            .buffer = buffer,
            .result = result,
        };

        return Command{ .write = write };
    }
};
