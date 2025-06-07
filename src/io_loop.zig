const std = @import("std");
const DoublyLinkedList = std.DoublyLinkedList;
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;
const commands = @import("io_commands.zig");

const IO = @import("io.zig");

pub const IOLoop = @This();
pub const callback_t: type = *const fn (context: *anyopaque) void;

allocator: Allocator,
io: *IO,
count: u32,
continuations: DoublyLinkedList,

fn assert_invariants(self: *IOLoop) void {
    _ = self;
}

pub fn init(allocator: Allocator, io: *IO) IOLoop {
    var loop = IOLoop{
        .allocator = allocator,
        .io = io,
        .count = 0,
        .continuations = .{},
    };

    loop.assert_invariants();
    return loop;
}

pub fn tick(self: *IOLoop) !void {
    self.assert_invariants();

    var node = self.continuations.first;
    var count: usize = 0;
    while (node) |n| {
        std.debug.print("Hello from node {d}\n", .{count});
        const c: *Continuation = @fieldParentPtr("node", n);

        switch (c.status) {
            .submitted => try self.handle_submitted(c),
            .waiting => std.debug.print("Waiting not implemented", .{}),
            .completed => try self.handle_completed(c),
        }

        // IO should mark the command as waiting or completed
        assert(c.status == commands.Status.waiting or c.status == commands.Status.completed);

        count += 1;
        node = n.next;
    }

    self.io.tick();

    self.assert_invariants();
}

fn handle_submitted(self: *IOLoop, continuation: *Continuation) !void {
    switch (continuation.command.*) {
        .write => self.io.write(continuation.command.write, &continuation.status),
    }
}

fn handle_completed(self: *IOLoop, continuation: *Continuation) !void {
    _ = self;
    continuation.callback(continuation);
}

pub fn enqueue(self: *IOLoop, command: *commands.Command, callback: callback_t, result: *anyopaque) !void {
    self.assert_invariants();

    // TODO deinit
    var continuation = try self.allocator.create(Continuation);
    continuation.init(command, callback, result);

    self.continuations.append(&continuation.node);

    self.count += 1;

    self.assert_invariants();
}

pub const Continuation = struct {
    command: *commands.Command,
    status: commands.Status,
    node: DoublyLinkedList.Node,
    callback: callback_t,
    result: *anyopaque,

    pub fn init(ptr: *Continuation, command: *commands.Command, callback: callback_t, result: *anyopaque) void {
        ptr.status = .submitted;
        ptr.command = command;
        ptr.callback = callback;
        ptr.result = result;
    }
};
