const std = @import("std");
const network = @import("network.zig");
const expect = std.testing.expect;
const assert = std.debug.assert;

pub const PGWire = @This();

pub fn deserialize(data: network.NonEmptyBytes) Message {
    data.assert_invariants();
}

pub const Message = union(enum) {
    authentication: Authentication,
};

pub const Startup = struct {
    len: u32,
    version: u32,
    params: std.StringHashMap([]const u8),

    pub fn deserialize(data: network.NonEmptyBytes) !void {
        data.assert_invariants();

        var deserializer = network.Deserializer.init(data);

        const len = deserializer.next_int(u32);
        std.debug.print("len: {d}\n", .{len.int});

        if (len.int != data.items.len) {
            return error.InvalidStartupMessage;
        }

        const version = deserializer.next_int(u32);
        std.debug.print("version: {d}\n", .{version.int});
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

pub fn serialize() []u8 {
    unreachable;
}
