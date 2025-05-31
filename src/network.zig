const std = @import("std");
const expect = std.testing.expect;
const assert = std.debug.assert;

pub const Network = @This();

pub const NonEmptyBytes = struct {
    items: []u8,
    corrupt: bool = false,

    pub inline fn assert_invariants(self: *const NonEmptyBytes) void {
        assert(!self.corrupt);
        assert(self.items.len >= 1);
    }

    pub fn init(bytes: []u8) NonEmptyBytes {
        assert(bytes.len >= 1);

        const non_empty_bytes = NonEmptyBytes{
            .items = bytes,
        };

        non_empty_bytes.assert_invariants();
        return non_empty_bytes;
    }

    pub fn set_corrupt(self: *NonEmptyBytes) void {
        self.corrupt = true;
    }
};

pub const Deserializer = struct {
    bytes: *NonEmptyBytes,
    pos: usize = 0,

    pub inline fn assert_invariants(self: *const Deserializer) void {
        self.bytes.assert_invariants();
        assert(self.pos >= 0);
        assert(self.pos <= self.bytes.items.len);
    }

    pub fn init(bytes: *NonEmptyBytes) Deserializer {
        bytes.assert_invariants();

        const deserializer = Deserializer{
            .bytes = bytes,
        };

        deserializer.assert_invariants();
        return deserializer;
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

        self.assert_invariants();
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

        self.assert_invariants();
        return string;
    }
};

pub const Serializer = struct {
    buffer: std.io.FixedBufferStream([]u8),
    bytes: *NonEmptyBytes,

    pub inline fn assert_invariants(self: *const Serializer) void {
        self.bytes.assert_invariants();
    }

    pub fn init(bytes: *NonEmptyBytes) Serializer {
        const buffer = std.io.fixedBufferStream(bytes.items);

        const serializer = Serializer{
            .buffer = buffer,
            .bytes = bytes,
        };

        serializer.assert_invariants();
        return serializer;
    }

    pub fn write_int(self: *Serializer, T: type, int: T) !void {
        self.assert_invariants();

        const networkInt = NetworkInt(T).from_native(int);

        var buffer: [@sizeOf(T)]u8 = undefined;

        std.mem.writePackedInt(T, &buffer, 0, networkInt.int, .big);

        const written = try self.buffer.write(&buffer);
        if (written != @sizeOf(T)) {
            self.bytes.set_corrupt();
            return error.NotEnoughBytes;
        }

        self.assert_invariants();
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

        self.assert_invariants();
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

test "can serialize and deserialize multiple ints" {
    var buffer = [_]u8{0} ** 4;
    var non_empty = NonEmptyBytes.init(&buffer);

    var serializer = Serializer.init(&non_empty);
    try serializer.write_int(u16, 0x1234);
    try serializer.write_int(u8, 0x34);
    try serializer.write_int(u8, 0x12);

    const no_space_left = serializer.write_int(u8, 0x00);
    try expect(std.meta.eql(no_space_left, error.NoSpaceLeft));

    var deserializer = Deserializer.init(&non_empty);

    const result1 = try deserializer.next_int(u16);
    const result2 = try deserializer.next_int(u8);
    const result3 = try deserializer.next_int(u8);
    const result4 = deserializer.next_int(u8);

    try expect(std.meta.eql(
        result1,
        0x1234,
    ));

    try expect(std.meta.eql(
        result2,
        0x34,
    ));

    try expect(std.meta.eql(
        result3,
        0x12,
    ));

    try expect(std.meta.eql(result4, error.NotEnoughBytes));
}

test "mark bytes as corrupt when write partially succeeds" {
    var buffer = [_]u8{0} ** 1;
    var non_empty = NonEmptyBytes.init(&buffer);
    var serializer = Serializer.init(&non_empty);

    const fail = serializer.write_int(u16, 0x1234);
    try expect(std.meta.eql(fail, error.NotEnoughBytes));
    try expect(non_empty.corrupt);
}

test "can deserialize multiple strings" {
    var bytes = [_]u8{ 'h', 'e', 'l', 'l', 'o', 0, 'w', 'o', 'r', 'l', 'd', 0 };
    var non_empty = NonEmptyBytes.init(&bytes);
    var deserializer = Deserializer.init(&non_empty);

    const result1 = try deserializer.next_string();
    const result2 = try deserializer.next_string();
    const result3 = deserializer.next_string();

    try expect(std.mem.eql(u8, result1, "hello"));
    try expect(std.mem.eql(u8, result2, "world"));
    try expect(std.meta.eql(result3, error.EndOfBytes));
}
