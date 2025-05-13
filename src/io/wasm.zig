const IO = @import("../io.zig");

extern fn jsLog(ptr: [*]const u8, len: usize) void;

pub const wasm_io = @This();

pub fn io(self: *wasm_io) IO {
    return .{
        .ptr = self,
        .vtable = &IO.VTable{
            .logFn = log,
        },
    };
}

fn log(ptr: *anyopaque, msg: []const u8) void {
    const self: *wasm_io = @ptrCast(@alignCast(ptr));
    _ = self;

    jsLog(msg.ptr, msg.len);
}
