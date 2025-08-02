const std = @import("std");
const assert = std.debug.assert;
const expect = std.testing.expect;
const linux = std.os.linux;
const std_io = std.io;
const posix = std.posix;
const IoUring = linux.IoUring;
const DoublyLinkedList = std.DoublyLinkedList;
const tracy = @import("../tracy.zig");

const io_impl = @import("../io.zig");
const Command = io_impl.Command;
const IOLoop = @import("../io_loop.zig");
const Continuation = IOLoop.Continuation;
const Status = IOLoop.Continuation.Status;
const SubmitError = io_impl.SubmitError;

pub const IO = @This();

pub const fd_t = linux.fd_t;
pub const open_flags = linux.O;
pub const mode_t = linux.mode_t;
pub const socket_t = fd_t;
pub const sockaddr_t = posix.sockaddr;
pub const socklen_t = posix.socklen_t;
pub const timespec_t = linux.kernel_timespec;

ring: IoUring,
count: usize,

pub fn init() !IO {
    return .{
        .ring = try IoUring.init(128, 0),
        .count = 0,
    };
}
//0      io_uring:io_uring_local_work_run
//0      io_uring:io_uring_short_write
//1      io_uring:io_uring_task_work_run
//0      io_uring:io_uring_cqe_overflow
//0      io_uring:io_uring_req_failed
//0      io_uring:io_uring_task_add
//0      io_uring:io_uring_poll_arm
//1      io_uring:io_uring_submit_req
//1      io_uring:io_uring_complete
//0      io_uring:io_uring_fail_link
//0      io_uring:io_uring_cqring_wait
//0      io_uring:io_uring_link
//0      io_uring:io_uring_defer
//0      io_uring:io_uring_queue_async_work
//0      io_uring:io_uring_file_get
//0      io_uring:io_uring_register
//1      io_uring:io_uring_create

pub fn tick(self: *IO) void {
    // std.debug.print("IO tick\n", .{});
    var tick_timeout: Continuation = undefined;
    const data = io_impl.TimeoutData{
        .ts = .{
            .sec = 1,
            .nsec = 0,
            // .nsec = std.time.ns_per_ms * 10,
        },
        .flags = 0,
    };

    tick_timeout.init(data.to_cmd(), Continuation.no_op);
    self.timeout(&tick_timeout) catch |err| {
        std.debug.panic("Error submitting timeout: {any}\n", .{err});
    };

    while (tick_timeout.status != .completed) {
        _ = self.ring.submit_and_wait(0) catch |err| {
            std.debug.panic("Error submitting: {any}\n", .{err});
        };

        var cqes: [128]linux.io_uring_cqe = undefined;
        const completed = self.ring.copy_cqes(&cqes, 0) catch |err| {
            std.debug.panic("Error getting cqes: {any}\n", .{err});
        };

        for (cqes[0..completed]) |cqe| {
            // TODO: assert that user data is not 0
            if (cqe.user_data == 0) continue;

            const c: *Continuation = @ptrFromInt(cqe.user_data);
            self.handle_complete(c, cqe.res);
        }
    }
}

fn handle_complete(self: *IO, c: *Continuation, result: i32) void {
    std.debug.print("Status: {any}\n", .{c.status});
    assert(c.status == .waiting);
    switch (c.command) {
        .accept => accept_result(c, result),
        .close => close_result(c, result),
        .open => open_result(c, result),
        .read => read_result(c, result),
        .write => write_result(c, result),
        .timeout => timeout_result(c, result),
    }

    c.status = .completed;
    self.count -= 1;
}

inline fn get_sqe(self: *IO) SubmitError!*linux.io_uring_sqe {
    return self.ring.get_sqe() catch |err| {
        switch (err) {
            error.SubmissionQueueFull => return SubmitError.Retry,
        }
    };
}

pub fn log(self: *IO, msg: []const u8) void {
    _ = self;

    std.debug.print("{s}\n", .{msg});
}

pub fn accept(self: *IO, c: *Continuation) SubmitError!void {
    assert(c.command == .accept);
    assert(c.status == Status.queued);

    const data = c.command.accept.data;

    const sqe = try self.get_sqe();
    sqe.prep_accept(
        data.socket,
        null,
        null,
        posix.SOCK.CLOEXEC,
    );

    sqe.user_data = @intFromPtr(c);
    self.count += 1;
}

