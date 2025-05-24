const std = @import("std");
const expect = std.testing.expect;
const assert = std.debug.assert;

pub const Network = @This();

pub const NonEmptyBytes = struct {
    items: []const u8,

    comptime {
        assert(@sizeOf(NonEmptyBytes) == @sizeOf([]const u8));
    }

    pub fn init(bytes: []const u8) NonEmptyBytes {
        assert(bytes.len >= 1);

        return .{
            .items = bytes,
        };
    }

    pub inline fn assert_invariants(self: NonEmptyBytes) void {
        assert(self.items.len >= 1);
    }
};

pub const Deserializer = struct {
    bytes: NonEmptyBytes,
    pos: u32 = 0,

    pub fn init(bytes: NonEmptyBytes) Deserializer {
        bytes.assert_invariants();

        return .{
            .bytes = bytes,
        };
    }

    pub fn next_int(self: *Deserializer, T: type) NativeInt(T) {
        const size = @sizeOf(T);
        //TODO: Return error instead of panicing
        assert(self.pos + size <= self.bytes.items.len);
        const bytes = self.bytes.items[self.pos .. self.pos + size];

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

        pub inline fn from_native(native: NativeInt(T)) this {
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

        pub inline fn from_network(network: NetworkInt(T)) this {
            return init(std.mem.bigToNative(T, network.int));
        }
    };
}

test "can transform native int to network int and back" {
    const native = NativeInt(u16).init(0x1234);
    const network = NetworkInt(u16).from_native(native);

    const result = NativeInt(u16).from_network(network);
    try expect(std.meta.eql(
        native,
        result,
    ));
}

test "can transform netowrk int to native int and back" {
    const network = NetworkInt(u16).init(0x1234);
    const native = NativeInt(u16).from_network(network);

    const result = NetworkInt(u16).from_native(native);
    try expect(std.meta.eql(
        network,
        result,
    ));
}

test "can deserialize multiple ints" {
    const bytes = [_]u8{ 0x12, 0x34, 0x34, 0x12 };
    const non_empty = NonEmptyBytes.init(&bytes);
    var deserializer = Deserializer.init(non_empty);

    const result1 = deserializer.next_int(u16);
    const result2 = deserializer.next_int(u8);
    const result3 = deserializer.next_int(u8);

    try expect(std.meta.eql(
        result1,
        NativeInt(u16).from_network(
            NetworkInt(u16).init(0x1234),
        ),
    ));

    try expect(std.meta.eql(
        result2,
        NativeInt(u8).from_network(
            NetworkInt(u8).init(0x34),
        ),
    ));

    try expect(std.meta.eql(
        result3,
        NativeInt(u16).from_network(
            NetworkInt(u8).init(0x12),
        ),
    ));
}
