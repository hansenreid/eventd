const std = @import("std");
const assert = std.debug.assert;
const linux = std.os.linux;
const IoUring = linux.IoUring;
const DoublyLinkedList = std.DoublyLinkedList;

const io_impl = @import("../io.zig");
const Command = io_impl.Command;
const Status = @import("../io_loop.zig").Continuation.Status;
const SubmitError = io_impl.SubmitError;

pub const IO = @This();

// TODO: Move to a different implementation?
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
    const submitted = self.ring.submit_and_wait(0) catch |err| {
        std.debug.panic("Error submitting: {any}\n", .{err});
    };

    std.debug.print("Submitted {d} requests\n", .{submitted});

    var cqes: [128]linux.io_uring_cqe = undefined;
    const completed = self.ring.copy_cqes(&cqes, 0) catch |err| {
        std.debug.panic("Error getting cqes: {any}\n", .{err});
    };

    std.debug.print("Got {d} completed requests\n", .{completed});

    for (cqes[0..completed]) |cqe| {
        if (cqe.user_data == 0) continue;

        const op: *Op = @ptrFromInt(cqe.user_data);
        self.handle_complete(op, cqe.res);
    }
}

fn handle_complete(self: *IO, op: *Op, result: i32) void {
    switch (op.cmd.*) {
        .read => read_result(op, result),
        .write => write_result(op, result),
    }
    op.status.* = .completed;
    self.ops.remove(&op.node);
}

inline fn get_sqe(self: *IO) SubmitError!*linux.io_uring_sqe {
    return self.ring.get_sqe() catch |err| {
        switch (err) {
            error.SubmissionQueueFull => return SubmitError.TryAgainLater,
        }
    };
}

inline fn add_op(self: *IO, cmd: *Command, status: *Status) SubmitError!*Op {
    const node = self.unused.pop() orelse {
        return SubmitError.TryAgainLater;
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

pub fn read(self: *IO, cmd: *Command, status: *Status) !void {
    assert(cmd.* == .read);
    assert(status.* == Status.submitted);

    const data = cmd.read.data;
    const sqe = try self.get_sqe();
    sqe.prep_read(data.fd, data.buffer, data.offset);
    const op = try self.add_op(cmd, status);
    sqe.user_data = @intFromPtr(op);
}

fn read_result(op: *Op, result: i32) void {
    _ = op;
    _ = result;
}

pub fn write(self: *IO, cmd: *Command, status: *Status) void {
    _ = self;

    assert(cmd.* == .write);
    assert(status.* == Status.submitted);

    status.* = .completed;
    cmd.write.result = io_impl.WriteResult{ .bytes_read = 10 };
    std.debug.print("Hello from write impl\n", .{});
}

fn write_result(op: *Op, result: i32) void {
    _ = op;
    _ = result;
}
