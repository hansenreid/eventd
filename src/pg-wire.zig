const std = @import("std");
const network = @import("network.zig");
const expect = std.testing.expect;
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;

pub const PGWire = @This();

pub const Message = union(enum) {
    authentication: Authentication,
};

pub const Startup = struct {
    len: u32,
    major_version: u16,
    minor_version: u16,
    params: std.StringHashMap([]const u8),

    pub fn deserialize(allocator: Allocator, data: network.NonEmptyBytes) !Startup {
        data.assert_invariants();

        var deserializer = network.Deserializer.init(data);

        const len = try deserializer.next_int(u32);
        if (len != data.items.len) {
            return error.InvalidStartupMessage;
        }

        const major = try deserializer.next_int(u16);
        const minor = try deserializer.next_int(u16);
        if (major != 3 or minor != 0) {
            return error.UnsupportedVersion;
        }

        var params = std.StringHashMap([]const u8).init(allocator);
        var max_params: usize = 20;
        blk: while (true and max_params > 0) {
            max_params -= 1;
            const key = deserializer.next_string() catch |err| {
                switch (err) {
                    error.EndOfBytes => {
                        break :blk;
                    },
                    else => return error.InvalidStartParams,
                }
            };

            const val = deserializer.next_string() catch |err| {
                std.debug.print("err2: {any}\n", .{err});
                return error.InvalidStartParams;
            };

            try params.put(key, val);
        }

        if (!params.contains("user")) {
            return error.MissingUserParam;
        }

        return .{
            .len = len,
            .major_version = major,
            .minor_version = minor,
            .params = params,
        };
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
