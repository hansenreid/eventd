const builtin = @import("builtin");
const std = @import("std");
const options = @import("build_options");
const assert = std.debug.assert;
const linux = std.os.linux;

const IO_Linux = @import("io/linux.zig").IO;
const IO_Test = @import("io/test.zig").IO;

// TODO: Rename this? Importing as io_impl does not feel great
pub const IO = if (options.test_io) IO_Test else switch (builtin.target.os.tag) {
    .linux => IO_Linux,
    else => @compileError("IO is not supported for platform"),
};

pub const fd_t = switch (builtin.target.os.tag) {
    .linux => std.os.linux.fd_t,
    else => @compileError("IO is not supported for platform"),
};

pub const open_flags = switch (builtin.target.os.tag) {
    .linux => linux.O,
    else => @compileError("IO is not supported for platform"),
};

pub const mode_t = switch (builtin.target.os.tag) {
    .linux => linux.mode_t,
    else => @compileError("IO is not supported for platform"),
};

pub const SubmitError = error{
    Retry,
    Unexpected,
};

pub const Command = union(enum) {
    open: OpenCmd,
    read: ReadCmd,
    write: WriteCmd,
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

pub const OpenCmd = cmd(OpenData, OpenError!OpenResult);
pub const OpenData = struct {
    dir_fd: fd_t,
    path: [*:0]const u8,
    flags: open_flags,
    mode: mode_t,

    pub fn to_cmd(data: OpenData) Command {
        return Command{ .open = OpenCmd.init(data) };
    }
};

pub const OpenResult = struct {
    fd: fd_t,
};

pub const OpenError = error{
    AccessDenied,
    DeviceBusy,
    FileBusy,
    FileLocksNotSupported,
    FileNotFound,
    FileTooBig,
    IsDirectory,
    NameTooLong,
    NoDevice,
    NoSpaceLeft,
    NotDirectory,
    PathAlreadyExists,
    ResourceExhausted,
    Retry,
    TooManyOpenFiles,
    TooManySymLinks,
    Unexpected,
    WouldBlock,
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

const ReadError = error{
    BadFileDescriptor,
    IsDirectory,
    ResourceExhausted,
    Retry,
    Unexpected,
    Unseekable,
};

const WriteError = error{
    AccessDenied,
    BrokenPipe,
    DiskQuotaExceeded,
    FileTooLarge,
    InputOutput,
    InvalidArgument,
    InvalidSeek,
    NoSpaceLeft,
    NoSuchDevice,
    NotOpenForWriting,
    Overflow,
    Retry,
    Unexpected,
    WouldBlock,
};

pub const WriteCmd = cmd(WriteData, WriteError!WriteResult);

pub const WriteData = struct {
    fd: fd_t,
    buffer: []const u8,
    offset: u64,

    pub fn to_cmd(self: WriteData) Command {
        return Command{ .write = WriteCmd.init(self) };
    }
};

pub const WriteResult = struct {
    bytes_written: u31,

    comptime {
        assert(@sizeOf(WriteResult) == @sizeOf(u31));
    }
};
