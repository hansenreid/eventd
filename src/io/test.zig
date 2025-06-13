const std = @import("std");
const DoublyLinkedList = std.DoublyLinkedList;
const assert = std.debug.assert;

const io_impl = @import("../io.zig");
const Command = io_impl.Command;
const Status = Command.Status;

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
            op.status.* = .completed;
            self.io_ops.remove(n);
            self.unused.append(n);
            self.count -= 1;
        } else {
            op.count += 1;
        }
    }
}

pub fn log(self: *IO, msg: []const u8) void {
    _ = self;

    std.debug.print("{s}\n", .{msg});
}

pub fn write(self: *IO, write_command: Command.WriteCommand, status: *Status) void {
    _ = write_command;

    assert(status.* == Status.submitted);

    // TODO: Figure out error handling
    const node = self.unused.pop() orelse {
        unreachable;
    };

    var op: *Ops = @fieldParentPtr("node", node);
    op.count = 0;
    op.status = status;

    self.io_ops.append(&op.node);
    status.* = .waiting;
    self.count += 1;
}
