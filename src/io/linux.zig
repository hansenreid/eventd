const std = @import("std");
const assert = std.debug.assert;
const expect = std.testing.expect;
const linux = std.os.linux;
const IoUring = linux.IoUring;
const DoublyLinkedList = std.DoublyLinkedList;

const io_impl = @import("../io.zig");
const Command = io_impl.Command;
const Status = @import("../io_loop.zig").Continuation.Status;
const SubmitError = io_impl.SubmitError;

pub const IO = @This();

ring: IoUring,
ops: DoublyLinkedList,
unused: DoublyLinkedList,
count: usize,

const LIST_SIZE = 1000;
var list: [LIST_SIZE]Op = undefined;

const Op = struct {
    node: DoublyLinkedList.Node,
    status: *Status,
    cmd: *io_impl.Command,
};

pub fn init() !IO {
    var unused: DoublyLinkedList = .{};
    for (&list) |*o| {
        o.node = .{};
        unused.append(&o.node);
    }

    return .{
        .ring = try IoUring.init(128, 0),
        .ops = .{},
        .unused = unused,
        .count = 0,
    };
}

pub fn tick(self: *IO) void {
    _ = self.ring.submit_and_wait(0) catch |err| {
        std.debug.panic("Error submitting: {any}\n", .{err});
    };

    var cqes: [128]linux.io_uring_cqe = undefined;
    const completed = self.ring.copy_cqes(&cqes, 0) catch |err| {
        std.debug.panic("Error getting cqes: {any}\n", .{err});
    };

    for (cqes[0..completed]) |cqe| {
        if (cqe.user_data == 0) continue;

        const op: *Op = @ptrFromInt(cqe.user_data);
        self.handle_complete(op, cqe.res);
    }
}

fn handle_complete(self: *IO, op: *Op, result: i32) void {
    switch (op.cmd.*) {
        .open => open_result(op, result),
        .read => read_result(op, result),
        .write => write_result(op, result),
    }

    op.status.* = .completed;
    self.ops.remove(&op.node);
    self.count -= 1;
}

inline fn get_sqe(self: *IO) SubmitError!*linux.io_uring_sqe {
    return self.ring.get_sqe() catch |err| {
        switch (err) {
            error.SubmissionQueueFull => return SubmitError.Retry,
        }
    };
}

inline fn add_op(self: *IO, cmd: *Command, status: *Status) SubmitError!*Op {
    const node = self.unused.pop() orelse {
        return SubmitError.Retry;
    };

    var op: *Op = @fieldParentPtr("node", node);
    op.cmd = cmd;
    op.status = status;

    status.* = .waiting;
    self.count += 1;

    return op;
}

pub fn log(self: *IO, msg: []const u8) void {
    _ = self;

    std.debug.print("{s}\n", .{msg});
}

pub fn open(self: *IO, cmd: *Command, status: *Status) SubmitError!void {
    assert(cmd.* == .open);
    assert(status.* == Status.queued);

    const data = cmd.open.data;
    const sqe = try self.get_sqe();
    sqe.prep_openat(data.dir_fd, data.path, data.flags, data.mode);
    const op = try self.add_op(cmd, status);
    sqe.user_data = @intFromPtr(op);
}

fn open_result(op: *Op, result: i32) void {
    assert(op.cmd.* == .open);

    if (result < 0) {
        const err = @as(std.posix.E, @enumFromInt(-result));
        op.cmd.open.result = switch (err) {
            .ACCES => error.AccessDenied,
            .AGAIN => error.WouldBlock,
            .BUSY => error.DeviceBusy,
            .EXIST => error.PathAlreadyExists,
            .FBIG => error.FileTooBig,
            .INTR => error.Retry,
            .ISDIR => error.IsDirectory,
            .LOOP => error.TooManySymLinks,
            .MFILE => error.TooManyOpenFiles,
            .NAMETOOLONG => error.NameTooLong,
            .NFILE => error.TooManyOpenFiles,
            .NODEV => error.NoDevice,
            .NOENT => error.FileNotFound,
            .NOMEM => error.ResourceExhausted,
            .NOSPC => error.NoSpaceLeft,
            .NOTDIR => error.NotDirectory,
            .OPNOTSUPP => error.FileLocksNotSupported,
            .OVERFLOW => error.FileTooBig,
            .PERM => error.AccessDenied,
            .TXTBSY => error.FileBusy,
            else => error.Unexpected,
        };

        return;
    }

    op.cmd.open.result = io_impl.OpenResult{
        .fd = @as(io_impl.fd_t, result),
    };
}

