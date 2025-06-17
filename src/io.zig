const builtin = @import("builtin");
const std = @import("std");
const options = @import("build_options");
const assert = std.debug.assert;

const IO_Linux = @import("io/linux.zig").IO;
const IO_Test = @import("io/test.zig").IO;

// TODO: Rename this? Importing as io_impl does not feel great
pub const IO = if (options.test_io) IO_Test else switch (builtin.target.os.tag) {
    .linux => IO_Linux,
    else => @compileError("IO is not supported for platform"),
};

const fd_t = switch (builtin.target.os.tag) {
    .linux => std.os.linux.fd_t,
    else => @compileError("IO is not supported for platform"),
};

pub const SubmitError = error{
    Retry,
    Unexpected,
};

pub const Command = union(enum) {
    write: WriteCmd,
    read: ReadCmd,
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

const ReadError = error{
    Retry,
    IsDirectory,
    BadFileDescriptor,
    Unseekable,
    ResourceExhausted,
    Unexpected,
};

pub const ReadCmd = cmd(ReadData, ReadError!ReadResult);
pub const ReadData = struct {
    fd: fd_t,
    buffer: []u8,
    offset: u64,

    pub fn to_cmd(data: ReadData) Command {
        return Command{ .read = ReadCmd.init(data) };
    }
};

pub const ReadResult = struct {
    bytes_read: u31,

    comptime {
        assert(@sizeOf(ReadResult) == @sizeOf(u31));
    }
};

const WriteError = error{
    Unexpected,
};

pub const WriteCmd = cmd(WriteData, WriteError!WriteResult);

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
