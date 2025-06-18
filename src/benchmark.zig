const std = @import("std");
const assert = std.debug.assert;
const IOLoop = @import("io_loop.zig");

const io_impl = @import("io.zig");
const IO = io_impl.IO;
const Command = io_impl.Command;

var done = false;
var read: usize = 0;
const gb = 1073741824;
const mb = 1048576;

var buffer: [gb]u8 = undefined;

pub fn main() !void {
    var io = try IO.init();

    var loop = IOLoop.init(&io);
    try read_from_rnd(&loop);
    while (!done) {
        if (read >= gb) break;
        loop.tick();
    }

    // const fd = try std.fs.cwd().createFile("test.bin", .{ .read = true });
    // defer fd.close();
    // try fd.writeAll(&buffer);
}

fn read_from_rnd(loop: *IOLoop) !void {
    const open_data = io_impl.OpenData{
        .dir_fd = 0,
        .path = "/home/reid/dev/personal/eventd/test.bin",
        .flags = .{},
        .mode = 744,
    };

    const cmd = open_data.to_cmd();
    try loop.enqueue(cmd, open_rnd_callback);
}

//TODO: Just deal with continuations instead of commands?
fn open_rnd_callback(context: *anyopaque, continuation: *IOLoop.Continuation) void {
    assert(continuation.command == .open);
    assert(continuation.command.open.result != null);

    const loop: *IOLoop = @ptrCast(@alignCast(context));

    const result = continuation.command.open.result.? catch |err| {
        std.debug.print("Error opening file: {any}\n", .{err});
        done = true;
        return;
    };

    var i: usize = 0;
    var count: usize = 0;
    while (i < gb) {
        count += 1;

        const next: usize = i + mb;
        const read_data = io_impl.ReadData{
            .buffer = buffer[i..next],
            .fd = result.fd,
            .offset = 0,
        };

        const cmd = read_data.to_cmd();
        loop.enqueue(cmd, open_rnd_read_callback) catch |err| {
            switch (err) {
                error.NoFreeContinuations => std.debug.panic("No Free Continuations", .{}),
            }
        };

        i = next;
    }
}

fn open_rnd_read_callback(context: *anyopaque, continuation: *IOLoop.Continuation) void {
    _ = context;

    assert(continuation.command == .read);
    assert(continuation.command.read.result != null);

    const result = continuation.command.read.result.? catch |err| {
        std.debug.print("Error reading file: {any}\n", .{err});
        done = true;
        return;
    };

    read += result.bytes_read;
}
