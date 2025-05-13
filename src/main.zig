const builtin = @import("builtin");
const linux_io = @import("io/linux.zig");
const wasm_io = @import("io/wasm.zig");

pub fn main() !void {
    run();
}

export fn run() void {
    var io_impl = comptime blk: {
        switch (builtin.os.tag) {
            .linux, .wasi => break :blk linux_io{},
            .freestanding => break :blk wasm_io{},
            else => @compileError("Target not supported"),
        }
    };

    const io = io_impl.io();
    const msg: []const u8 = "Hello from impl";
    io.log(msg);
}
