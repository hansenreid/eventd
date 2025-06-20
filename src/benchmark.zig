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
var continuations: *[]IOLoop.Continuation = undefined;

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    const num_continuations = try std.math.divExact(comptime_int, gb, mb);
    var c: []IOLoop.Continuation = try allocator.alloc(IOLoop.Continuation, num_continuations + 1);
    continuations = &c;

    var io = try IO.init();

    var loop = IOLoop.init(&io);

    loop.open(
        0,
        "/home/reid/dev/personal/eventd/test.bin",
        .{},
        744,
        &continuations.*[0],
        open_rnd_callback,
    );

    while (!done) {
        if (read >= gb) break;
        loop.tick();
    }

    // const fd = try std.fs.cwd().createFile("test.bin", .{ .read = true });
    // defer fd.close();
    // try fd.writeAll(&buffer);
}

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
        const c = &continuations.*[count];

        const next: usize = i + mb;
        loop.read(result.fd, buffer[i..next], i, c, open_rnd_read_callback);

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
