const std = @import("std");
const builtin = @import("builtin");
const linux_io = @import("io/linux.zig");
const wasm_io = @import("io/wasm.zig");
const pg_wire = @import("pg-wire.zig");
const network = @import("network.zig");

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

    const bytes = [_]u8{ 0x12, 0x32, 0x32, 0x12 };
    const non_empty = network.NonEmptyBytes.init(&bytes);
    var deserializer = network.Deserializer.init(non_empty);
    std.debug.print("{x}\n", .{deserializer.next_int(u16).int});
    std.debug.print("{x}\n", .{deserializer.next_int(u8).int});
    std.debug.print("{x}\n", .{deserializer.next_int(u8).int});
}