pub fn accept_result(c: *Continuation, result: i32) void {
    assert(c.command == .accept);
    if (result < 0) {
        const err = @as(std.posix.E, @enumFromInt(-result));
        c.command.accept.result = switch (err) {
            .INTR => error.Retry,
            .AGAIN => error.WouldBlock,
            .BADF => error.FileDescriptorInvalid,
            .CONNABORTED => error.ConnectionAborted,
            .INVAL => error.SocketNotListening,
            .MFILE => error.ProcessFdQuotaExceeded,
            .NFILE => error.SystemFdQuotaExceeded,
            .NOBUFS => error.NoBufferSpace,
            .NOMEM => error.NoSpaceLeft,
            .NOTSOCK => error.FileDescriptorNotASocket,
            .OPNOTSUPP => error.OperationNotSupported,
            .PERM => error.PermissionDenied,
            .PROTO => error.ProtocolFailure,
            else => error.Unexpected,
        };

        return;
    }

    c.command.accept.result = io_impl.AcceptResult{
        .fd = @as(fd_t, result),
    };
}

pub fn close(self: *IO, c: *Continuation) SubmitError!void {
    assert(c.command == .close);
    assert(c.status == Status.queued);

    const data = c.command.close.data;

    const sqe = try self.get_sqe();
    sqe.prep_close(data.fd);
    sqe.user_data = @intFromPtr(c);
    self.count += 1;
}

fn close_result(c: *Continuation, result: i32) void {
    assert(c.command == .close);

    if (result < 0) {
        const err = @as(std.posix.E, @enumFromInt(-result));
        c.command.close.result = switch (err) {
            .BADF => error.FileDescriptorInvalid,
            .DQUOT => error.DiskQuota,
            .IO => error.InputOutput,
            .NOSPC => error.NoSpaceLeft,
            else => error.Unexpected,
        };

        return;
    }

    assert(result == 0);

    c.command.close.result = {};
}

pub fn open(self: *IO, c: *Continuation) SubmitError!void {
    assert(c.command == .open);
    assert(c.status == Status.queued);

    const data = c.command.open.data;

    const sqe = try self.get_sqe();
    sqe.prep_openat(data.dir_fd, data.path, data.flags, data.mode);
    sqe.user_data = @intFromPtr(c);
    self.count += 1;
}

