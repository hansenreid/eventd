const std = @import("std");
const DoublyLinkedList = std.DoublyLinkedList;
const assert = std.debug.assert;
const IO = @import("../io.zig");
const commands = @import("../io_commands.zig");
const Allocator = std.mem.Allocator;

pub const test_io = @This();

allocator: Allocator,
io_ops: DoublyLinkedList,
unused: DoublyLinkedList,
rand: std.Random,
count: u32,

const LIST_SIZE = 1000;
var list: [LIST_SIZE]Ops = undefined;

const Ops = struct {
    node: DoublyLinkedList.Node,
    status: *commands.Status,
    count: u8,
};

pub fn init(allocator: Allocator, rand: std.Random) test_io {
    var unused: DoublyLinkedList = .{};
    for (&list) |*o| {
        o.node = .{};
        unused.append(&o.node);
    }

    return .{
        .allocator = allocator,
        .io_ops = .{},
        .unused = unused,
        .rand = rand,
        .count = 0,
    };
}

pub fn io(self: *test_io) IO {
    return .{
        .ptr = self,
        .vtable = &IO.VTable{
            .tick = tick,
            .logFn = log,
            .writeFn = write,
        },
    };
}

fn tick(ptr: *anyopaque) void {
    const self: *test_io = @ptrCast(@alignCast(ptr));
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

fn log(ptr: *anyopaque, msg: []const u8) void {
    const self: *test_io = @ptrCast(@alignCast(ptr));
    _ = self;

    std.debug.print("{s}\n", .{msg});
}

fn write(ptr: *anyopaque, write_command: commands.WriteCommand, status: *commands.Status) void {
    _ = write_command;

    assert(status.* == commands.Status.submitted);
    const self: *test_io = @ptrCast(@alignCast(ptr));

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
