const std = @import("std");
const DoublyLinkedList = std.DoublyLinkedList;
const assert = std.debug.assert;
const IO = @import("../io.zig");
const commands = @import("../io_commands.zig");
const Allocator = std.mem.Allocator;

pub const test_io = @This();

allocator: Allocator,
io_ops: DoublyLinkedList,
rand: std.Random,
count: u32,

const Ops = struct {
    node: DoublyLinkedList.Node,
    status: *commands.Status,
    count: u8,
};

pub fn init(allocator: Allocator, rand: std.Random) test_io {
    return .{
        .allocator = allocator,
        .io_ops = .{},
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
            self.allocator.destroy(op);
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

    // TODO: figure out error handling
    var op = self.allocator.create(Ops) catch {
        unreachable;
    };
    op.node = .{};
    op.count = 0;
    op.status = status;

    self.io_ops.append(&op.node);
    status.* = .waiting;
    self.count += 1;
}