pub fn read(self: *IO, cmd: *Command, status: *Status) SubmitError!void {
    assert(cmd.* == .read);
    assert(status.* == Status.queued);

    const data = cmd.read.data;
    const sqe = try self.get_sqe();
    sqe.prep_read(data.fd, data.buffer, data.offset);
    const op = try self.add_op(cmd, status);
    sqe.user_data = @intFromPtr(op);
}

fn read_result(op: *Op, result: i32) void {
    assert(op.cmd.* == .read);

    if (result < 0) {
        const err = @as(std.posix.E, @enumFromInt(-result));

        op.cmd.read.result = switch (err) {
            .AGAIN => error.Retry,
            .BADF => error.BadFileDescriptor,
            .INTR => error.Retry,
            .ISDIR => error.IsDirectory,
            .NOBUFS => error.ResourceExhausted,
            .NOMEM => error.ResourceExhausted,
            .SPIPE => error.Unseekable,
            else => error.Unexpected,
        };

        return;
    }

    op.cmd.read.result = io_impl.ReadResult{
        .bytes_read = @intCast(result),
    };
}

pub fn write(self: *IO, cmd: *Command, status: *Status) void {
    _ = self;

    assert(cmd.* == .write);
    assert(status.* == Status.queued);

    status.* = .completed;
    cmd.write.result = io_impl.WriteResult{ .bytes_read = 10 };
    std.debug.print("Hello from write impl\n", .{});
}

fn write_result(op: *Op, result: i32) void {
    _ = op;
    _ = result;
}

test "can open directories and files" {
    var io = try IO.init();

    var dir = try std.fs.openDirAbsolute("/tmp", .{});
    const f = try dir.createFile("open_test.txt", .{ .read = true });
    f.close();
    dir.close();

    const open_dir_data = io_impl.OpenData{
        .dir_fd = 0,
        .path = "/tmp",
        .flags = .{},
        .mode = 744,
    };

    var cmd_dir = open_dir_data.to_cmd();
    var status_dir = Status.queued;
    try io.open(&cmd_dir, &status_dir);

    var count: usize = 0;
    while (status_dir != .completed) : (count += 1) {
        if (count > 5) {
            return error.ReadTookTooLong;
        }

        std.time.sleep(10 * std.time.ns_per_ms);
        io.tick();
    }

    if (cmd_dir.open.result == null) {
        return error.NoResult;
    }

    const result_dir = try cmd_dir.open.result.?;
    try expect(result_dir.fd > 0);

    const open_file_data = io_impl.OpenData{
        .dir_fd = 0,
        .path = "/tmp",
        .flags = .{},
        .mode = 744,
    };

    var cmd_file = open_file_data.to_cmd();
    var status_file = Status.queued;
    try io.open(&cmd_file, &status_file);

    count = 0;
    while (status_file != .completed) : (count += 1) {
        if (count > 5) {
            return error.ReadTookTooLong;
        }

        std.time.sleep(10 * std.time.ns_per_ms);
        io.tick();
    }

    if (cmd_file.open.result == null) {
        return error.NoResult;
    }

    const result_file = try cmd_file.open.result.?;
    try expect(result_file.fd > 0);
}

test "can read from a file" {
    var io = try IO.init();

    var dir = try std.fs.openDirAbsolute("/tmp", .{});
    defer dir.close();

    const f = try dir.createFile("read_test.txt", .{ .read = true });
    defer f.close();

    const expected = "Hello World";
    try f.writeAll(expected);

    var buffer: [16]u8 = undefined;
    const read_data = io_impl.ReadData{
        .buffer = &buffer,
        .fd = f.handle,
        .offset = 0,
    };

    var cmd = read_data.to_cmd();
    var status = Status.queued;
    try io.read(&cmd, &status);

    var buffer_offset: [16]u8 = undefined;
    const read_data_offset = io_impl.ReadData{
        .buffer = &buffer_offset,
        .fd = f.handle,
        .offset = 6,
    };

    var cmd_offset = read_data_offset.to_cmd();
    var status_offset = Status.queued;
    try io.read(&cmd_offset, &status_offset);

    var count: usize = 0;
    while (status != .completed or status_offset != .completed) : (count += 1) {
        if (count > 5) {
            return error.ReadTookTooLong;
        }

        std.time.sleep(10 * std.time.ns_per_ms);
        io.tick();
    }

    if (cmd.read.result == null or cmd_offset.read.result == null) {
        return error.NoResult;
    }

    const result = try cmd.read.result.?;
    const msg = buffer[0..result.bytes_read];
    try expect(std.mem.eql(u8, msg, expected));

    const result_offset = try cmd_offset.read.result.?;
    const msg_offset = buffer_offset[0..result_offset.bytes_read];
    try expect(std.mem.eql(u8, msg_offset, "World"));

    try dir.deleteFile("read_test.txt");
}
