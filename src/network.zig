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

    pub fn init(bytes: []u8) !NonEmptyBytes {
        if (bytes.len == 0) {
            return error.Empty;
        }

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

pub fn ReadResult(comptime T: type) type {
    return struct {
        bytes_read: usize,
        item: T,
    };
}

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

    pub fn next_int(self: *Deserializer, T: type) !ReadResult(T) {
        self.assert_invariants();

        const size = @sizeOf(T);
        if (self.pos + size > self.bytes.items.len) {
            return error.NotEnoughBytes;
        }

        const bytes = self.bytes.items[self.pos .. self.pos + size];

        const int = NetworkInt(T).init(std.mem.readVarInt(T, bytes, .big));

        self.pos += size;

        self.assert_invariants();

        return .{
            .bytes_read = size,
            .item = int.to_native(),
        };
    }

    pub fn next_string(self: *Deserializer, max_len: usize) !ReadResult([]const u8) {
        self.assert_invariants();

        if (self.pos == self.bytes.items.len) {
            return error.EndOfBytes;
        }

        const bytes = self.bytes.items[self.pos..self.bytes.items.len];

        var count: usize = 0;
        const size = for (bytes, 0..) |char, idx| {
            if (count > max_len) {
                return error.StringLongerThanMax;
            }
            count += 1;

            if (char == 0) {
                break idx;
            }
        } else return error.SentinelNotFound;

        const string = self.bytes.items[self.pos .. self.pos + size];

        // Add 1 to move past the sentinel
        self.pos = self.pos + size + 1;

        self.assert_invariants();

        return .{
            // Add one to account for the zero byte
            .bytes_read = size + 1,
            .item = string,
        };
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

    pub fn write_string(self: *Serializer, bytes: []const u8) !void {
        self.assert_invariants();

        const written = try self.buffer.write(bytes);
        if (written != bytes.len) {
            self.bytes.set_corrupt();
            return error.NotEnoughBytes;
        }

        const zero_byte_written = try self.buffer.write(&[_]u8{0x00});
        if (zero_byte_written != 1) {
            self.bytes.set_corrupt();
            return error.NotEnoughBytes;
        }

        self.assert_invariants();
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
    var buffer: [12]u8 = undefined;
    var non_empty = try NonEmptyBytes.init(&buffer);

    var serializer = Serializer.init(&non_empty);
    try serializer.write_int(u16, 0x1234);
    try serializer.write_int(u8, 0x34);
    try serializer.write_int(u8, 0x12);
    try serializer.write_int(u64, 0xfd93283ffe172a0d);

    const no_space_left = serializer.write_int(u8, 0x00);
    try expect(std.meta.eql(no_space_left, error.NoSpaceLeft));

    var deserializer = Deserializer.init(&non_empty);

    const result1 = try deserializer.next_int(u16);
    const result2 = try deserializer.next_int(u8);
    const result3 = try deserializer.next_int(u8);
    const result4 = try deserializer.next_int(u64);
    const result5 = deserializer.next_int(u8);

    try expect(std.meta.eql(
        result1.item,
        0x1234,
    ));

    try expect(std.meta.eql(
        result2.item,
        0x34,
    ));

    try expect(std.meta.eql(
        result3.item,
        0x12,
    ));

    try expect(std.meta.eql(
        result4.item,
        0xfd93283ffe172a0d,
    ));

    try expect(std.meta.eql(result5, error.NotEnoughBytes));
}

test "mark bytes as corrupt when int write partially succeeds" {
    var buffer: [1]u8 = undefined;
    var non_empty = try NonEmptyBytes.init(&buffer);
    var serializer = Serializer.init(&non_empty);

    const fail = serializer.write_int(u16, 0x1234);
    try expect(std.meta.eql(fail, error.NotEnoughBytes));
    try expect(non_empty.corrupt);
}

test "can serialize and deserialize multiple strings" {
    var buffer: [12]u8 = undefined;
    var non_empty = try NonEmptyBytes.init(&buffer);

    const hello = "hello";
    const world = "world";
    const fail = "fail";

    var serializer = Serializer.init(&non_empty);
    try serializer.write_string(hello);
    try serializer.write_string(world);

    const no_space_left = serializer.write_string(fail);
    try expect(std.meta.eql(no_space_left, error.NoSpaceLeft));

    var deserializer = Deserializer.init(&non_empty);

    const result1 = try deserializer.next_string(100);
    const result2 = try deserializer.next_string(100);
    const result3 = deserializer.next_string(100);

    try expect(std.mem.eql(u8, result1.item, hello));
    try expect(std.mem.eql(u8, result2.item, world));
    try expect(std.meta.eql(result3, error.EndOfBytes));
}

test "deserializing string longer than max returns error" {
    var buffer: [12]u8 = undefined;
    var non_empty = try NonEmptyBytes.init(&buffer);

    const hello = "hello world";

    var serializer = Serializer.init(&non_empty);
    try serializer.write_string(hello);

    var deserializer = Deserializer.init(&non_empty);
    const result = deserializer.next_string(5);

    try expect(std.meta.eql(result, error.StringLongerThanMax));
}

test "mark bytes as corrupt when string write partially succeeds" {
    var buffer: [1]u8 = undefined;
    var non_empty = try NonEmptyBytes.init(&buffer);
    var serializer = Serializer.init(&non_empty);

    const fail = serializer.write_string("fail");
    try expect(std.meta.eql(fail, error.NotEnoughBytes));
    try expect(non_empty.corrupt);
}

test "fuzz strings" {
    const Context = struct {
        allocator: std.mem.Allocator,

        fn testOne(context: @This(), input: []const u8) anyerror!void {
            const bytes = try context.allocator.alloc(u8, input.len);
            defer context.allocator.free(bytes);

            @memcpy(bytes, input);

            var non_empty = NonEmptyBytes.init(bytes) catch {
                return;
            };

            var deserializer = Deserializer.init(&non_empty);
            const result = deserializer.next_string(input.len) catch |err| {
                switch (err) {
                    error.StringLongerThanMax, error.SentinelNotFound => return,
                    else => return err,
                }
            };

            const output = try context.allocator.alloc(u8, result.bytes_read);
            defer context.allocator.free(output);

            var out_bytes = try NonEmptyBytes.init(output);
            var serializer = Serializer.init(&out_bytes);

            try serializer.write_string(result.item);
            try expect(std.mem.eql(u8, input[0..result.bytes_read], output));
        }
    };

    const allocator = std.testing.allocator;
    try std.testing.fuzz(Context{ .allocator = allocator }, Context.testOne, .{});
}

test "fuzz integers" {
    const Context = struct {
        allocator: std.mem.Allocator,

        fn testOne(context: @This(), input: []const u8) anyerror!void {
            const bytes = try context.allocator.alloc(u8, input.len);
            defer context.allocator.free(bytes);

            @memcpy(bytes, input);

            var non_empty = NonEmptyBytes.init(bytes) catch {
                return;
            };

            var deserializer = Deserializer.init(&non_empty);
            var len: usize = 0;
            const int: u64 = blk: switch (input.len) {
                1 => {
                    len = 1;
                    const result = try deserializer.next_int(u8);
                    break :blk @intCast(result.item);
                },
                2, 3 => {
                    len = 2;
                    const result = try deserializer.next_int(u16);
                    break :blk @intCast(result.item);
                },
                4...7 => {
                    len = 4;
                    const result = try deserializer.next_int(u32);
                    break :blk @intCast(result.item);
                },
                else => {
                    len = 8;
                    const result = try deserializer.next_int(u64);
                    break :blk @intCast(result.item);
                },
            };

            const output = try context.allocator.alloc(u8, len);
            defer context.allocator.free(output);

            var out_bytes = try NonEmptyBytes.init(output);
            var serializer = Serializer.init(&out_bytes);

            switch (len) {
                1 => try serializer.write_int(u8, @truncate(int)),
                2, 3 => try serializer.write_int(u16, @truncate(int)),
                4...7 => try serializer.write_int(u32, @truncate(int)),
                else => try serializer.write_int(u64, int),
            }

            try expect(std.mem.eql(u8, input[0..len], output));
        }
    };

    const allocator = std.testing.allocator;
    try std.testing.fuzz(Context{ .allocator = allocator }, Context.testOne, .{});
}