fn open_result(c: *Continuation, result: i32) void {
    assert(c.command == .open);

    if (result < 0) {
        const err = @as(std.posix.E, @enumFromInt(-result));
        c.command.open.result = switch (err) {
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

    c.command.open.result = io_impl.OpenResult{
        .fd = @as(fd_t, result),
    };
}

pub fn read(self: *IO, c: *Continuation) SubmitError!void {
    assert(c.command == .read);
    assert(c.status == Status.queued);

    const data = c.command.read.data;

    const sqe = try self.get_sqe();
    sqe.prep_read(data.fd, data.buffer, data.offset);
    sqe.user_data = @intFromPtr(c);
    self.count += 1;
}

fn read_result(c: *Continuation, result: i32) void {
    assert(c.command == .read);

    if (result < 0) {
        const err = @as(std.posix.E, @enumFromInt(-result));

        c.command.read.result = switch (err) {
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

    c.command.read.result = io_impl.ReadResult{
        .bytes_read = @intCast(result),
    };
}

pub fn write(self: *IO, c: *Continuation) SubmitError!void {
    assert(c.command == .write);
    assert(c.status == Status.queued);

    const data = c.command.write.data;

    const sqe = try self.get_sqe();
    sqe.prep_write(data.fd, data.buffer, data.offset);
    sqe.user_data = @intFromPtr(c);
    self.count += 1;
}

fn write_result(c: *Continuation, result: i32) void {
    assert(c.command == .write);

    if (result < 0) {
        const err = @as(std.posix.E, @enumFromInt(-result));

        c.command.write.result = switch (err) {
            .AGAIN => error.WouldBlock,
            .BADF => error.NotOpenForWriting,
            .DQUOT => error.DiskQuotaExceeded,
            .FBIG => error.FileTooLarge,
            .INTR => error.Retry,
            .INVAL => error.InvalidArgument,
            .IO => error.InputOutput,
            .NOSPC => error.NoSpaceLeft,
            .NXIO => error.NoSuchDevice,
            .OVERFLOW => error.Overflow,
            .PERM => error.AccessDenied,
            .PIPE => error.BrokenPipe,
            .SPIPE => error.InvalidSeek,
            else => error.Unexpected,
        };

        return;
    }

    c.command.write.result = io_impl.WriteResult{
        .bytes_written = @intCast(result),
    };
}

pub fn timeout(self: *IO, c: *Continuation) SubmitError!void {
    assert(c.command == .timeout);
    assert(c.status == Status.queued);

    const data = c.command.timeout.data;

    const sqe = try self.get_sqe();
    sqe.prep_timeout(&data.ts, 3, data.flags);
    sqe.user_data = @intFromPtr(c);
    self.count += 1;
}

fn timeout_result(c: *Continuation, result: i32) void {
    assert(c.command == .timeout);
    assert(result < 0);

    const err = @as(std.posix.E, @enumFromInt(-result));

    c.command.timeout.result = switch (err) {
        .TIME => io_impl.TimeoutResult{},
        .INVAL => error.InvalidArgument,
        .FAULT => error.Fault,
        else => error.Unexpected,
    };

    return;
}

pub fn open_socket(self: *IO, family: u32) !linux.socket_t {
    _ = self;

    const fd = try posix.socket(
        family,
        posix.SOCK.STREAM | posix.SOCK.CLOEXEC,
        std.posix.IPPROTO.TCP,
    );
    errdefer posix.close(fd);

    return fd;
}

pub fn listen(
    self: *IO,
    fd: linux.socket_t,
    address: std.net.Address,
) !std.net.Address {
    _ = self;

    // TODO: Handle all options
    try posix.setsockopt(
        fd,
        posix.SOL.SOCKET,
        posix.SO.REUSEADDR,
        &std.mem.toBytes(@as(c_int, 1)),
    );

    try posix.bind(fd, &address.any, address.getOsSockLen());

    var resolved_address: std.net.Address = .{ .any = undefined };
    var addrlen: posix.socklen_t = @sizeOf(std.net.Address);
    try posix.getsockname(fd, &resolved_address.any, &addrlen);

    assert(resolved_address.getOsSockLen() == addrlen);
    assert(resolved_address.any.family == address.any.family);

    // TODO: magic number
    try posix.listen(fd, 128);

    return resolved_address;
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

test "can close a file or directory" {
    var io = try IO.init();
    var dir = try std.fs.openDirAbsolute("/tmp", .{});
    const f = try dir.createFile("close_test.txt", .{ .read = true });

    const close_file_data = io_impl.CloseData{
        .fd = f.handle,
    };

    var cmd_file = close_file_data.to_cmd();
    var status_file = Status.queued;
    try io.close(&cmd_file, &status_file);

    const close_dir_data = io_impl.CloseData{
        .fd = dir.fd,
    };

    var cmd_dir = close_dir_data.to_cmd();
    var status_dir = Status.queued;
    try io.close(&cmd_dir, &status_dir);

    var count: usize = 0;
    while (status_file != .completed or status_dir != .completed) : (count += 1) {
        if (count > 5) {
            return error.ReadTookTooLong;
        }

        std.time.sleep(10 * std.time.ns_per_ms);
        io.tick();
    }

    if (cmd_file.close.result == null or cmd_dir.close.result == null) {
        return error.NoResult;
    }

    const result_file = try cmd_file.close.result.?;
    try expect(result_file == {});

    const result_dir = try cmd_dir.close.result.?;
    try expect(result_dir == {});

    var dir_cleanup = try std.fs.openDirAbsolute("/tmp", .{});
    try dir_cleanup.deleteFile("close_test.txt");
    defer dir_cleanup.close();
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
test "can write to a file" {
    var io = try IO.init();

    var dir = try std.fs.openDirAbsolute("/tmp", .{});
    defer dir.close();

    const f = try dir.createFile("write_test.txt", .{ .read = true });
    defer f.close();

    const buffer: []const u8 = "Hello ";
    const write_data = io_impl.WriteData{
        .fd = f.handle,
        .buffer = buffer,
        .offset = 0,
    };

    var cmd = write_data.to_cmd();
    var status = Status.queued;
    try io.write(&cmd, &status);

    const buffer_offset: []const u8 = "World";
    const write_data_offset = io_impl.WriteData{
        .buffer = buffer_offset,
        .fd = f.handle,
        .offset = 6,
    };

    var cmd_offset = write_data_offset.to_cmd();
    var status_offset = Status.queued;
    try io.write(&cmd_offset, &status_offset);

    var count: usize = 0;
    while (status != .completed or status_offset != .completed) : (count += 1) {
        if (count > 5) {
            return error.WriteTookTooLong;
        }

        std.time.sleep(10 * std.time.ns_per_ms);
        io.tick();
    }

    if (cmd.write.result == null or cmd_offset.write.result == null) {
        return error.NoResult;
    }

    const result = try cmd.write.result.?;
    try expect(result.bytes_written == 6);

    const result_offset = try cmd_offset.write.result.?;
    try expect(result_offset.bytes_written == 5);

    var result_buffer: [11]u8 = undefined;
    const bytes_read = try f.readAll(&result_buffer);
    try expect(bytes_read == 11);
    try expect(std.mem.eql(u8, &result_buffer, "Hello World"));

    try dir.deleteFile("write_test.txt");
}
