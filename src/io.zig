const builtin = @import("builtin");
const options = @import("build_options");

const IO_Linux = @import("io/linux.zig").IO;
const IO_Test = @import("io/test.zig").IO;

pub const IO = if (options.test_io) IO_Test else switch (builtin.target.os.tag) {
    .linux => IO_Linux,
    else => @compileError("IO is not supported for platform"),
};
