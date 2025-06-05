const std = @import("std");
const network = @import("network.zig");
const expect = std.testing.expect;
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;

pub const PGWire = @This();

pub const Startup = struct {
    major_version: u16,
    minor_version: u16,
    user: []const u8,
    database: ?[]const u8,

    const max_params: u32 = 20;
    const max_param_len: u32 = 100;

    pub const StartupParam = enum {
        user,
        database,
    };

    pub inline fn assert_invariants(self: *const Startup) void {
        assert(self.major_version == 3);
        assert(self.minor_version == 0);
        assert(self.user.len > 0);
    }

    pub fn init(major: u16, minor: u16, user: []const u8, database: ?[]const u8) !Startup {
        if (major != 3 or minor != 0) {
            return error.UnsupportedVersion;
        }

        const startup = Startup{
            .major_version = major,
            .minor_version = minor,
            .user = user,
            .database = database,
        };

        startup.assert_invariants();
        return startup;
    }

    pub fn deserialize(deserializer: *network.Deserializer) !Startup {
        deserializer.assert_invariants();

        const len = try deserializer.next_int(u32);
        _ = len;

        const major = try deserializer.next_int(u16);
        const minor = try deserializer.next_int(u16);

        var user: ?[]const u8 = null;
        var database: ?[]const u8 = null;

        var count: usize = 0;
        blk: while (count <= max_params) {
            count += 1;
            if (count > max_params) {
                return error.TooManyParams;
            }

            const key = deserializer.next_string(max_param_len) catch |err| {
                switch (err) {
                    error.EndOfBytes => {
                        break :blk;
                    },
                    else => return error.InvalidStartParams,
                }
            };

            const val = deserializer.next_string(max_param_len) catch |err| {
                std.debug.print("err: {any}\n", .{err});
                return error.InvalidStartParams;
            };

            const param = std.meta.stringToEnum(StartupParam, key) orelse {
                std.debug.print("Ignoring unkown param: {s}\n", .{key});
                continue;
            };

            switch (param) {
                .user => user = val,
                .database => database = val,
            }
        }

        if (user == null) {
            return error.MissingUserParam;
        }

        const startup = try Startup.init(major, minor, user.?, database);
        startup.assert_invariants();

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

test "can serialize and deserialize startup message" {
    const allocator = std.testing.allocator;
    var params = std.StringHashMap([]const u8).init(allocator);
    defer params.deinit();

    try params.put("user", "bob");

    const startup = try Startup.init(3, 0, "bob");

    var buffer: [256]u8 = undefined;
    var non_empty = network.NonEmptyBytes.init(&buffer);

    var serializer = network.Serializer.init(&non_empty);
    try startup.serialize(&serializer);
}
