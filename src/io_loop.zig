const std = @import("std");
const DoublyLinkedList = std.DoublyLinkedList;
const assert = std.debug.assert;
const tracy = @import("tracy.zig");
const RingBuffer = std.RingBuffer;

const io_impl = @import("io.zig");
const IO = io_impl.IO;
const Command = io_impl.Command;
const SubmitError = io_impl.SubmitError;

pub const IOLoop = @This();
pub const callback_t: type = *const fn (context: *anyopaque) void;

io: *IO,
count: u32,
continuations: DoublyLinkedList,
unused: DoublyLinkedList,

const LIST_SIZE = 1000;
var list: [LIST_SIZE]Continuation = undefined;

fn assert_invariants(self: *IOLoop) void {
    _ = self;
}

pub fn init(io: *IO) IOLoop {
    var unused: DoublyLinkedList = .{};
    for (&list) |*c| {
        c.node = .{};
        unused.append(&c.node);
    }

    var loop = IOLoop{
        .io = io,
        .count = 0,
        .continuations = .{},
        .unused = unused,
    };

    loop.assert_invariants();
    return loop;
}

pub fn tick(self: *IOLoop) void {
    self.assert_invariants();
    tracy.frameMark();

    var node = self.continuations.first;
    var count: usize = 0;
    while (node) |n| {
        const c: *Continuation = @fieldParentPtr("node", n);

        // Need to set next before potentially removing
        // the current node on completion
        node = n.next;
        switch (c.status) {
            .queued => self.handle_submitted(c),
            .waiting => {},
            .completed => self.handle_completed(c),
        }

        count += 1;
    }

    self.io.tick();

    self.assert_invariants();
}

fn handle_submitted(self: *IOLoop, c: *Continuation) void {
    const err = switch (c.command.*) {
        .open => self.io.open(c.command, &c.status),
        .write => self.io.write(c.command, &c.status),
        .read => self.io.read(c.command, &c.status),
    };

    err catch |e| {
        switch (e) {
            error.Retry => return,
            else => std.debug.panic("Error submitting: {any}\n", .{e}),
        }
    };
}

fn handle_completed(self: *IOLoop, continuation: *Continuation) void {
    continuation.callback(continuation);
    self.continuations.remove(&continuation.node);
    self.unused.append(&continuation.node);
    self.count -= 1;
}

pub fn enqueue(self: *IOLoop, command: *Command, callback: callback_t) !void {
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
    command: *Command,
    status: Status,
    node: DoublyLinkedList.Node,
    callback: callback_t,

    pub const Status = enum {
        queued,
        waiting,
        completed,
    };

    pub fn init(ptr: *Continuation, command: *Command, callback: callback_t) void {
        ptr.status = .queued;
        ptr.command = command;
        ptr.callback = callback;
    }
};
