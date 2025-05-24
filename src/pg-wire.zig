const std = @import("std");
const expect = std.testing.expect;
const assert = std.debug.assert;

pub const PGWire = @This();

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
