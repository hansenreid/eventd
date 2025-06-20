const std = @import("std");
const builtin = @import("builtin");
const pg_wire = @import("pg-wire.zig");
const network = @import("network.zig");
const IOLoop = @import("io_loop.zig");

const io_impl = @import("io.zig");
const IO = io_impl.IO;
const Command = io_impl.Command;

const tracy = @import("tracy.zig");

pub fn main() !void {
    run();
}

fn dummy(context: *anyopaque, continuation: *IOLoop.Continuation) void {
    const loop: *IOLoop = @ptrCast(@alignCast(context));
    _ = loop;

    std.debug.print("result: {any}\n", .{continuation.status});
    std.debug.print("result: {any}\n", .{continuation.command.write.result});

    std.debug.print("Hello from a dummy function\n", .{});
}

export fn run() void {
    var buffer: [256]u8 = undefined;

    var io = IO.init() catch {
        unreachable;
    };

    var loop = IOLoop.init(&io);
    var c: IOLoop.Continuation = undefined;
    loop.write(3, &buffer, 0, &c, dummy);

    loop.tick();
    loop.tick();
}
