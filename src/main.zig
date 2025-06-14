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

fn dummy(context: *anyopaque) void {
    const continuation: *IOLoop.Continuation = @ptrCast(@alignCast(context));

    std.debug.print("result: {any}\n", .{continuation.status});

    std.debug.print("Hello from a dummy function\n", .{});
}

export fn run() void {
    const allocator = std.heap.page_allocator;

    const buffer: [256]u8 = undefined;

    var io = IO.init();
    var loop = IOLoop.init(allocator, &io);
    const write_data = io_impl.WriteData{
        .buffer = &buffer,
        .fd = 0,
    };

    var write = write_data.to_cmd();

    loop.enqueue(&write, dummy) catch {
        unreachable;
    };

    loop.tick() catch {
        unreachable;
    };

    loop.tick() catch {
        unreachable;
    };
}
