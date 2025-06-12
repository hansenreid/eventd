const std = @import("std");
const DoublyLinkedList = std.DoublyLinkedList;
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;
const commands = @import("io_commands.zig");
const tracy = @import("tracy.zig");

const IO = @import("io.zig");

pub const IOLoop = @This();
pub const callback_t: type = *const fn (context: *anyopaque) void;

allocator: Allocator,
io: *IO,
count: u32,
continuations: DoublyLinkedList,
unused: DoublyLinkedList,

const LIST_SIZE = 1000;
var list: [LIST_SIZE]Continuation = undefined;

fn assert_invariants(self: *IOLoop) void {
    _ = self;
}

pub fn init(allocator: Allocator, io: *IO) IOLoop {
    var unused: DoublyLinkedList = .{};
    for (&list) |*c| {
        c.node = .{};
        unused.append(&c.node);
    }

    var loop = IOLoop{
        .allocator = allocator,
        .io = io,
        .count = 0,
        .continuations = .{},
        .unused = unused,
    };

    loop.assert_invariants();
    return loop;
}

pub fn tick(self: *IOLoop) !void {
    self.assert_invariants();

    var node = self.continuations.first;
    var count: usize = 0;
    // std.debug.print("IO Loop count: {d}\n", .{self.count});
    while (node) |n| {
        const c: *Continuation = @fieldParentPtr("node", n);

        // Need to set next before potentially destroying the memory
        node = n.next;
        switch (c.status) {
            .submitted => try self.handle_submitted(c),
            .waiting => {},
            .completed => try self.handle_completed(c),
        }

        count += 1;
    }

    self.io.tick();

    self.assert_invariants();
}

fn handle_submitted(self: *IOLoop, c: *Continuation) !void {
    switch (c.command.*) {
        .write => self.io.write(c.command.write, &c.status),
    }

    // IO should mark the command as waiting or completed
    assert(c.status == commands.Status.waiting or c.status == commands.Status.completed);
}

fn handle_completed(self: *IOLoop, continuation: *Continuation) !void {
    continuation.callback(continuation);
    self.continuations.remove(&continuation.node);
    self.unused.append(&continuation.node);
    self.count -= 1;
}

pub fn enqueue(self: *IOLoop, command: *commands.Command, callback: callback_t) !void {
    self.assert_invariants();

    const node = self.unused.pop() orelse {
        return error.NoFreeContinuations;
    };

    var c: *Continuation = @fieldParentPtr("node", node);

    c.init(command, callback);

    self.continuations.append(&c.node);

    self.count += 1;

    self.assert_invariants();
}

pub const Continuation = struct {
    command: *commands.Command,
    status: commands.Status,
    node: DoublyLinkedList.Node,
    callback: callback_t,

    pub fn init(ptr: *Continuation, command: *commands.Command, callback: callback_t) void {
        ptr.status = .submitted;
        ptr.command = command;
        ptr.callback = callback;
    }
};
