const std = @import("std");
const expect = std.testing.expect;
const assert = std.debug.assert;

pub const PGWire = @This();

pub const Deserializer = struct {
    bytes: []const u8,
    pos: u32 = 0,

    pub fn init(bytes: []const u8) Deserializer {
        assert(bytes.len >= 1);

        return .{
            .bytes = bytes,
        };
    }

    pub fn next_int(self: *Deserializer, T: type) NativeInt(T) {
        const size = @sizeOf(T);
        assert(self.pos + size <= self.bytes.len);
        const bytes = self.bytes[self.pos .. self.pos + size];

        const int = NetworkInt(T).init(std.mem.readVarInt(T, bytes, .big));

        self.pos += size;
        return NativeInt(T).from_network(int);
    }
};

pub fn NetworkInt(comptime T: type) type {
    if (@typeInfo(T) != .int) {
        @compileError("only ints accepted");
    }

    return struct {
        int: T,
        const this = @This();

        comptime {
            assert(@sizeOf(this) == @sizeOf(T));
        }

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

        comptime {
            assert(@sizeOf(this) == @sizeOf(T));
        }

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

test "can transform native int to network int and back" {
    const native = NativeInt(u16).init(0x1234);
    const network = NetworkInt(u16).from_native(native);

    const result = NativeInt(u16).from_network(network);
    try expect(std.meta.eql(native, result));
}

test "can transform netowrk int to native int and back" {
    const network = NetworkInt(u16).init(0x1234);
    const native = NativeInt(u16).from_network(network);

    const result = NetworkInt(u16).from_native(native);
    try expect(std.meta.eql(network, result));
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
