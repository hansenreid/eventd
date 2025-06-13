const std = @import("std");
const builtin = @import("builtin");
const pg_wire = @import("pg-wire.zig");
const IO = @import("io.zig").IO;
const network = @import("network.zig");
const IOLoop = @import("io_loop.zig");
const commands = @import("io_commands.zig");

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
    var write = commands.WriteCommand.init(&buffer) catch {
        unreachable;
    };

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
