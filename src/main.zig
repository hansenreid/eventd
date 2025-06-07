const std = @import("std");
const builtin = @import("builtin");
const linux_io = @import("io/linux.zig");
const wasm_io = @import("io/wasm.zig");
const pg_wire = @import("pg-wire.zig");
const network = @import("network.zig");
const IOLoop = @import("io_loop.zig");
const commands = @import("io_commands.zig");

pub fn main() !void {
    run();
}

fn dummy(context: *anyopaque) void {
    const continuation: *IOLoop.Continuation = @ptrCast(@alignCast(context));
    const r: *commands.WriteCommand.WriteResult = @ptrCast(@alignCast(continuation.result));
    r.code = 0;

    std.debug.print("result: {any}\n", .{r});

    std.debug.print("Hello from a dummy function\n", .{});
}

export fn run() void {
    const allocator = std.heap.page_allocator;

    var io_impl = comptime blk: {
        switch (builtin.os.tag) {
            .linux, .wasi => break :blk linux_io{},
            .freestanding => break :blk wasm_io{},
            else => @compileError("Target not supported"),
        }
    };

    const buffer: [256]u8 = undefined;

    var io = io_impl.io();
    var loop = IOLoop.init(allocator, &io);
    var write = commands.WriteCommand.init(allocator, &buffer) catch {
        unreachable;
    };

    loop.enqueue(&write, dummy, write.write.result) catch {
        unreachable;
    };

    loop.tick() catch {
        unreachable;
    };

    loop.tick() catch {
        unreachable;
    };
}
