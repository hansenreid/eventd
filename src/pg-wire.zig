const std = @import("std");
const network = @import("network.zig");
const expect = std.testing.expect;
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;

pub const PGWire = @This();

pub const Startup = struct {
    len: u32,
    major_version: u16,
    minor_version: u16,
    params: *StartupParams,

    pub inline fn assert_invariants(self: *const Startup) void {
        assert(self.major_version == 3);
        assert(self.minor_version == 0);
        self.params.assert_invariants();
    }

    pub fn init(major: u16, minor: u16, params: *StartupParams) !Startup {
        std.debug.print("startup init count1: {d}\n", .{params.map.count()});
        params.assert_invariants();
        std.debug.print("startup init count2: {d}\n", .{params.map.count()});

        if (major != 3 or minor != 0) {
            return error.UnsupportedVersion;
        }

        const startup = Startup{
            .len = 0,
            .major_version = major,
            .minor_version = minor,
            .params = params,
        };

        std.debug.print("startup init count3: {d}\n", .{params.map.count()});
        startup.assert_invariants();
        std.debug.print("startup init count4: {d}\n", .{params.map.count()});
        return startup;
    }

    pub fn deserialize(allocator: Allocator, deserializer: *network.Deserializer) !Startup {
        deserializer.assert_invariants();

        const len = try deserializer.next_int(u32);
        _ = len;

        const major = try deserializer.next_int(u16);
        const minor = try deserializer.next_int(u16);
        var params = try StartupParams.deserialize(allocator, deserializer);
        std.debug.print("deserialize count1: {d}\n", .{params.map.count()});

        const startup = try Startup.init(major, minor, &params);
        std.debug.print("deserialize count2: {d}\n", .{params.map.count()});
        startup.assert_invariants();
        std.debug.print("deserialize count3: {d}\n", .{params.map.count()});

        return startup;
    }

    pub fn serialize(self: *const Startup, serializer: *network.Serializer) !void {
        self.assert_invariants();
        serializer.assert_invariants();

        // var size: u32 = 0;

        // u32 for the length
        // size += 4;

        // u16 for major version
        // size += 2;

        // u16 for minor version
        // size += 2;

        // var iter = self.params.iterator();
        // var i: usize = 0;
        // TODO: Extract this to make param list
        // const max_iter = 20;
        // while (iter.next()) |entry| {
        // if (i >= max_iter) {
        // return error.TooManyParams;
        // }

        // i += 1;
        // Add size of key
        // size += entry.key_ptr.len;
        // }

        self.assert_invariants();
    }
};

const StartupParams = struct {
    len: u32,
    map: *std.StringHashMap([]const u8),

    const max_params: u32 = 20;
    const max_len: u32 = 100;

    pub inline fn assert_invariants(self: *const StartupParams) void {
        assert(self.map.contains("user"));
        std.debug.print("COUNT::::: {d}\n", .{self.map.count()});
        assert(self.map.count() <= max_params);

        // var iterator = self.map.iterator();
        // var count: usize = 0;
        // var len: u32 = 0;
        // std.debug.print("HERE\n", .{});

        // while (iterator.next()) |entry| {
        //     assert(count <= max_params);
        //     count += 1;
        //
        //     const key = entry.key_ptr.*;
        //     const val = entry.value_ptr.*;
        //
        //     const key_len: u32 = @intCast(key.len);
        //     const val_len: u32 = @intCast(val.len);
        //
        //     assert(key_len <= max_len);
        //     assert(val_len <= max_len);
        //     len += key_len + val_len + 2;
        // }
        //
        // assert(len == self.len);
        // std.debug.print("THERE\n", .{});
    }

    pub fn init(len: u32, map: *std.StringHashMap([]const u8)) !StartupParams {
        if (!map.contains("user")) {
            return error.MissingUserParam;
        }

        const startup_params = StartupParams{
            .len = len,
            .map = map,
        };

        std.debug.print("params init count1: {d}\n", .{map.count()});
        startup_params.assert_invariants();
        std.debug.print("params init count2: {d}\n", .{map.count()});
        return startup_params;
    }

    pub fn deinit(self: *StartupParams) void {
        self.map.deinit();
    }

    pub fn deserialize(allocator: Allocator, deserializer: *network.Deserializer) !StartupParams {
        var params = std.StringHashMap([]const u8).init(allocator);
        var len: u32 = 0;

        var count: usize = 0;
        blk: while (count <= max_params) {
            count += 1;
            if (count > max_params) {
                return error.TooManyParams;
            }

            const key = deserializer.next_string(max_len) catch |err| {
                switch (err) {
                    error.EndOfBytes => {
                        break :blk;
                    },
                    else => return error.InvalidStartParams,
                }
            };

            const val = deserializer.next_string(max_len) catch |err| {
                std.debug.print("err: {any}\n", .{err});
                return error.InvalidStartParams;
            };

            try params.put(key, val);

            // The values are guaranteed to fit in a u32
            const key_len: u32 = @intCast(key.len);
            const val_len: u32 = @intCast(val.len);

            // Account for two zero bytes
            len += key_len + val_len + 2;
        }

        return StartupParams.init(len, &params);
    }
};

test "can serialize and deserialize startup message" {
    const allocator = std.testing.allocator;
    var params = std.StringHashMap([]const u8).init(allocator);
    defer params.deinit();

    try params.put("user", "bob");
    var startup_params = try StartupParams.init(9, &params);

    const startup = try Startup.init(3, 0, &startup_params);

    var buffer: [256]u8 = undefined;
    var non_empty = network.NonEmptyBytes.init(&buffer);

    var serializer = network.Serializer.init(&non_empty);
    try startup.serialize(&serializer);
}
