const std = @import("std");
const builtin = @import("builtin");
const linux_io = @import("io/linux.zig");
const wasm_io = @import("io/wasm.zig");
const pg_wire = @import("pg-wire.zig");
const network = @import("network.zig");

pub fn main() !void {
    run();
}

export fn run() void {
    // var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    // const allocator = gpa.allocator();

    // var params = std.StringHashMap([]const u8).init(allocator);
    // defer params.deinit();
    // _ = params.put("Hello", "World") catch unreachable;

    var io_impl = comptime blk: {
        switch (builtin.os.tag) {
            .linux, .wasi => break :blk linux_io{},
            .freestanding => break :blk wasm_io{},
            else => @compileError("Target not supported"),
        }
    };

    const io = io_impl.io();
    io.log("Hello There");

    const bytes = [_]u8{ 0x08, 0x00, 0x00, 0x00, 0x03, 0x00, 0x00, 0x00 };
    const non_empty = network.NonEmptyBytes.init(&bytes);

    pg_wire.Startup.deserialize(non_empty) catch |err| {
        std.debug.print("err: {any}\n", .{err});
        io.log("Failed to parse startup message");
    };
}
