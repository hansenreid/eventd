const std = @import("std");
const builtin = @import("builtin");
const pg_wire = @import("pg-wire.zig");
const network = @import("network.zig");
const IOLoop = @import("io_loop.zig");

const net = std.net;
const posix = std.posix;

const io_impl = @import("io.zig");
const IO = io_impl.IO;
const Command = io_impl.Command;

const tracy = @import("tracy.zig");

var done = false;
pub fn main() !void {
    var io = try IO.init();

    const address = try std.net.Address.parseIp("127.0.0.1", 5678);
    const fd = try io.open_socket(address.any.family);
    defer posix.close(fd);

    const resolved_address = try io.listen(fd, address);
    _ = resolved_address;

    var loop = IOLoop.init(&io);
    var continuations: [10]IOLoop.Continuation = undefined;

    loop.accept(fd, address.any, address.getOsSockLen(), &continuations[0], dummy);

    while (!done) {
        loop.tick();
        std.debug.print("Ticking\n", .{});
        std.Thread.sleep(std.time.ns_per_s);
    }
}

fn dummy(context: *anyopaque, continuation: *IOLoop.Continuation) void {
    const loop: *IOLoop = @ptrCast(@alignCast(context));
    _ = loop;

    std.debug.print("result: {any}\n", .{continuation.status});
    std.debug.print("result: {any}\n", .{continuation.command.accept.result});

    done = true;
}
