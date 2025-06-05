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
        assert(self.user.len <= max_param_len);
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

        var read: usize = 0;

        const len = try deserializer.next_int(u32);
        read += len.bytes_read;

        const major = try deserializer.next_int(u16);
        read += major.bytes_read;

        const minor = try deserializer.next_int(u16);
        read += minor.bytes_read;

        var user: ?[]const u8 = null;
        var database: ?[]const u8 = null;

        var count: usize = 0;
        blk: while (count <= max_params and read < len.item) {
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

            read += key.bytes_read;

            const val = deserializer.next_string(max_param_len) catch |err| {
                std.debug.print("err: {any}\n", .{err});
                return error.InvalidStartParams;
            };

            read += val.bytes_read;

            const param = std.meta.stringToEnum(StartupParam, key.item) orelse {
                std.debug.print("Ignoring unkown param: {s}\n", .{key.item});
                continue;
            };

            switch (param) {
                .user => user = val.item,
                .database => database = val.item,
            }
        }

        if (user == null) {
            return error.MissingUserParam;
        }

        const startup = try Startup.init(major.item, minor.item, user.?, database);
        startup.assert_invariants();

        return startup;
    }

    pub fn serialize(self: *const Startup, serializer: *network.Serializer) !void {
        self.assert_invariants();
        serializer.assert_invariants();

        var size: u32 = 0;

        // u32 for the length
        size += 4;

        // u16 for major version
        size += 2;

        // u16 for minor version
        size += 2;

        // "user" and null bytes
        size += 4 + 1;
        // safe to cast since we assert that the len is less than max_param_len
        const user_size: u32 = @intCast(self.user.len);
        size += user_size + 1;

        // "database" and null bytes
        if (self.database) |db| {
            size += 8 + 1;
            // safe to cast since we assert that the len is less than max_param_len
            const db_size: u32 = @intCast(db.len);
            size += db_size + 1;
        }

        try serializer.write_int(u32, size);
        try serializer.write_int(u16, self.major_version);
        try serializer.write_int(u16, self.minor_version);

        try serializer.write_string("user");
        try serializer.write_string(self.user);

        if (self.database) |db| {
            try serializer.write_string("database");
            try serializer.write_string(db);
        }

        self.assert_invariants();
    }
};

test "can serialize and deserialize startup message" {
    const startup = try Startup.init(3, 0, "bob", null);

    var buffer: [256]u8 = undefined;
    var non_empty = network.NonEmptyBytes.init(&buffer);

    var serializer = network.Serializer.init(&non_empty);
    try startup.serialize(&serializer);

    var deserializer = network.Deserializer.init(&non_empty);
    const result = try Startup.deserialize(&deserializer);

    try std.testing.expectEqualDeep(startup, result);
}
