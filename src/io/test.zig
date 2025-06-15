const std = @import("std");
const DoublyLinkedList = std.DoublyLinkedList;
const assert = std.debug.assert;

const io_impl = @import("../io.zig");
const Command = io_impl.Command;
const Status = @import("../io_loop.zig").Continuation.Status;

pub const IO = @This();

io_ops: DoublyLinkedList,
unused: DoublyLinkedList,
rand: std.Random,
count: u32,

const LIST_SIZE = 1000;
var list: [LIST_SIZE]Ops = undefined;

const Ops = struct {
    node: DoublyLinkedList.Node,
    status: *Status,
    cmd: *io_impl.Command,
    count: u8,
};

pub fn init() IO {
    const seed: u64 = 0x3b5f92f093d3071b;
    // try std.posix.getrandom(std.mem.asBytes(&seed));
    var prng = std.Random.DefaultPrng.init(seed);

    var unused: DoublyLinkedList = .{};
    for (&list) |*o| {
        o.node = .{};
        unused.append(&o.node);
    }

    return .{
        .io_ops = .{},
        .unused = unused,
        .rand = prng.random(),
        .count = 0,
    };
}

pub fn tick(self: *IO) void {
    var node = self.io_ops.first;

    // std.debug.print("IO count: {d}\n", .{self.count});
    while (node) |n| {
        const op: *Ops = @fieldParentPtr("node", n);

        // Need to set next before potentially destroying the memory
        node = n.next;
        if (op.count > self.rand.int(u4)) {
            self.complete(op);
        } else {
            op.count += 1;
        }
    }
}

pub fn log(self: *IO, msg: []const u8) void {
    _ = self;

    std.debug.print("{s}\n", .{msg});
}

pub fn complete(self: *IO, op: *Ops) void {
    op.status.* = .completed;
    self.io_ops.remove(&op.node);
    self.unused.append(&op.node);
    self.count -= 1;

    switch (op.cmd.*) {
        .write => write_result(op.cmd),
    }
}

pub fn write(self: *IO, cmd: *io_impl.Command, status: *Status) void {
    assert(cmd.* == .write);
    assert(status.* == Status.submitted);

    const node = self.unused.pop() orelse {
        // If we don't have any unused space, don't mark as .waiting
        // so that it gets resubmitted on the next tick
        return;
    };

    var op: *Ops = @fieldParentPtr("node", node);
    op.count = 0;
    op.status = status;
    op.cmd = cmd;

    self.io_ops.append(&op.node);
    status.* = .waiting;
    self.count += 1;
}

pub fn write_result(cmd: *io_impl.Command) void {
    assert(cmd.* == .write);
    cmd.write.result = io_impl.WriteResult{ .bytes_read = 10 };
}
