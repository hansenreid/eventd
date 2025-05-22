const std = @import("std");
const builtin = @import("builtin");
const linux_io = @import("io/linux.zig");
const wasm_io = @import("io/wasm.zig");
const pg_wire = @import("pg-wire.zig").PGWire;

const native_endian = @import("builtin").target.cpu.arch.endian();

pub fn main() !void {
    run();
}

export fn run() void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    var params = std.StringHashMap([]const u8).init(allocator);
    defer params.deinit();
    _ = params.put("Hello", "World") catch unreachable;

    const startup = pg_wire.Startup{
        .version = 0,
        .params = params,
    };

    var io_impl = comptime blk: {
        switch (builtin.os.tag) {
            .linux, .wasi => break :blk linux_io{},
            .freestanding => break :blk wasm_io{},
            else => @compileError("Target not supported"),
        }
    };

    const io = io_impl.io();
    std.debug.print("{any}\n", .{startup.params.count()});
    io.log("Hello There");

    const native = pg_wire.NativeInt(u16).init(0x1234);
    const network = pg_wire.NetworkInt(u16).from_native(native);
    std.debug.print("{x}\n", .{native.bytes()});
    std.debug.print("{x}\n", .{network.bytes()});

    const network2 = pg_wire.NetworkInt(u16).init(0x1234);
    const native2 = pg_wire.NativeInt(u16).from_network(network2);
    std.debug.print("{x}\n", .{native2.bytes()});
    std.debug.print("{x}\n", .{network2.bytes()});
}
