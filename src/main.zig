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
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    var io_impl = comptime blk: {
        switch (builtin.os.tag) {
            .linux, .wasi => break :blk linux_io{},
            .freestanding => break :blk wasm_io{},
            else => @compileError("Target not supported"),
        }
    };

    const io = io_impl.io();

    var bytes = [_]u8{
        0x11,
        0x00,
        0x00,
        0x00,
        0x03,
        0x00,
        0x00,
        0x00,
        'u',
        's',
        'e',
        'r',
        0x00,
        'b',
        'o',
        'b',
        0x00,
    };

    var non_empty = network.NonEmptyBytes.init(&bytes);
    var d = network.Deserializer.init(&non_empty);

    const startup = pg_wire.Startup.deserialize(allocator, &d) catch |err| {
        std.debug.print("err: {any}\n", .{err});
        io.log("Failed to parse startup message\n");
        return;
    };

    std.debug.print("major version: {d}\n", .{startup.major_version});
    std.debug.print("minor version: {d}\n", .{startup.minor_version});
    std.debug.print("user: {?s}\n", .{startup.params.map.get("user")});
    std.debug.print("database: {?s}\n", .{startup.params.map.get("database")});

    var write_buffer: [256]u8 = undefined;
    var non_empty2 = network.NonEmptyBytes.init(&write_buffer);
    var serializer = network.Serializer.init(&non_empty2);

    const value: u16 = 0x1234;
    std.debug.print("Starting: 0x{x}\n", .{value});

    serializer.write_int(u16, value) catch |err| {
        std.debug.print("Error serializing: {any}\n", .{err});
    };

    var deserializer = network.Deserializer.init(&non_empty2);
    const result = deserializer.next_int(u16) catch |err| {
        std.debug.print("Error deserializing : {any}\n", .{err});
        return;
    };

    std.debug.print("Result: 0x{x}\n", .{result});
}
