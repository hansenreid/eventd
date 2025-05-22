const std = @import("std");
const assert = std.debug.assert;

pub const PGWire = @This();

pub fn NetworkInt(comptime T: type) type {
    if (@typeInfo(T) != .int) {
        @compileError("only ints accepted");
    }

    return struct {
        int: T,
        const this = @This();

        pub fn bytes(self: this) T {
            return self.int;
        }

        pub fn init(int: T) this {
            return .{
                .int = int,
            };
        }

        pub fn from_native(native: NativeInt(T)) this {
            return init(std.mem.nativeToBig(T, native.int));
        }
    };
}

pub fn NativeInt(comptime T: type) type {
    if (@typeInfo(T) != .int) {
        @compileError("only ints accepted");
    }

    return struct {
        int: T,
        const this = @This();

        pub fn bytes(self: this) T {
            return self.int;
        }

        pub fn init(int: T) this {
            return .{
                .int = int,
            };
        }

        pub fn from_network(network: NetworkInt(T)) this {
            return init(std.mem.bigToNative(T, network.int));
        }
    };
}

pub const Startup = struct {
    version: u32,
    params: std.StringHashMap([]const u8),

    pub fn deserialize(data: []const u8) !Startup {
        _ = data;
    }
};

pub const Authentication = struct {
    type: u8,
    length: u32,
    response: u32,
    data: ?[]u8 = null,
};

pub const AuthenticationOk: Authentication = .{
    .type = 'R',
    .length = 8,
    .response = 1,
};

pub fn deserialize(data: []u8) void {
    assert(data.len >= 1);
}

pub fn serialize() []u8 {
    unreachable;
}
