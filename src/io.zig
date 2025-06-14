const builtin = @import("builtin");
const std = @import("std");
const options = @import("build_options");
const assert = std.debug.assert;

const IO_Linux = @import("io/linux.zig").IO;
const IO_Test = @import("io/test.zig").IO;

pub const IO = if (options.test_io) IO_Test else switch (builtin.target.os.tag) {
    .linux => IO_Linux,
    else => @compileError("IO is not supported for platform"),
};

pub const Cmd = struct {
    data: struct {},
    result: struct {},
};

pub fn cmd(data_t: type, result_t: type) type {
    return struct {
        const this = @This();
        data: data_t,
        result: ?result_t = null,

        pub fn init(data: data_t) this {
            return .{
                .data = data,
            };
        }
    };
}

pub const WriteCmd = cmd(WriteData, anyerror!WriteResult);
pub const WriteData = struct {
    fd: usize,
    buffer: []const u8,

    pub fn to_cmd(self: WriteData) Command {
        return Command{ .write = WriteCmd.init(self) };
    }
};

pub const WriteResult = struct {
    bytes_read: usize,

    comptime {
        assert(@sizeOf(WriteResult) == @sizeOf(usize));
    }
};

pub const Command = union(enum) {
    write: WriteCmd,
};
