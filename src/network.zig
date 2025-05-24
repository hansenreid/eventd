const std = @import("std");
const expect = std.testing.expect;
const assert = std.debug.assert;

pub const Network = @This();

pub const NonEmptyBytes = struct {
    items: []const u8,

    comptime {
        assert(@sizeOf(NonEmptyBytes) == @sizeOf([]const u8));
    }

    pub inline fn assert_invariants(self: NonEmptyBytes) void {
        assert(self.items.len >= 1);
    }

    pub fn init(bytes: []const u8) NonEmptyBytes {
        assert(bytes.len >= 1);

        return .{
            .items = bytes,
        };
    }
};

pub const Deserializer = struct {
    bytes: NonEmptyBytes,
    pos: usize = 0,

    pub inline fn assert_invariants(self: Deserializer) void {
        self.bytes.assert_invariants();
        assert(self.pos >= 0);
        assert(self.pos <= self.bytes.items.len);
    }

    pub fn init(bytes: NonEmptyBytes) Deserializer {
        bytes.assert_invariants();

        return .{
            .bytes = bytes,
        };
    }

    pub fn next_int(self: *Deserializer, T: type) !T {
        self.assert_invariants();

        const size = @sizeOf(T);
        if (self.pos + size > self.bytes.items.len) {
            return error.NotEnoughBytes;
        }

        const bytes = self.bytes.items[self.pos .. self.pos + size];

        const int = NetworkInt(T).init(std.mem.readVarInt(T, bytes, .big));

        self.pos += size;
        return int.to_native();
    }

    pub fn next_string(self: *Deserializer) ![]const u8 {
        self.assert_invariants();

        if (self.pos == self.bytes.items.len) {
            return error.EndOfBytes;
        }

        const bytes = self.bytes.items[self.pos..self.bytes.items.len];

        const size = for (bytes, 0..) |char, idx| {
            if (char == 0) {
                break idx;
            }
        } else return error.SentinelNotFound;

        const string = self.bytes.items[self.pos .. self.pos + size];

        // Add 1 to move past the sentinel
        self.pos = self.pos + size + 1;
        return string;
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

        pub fn init(int: T) this {
            return .{
                .int = int,
            };
        }

        pub inline fn from_native(native: T) this {
            return init(std.mem.nativeToBig(T, native));
        }

        pub inline fn to_native(network: NetworkInt(T)) T {
            return std.mem.bigToNative(T, network.int);
        }
    };
}

test "can transform netowrk int to native int and back" {
    const network = NetworkInt(u16).init(0x1234);
    const native = network.to_native();

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

    const result1 = try deserializer.next_int(u16);
    const result2 = try deserializer.next_int(u8);
    const result3 = try deserializer.next_int(u8);
    const result4 = deserializer.next_int(u8);

    try expect(std.meta.eql(
        result1,
        NetworkInt(u16).init(0x1234).to_native(),
    ));

    try expect(std.meta.eql(
        result2,
        NetworkInt(u8).init(0x34).to_native(),
    ));

    try expect(std.meta.eql(
        result3,
        NetworkInt(u8).init(0x12).to_native(),
    ));

    try expect(std.meta.eql(result4, error.NotEnoughBytes));
}

test "can deserialize multiple strings" {
    const bytes = [_]u8{ 'h', 'e', 'l', 'l', 'o', 0, 'w', 'o', 'r', 'l', 'd', 0 };
    const non_empty = NonEmptyBytes.init(&bytes);
    var deserializer = Deserializer.init(non_empty);

    const result1 = try deserializer.next_string();
    const result2 = try deserializer.next_string();
    const result3 = deserializer.next_string();

    try expect(std.mem.eql(u8, result1, "hello"));
    try expect(std.mem.eql(u8, result2, "world"));
    try expect(std.meta.eql(result3, error.EndOfBytes));
}
