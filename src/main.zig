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

    var io_impl = comptime blk: {
        switch (builtin.os.tag) {
            .linux, .wasi => break :blk linux_io{},
            .freestanding => break :blk wasm_io{},
            else => @compileError("Target not supported"),
        }
    };

    const io = io_impl.io();
    io.log("Hello There");
}
