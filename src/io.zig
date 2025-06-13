const builtin = @import("builtin");
const options = @import("build_options");

const IO_Linux = @import("io/linux.zig").IO;
const IO_Test = @import("io/test.zig").IO;

pub const IO = if (options.test_io) IO_Test else switch (builtin.target.os.tag) {
    .linux => IO_Linux,
    else => @compileError("IO is not supported for platform"),
};

pub const Command = union(enum) {
    write: WriteCommand,

    pub const Status = enum {
        submitted,
        waiting,
        completed,
    };

    pub const WriteCommand = struct {
        // TODO figure out file descriptor type
        fd: usize,
        buffer: []const u8,

        pub fn init(buffer: []const u8) !Command {
            const write = WriteCommand{
                .fd = 1,
                .buffer = buffer,
            };

            return Command{ .write = write };
        }
    };
};
