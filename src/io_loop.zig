const std = @import("std");
const DoublyLinkedList = std.DoublyLinkedList;
const assert = std.debug.assert;
const tracy = @import("tracy.zig");
const RingBuffer = std.RingBuffer;

const io_impl = @import("io.zig");
const IO = io_impl.IO;
const Command = io_impl.Command;

pub const IOLoop = @This();

io: *IO,
count: u32,
continuations: DoublyLinkedList,

fn assert_invariants(self: *IOLoop) void {
    _ = self;
}

pub fn init(io: *IO) IOLoop {
    var loop = IOLoop{
        .io = io,
        .count = 0,
        .continuations = .{},
    };

    loop.assert_invariants();
    return loop;
}

pub fn tick(self: *IOLoop) void {
    self.assert_invariants();
    tracy.frameMarkNamed("IO Loop Tick");
    var trace = tracy.traceNamed(@src(), "IO Loop Tick");
    defer trace.end();

    var node = self.continuations.first;
    while (node) |n| {
        const c: *Continuation = @fieldParentPtr("node", n);

        // Need to set next before potentially removing
        // the current node on completion
        node = n.next;
        switch (c.status) {
            .queued => self.handle_queued(c),
            .waiting => {},
            .completed => self.handle_completed(c),
        }
    }

    self.io.tick();

    self.assert_invariants();
}

fn handle_queued(self: *IOLoop, c: *Continuation) void {
    var trace = tracy.traceNamed(@src(), "handle submitted");
    defer trace.end();

    const err = switch (c.command) {
        .accept => self.io.accept(c),
        .close => self.io.close(c),
        .open => self.io.open(c),
        .write => self.io.write(c),
        .read => self.io.read(c),
    };

    c.status = .waiting;

    err catch |e| {
        var err_trace = tracy.traceNamed(@src(), "handle retry");

        switch (e) {
            error.Retry => {
                c.status = .queued;
                self.io.tick();
            },
            else => std.debug.panic("Error submitting: {any}\n", .{e}),
        }

        err_trace.end();
    };
}

fn handle_completed(self: *IOLoop, continuation: *Continuation) void {
    var trace = tracy.traceNamed(@src(), "handle completed");
    defer trace.end();

    continuation.callback(self, continuation);
    self.continuations.remove(&continuation.node);
    self.count -= 1;
}

pub fn enqueue(
    self: *IOLoop,
    continuation: *Continuation,
) void {
    self.assert_invariants();
    assert(continuation.status == .queued);

    self.continuations.append(&continuation.node);
    self.count += 1;

    self.assert_invariants();
}

pub const Continuation = struct {
    command: Command,
    status: Status,
    node: DoublyLinkedList.Node,
    callback: *const fn (context: *anyopaque, continuation: *Continuation) void,

    pub const Status = enum {
        queued,
        waiting,
        completed,
    };

    pub fn init(
        ptr: *Continuation,
        command: Command,
        callback: *const fn (context: *anyopaque, continuation: *Continuation) void,
    ) void {
        ptr.status = .queued;
        ptr.command = command;
        ptr.callback = callback;
    }
};

pub fn accept(
    self: *IOLoop,
    socket: IO.socket_t,
    address: IO.sockaddr_t,
    address_size: IO.socklen_t,
    continuation: *Continuation,
    callback: *const fn (context: *anyopaque, continuation: *Continuation) void,
) void {
    _ = address;
    _ = address_size;
    const data = io_impl.AcceptData{
        .socket = socket,
        .address = undefined,
        .address_size = @sizeOf(std.posix.sockaddr),
    };

    continuation.init(data.to_cmd(), callback);
    self.enqueue(continuation);
}

pub fn open(
    self: *IOLoop,
    dir_fd: IO.fd_t,
    path: [*:0]const u8,
    flags: IO.open_flags,
    mode: IO.mode_t,
    continuation: *Continuation,
    callback: *const fn (context: *anyopaque, continuation: *Continuation) void,
) void {
    const data = io_impl.OpenData{
        .dir_fd = dir_fd,
        .path = path,
        .flags = flags,
        .mode = mode,
    };

    continuation.init(data.to_cmd(), callback);
    self.enqueue(continuation);
}

pub fn read(
    self: *IOLoop,
    fd: IO.fd_t,
    buffer: []u8,
    offset: u64,
    continuation: *Continuation,
    callback: *const fn (context: *anyopaque, continuation: *Continuation) void,
) void {
    const data = io_impl.ReadData{
        .fd = fd,
        .buffer = buffer,
        .offset = offset,
    };

    continuation.init(data.to_cmd(), callback);
    self.enqueue(continuation);
}

pub fn write(
    self: *IOLoop,
    fd: IO.fd_t,
    buffer: []u8,
    offset: u64,
    continuation: *Continuation,
    callback: *const fn (context: *anyopaque, continuation: *Continuation) void,
) void {
    const data = io_impl.WriteData{
        .fd = fd,
        .buffer = buffer,
        .offset = offset,
    };

    continuation.init(data.to_cmd(), callback);
    self.enqueue(continuation);
}

pub fn close(
    self: *IOLoop,
    fd: IO.fd_t,
    continuation: *Continuation,
    callback: *const fn (context: *anyopaque, continuation: *Continuation) void,
) void {
    const data = io_impl.CloseData{
        .fd = fd,
    };

    continuation.init(data.to_cmd(), callback);
    self.enqueue(continuation);
}
