const std = @import("std");
const IOLoop = @import("io_loop.zig");
const tracy = @import("tracy.zig");

const io_impl = @import("io.zig");
const IO = io_impl.IO;
const Command = io_impl.Command;

const options = @import("build_options");

fn dummy(context: *anyopaque) void {
    const continuation: *IOLoop.Continuation = @ptrCast(@alignCast(context));
    _ = continuation;
}

pub fn main() !void {
    // tracy.setThreadName("Main");
    // defer tracy.message("Graceful main thread exit", .{});

    const allocator = std.heap.page_allocator;

    const seed: u64 = 0x3b5f92f093d3071b;
    // try std.posix.getrandom(std.mem.asBytes(&seed));
    var prng = std.Random.DefaultPrng.init(seed);

    std.debug.print("Seed: {x}\n", .{seed});

    const rand = prng.random();
    var io = IO.init();

    var loop = IOLoop.init(allocator, &io);
    var events: usize = 0;

    var count: usize = 0;
    while (count < 10_000) {
        tracy.frameMark();
        for (0..rand.int(u4)) |_| {
            const buffer: [256]u8 = undefined;

            const write_data = io_impl.WriteData{
                .buffer = &buffer,
                .fd = 0,
            };

            var write = write_data.to_cmd();

            loop.enqueue(&write, dummy) catch |err| {
                std.debug.print("Error during enqueue: {any}\n", .{err});
                continue;
            };

            events += 1;
        }
        loop.tick() catch {
            unreachable;
        };

        count += 1;
    }

    var count2: usize = 0;
    while (count2 < 200) {
        loop.tick() catch {
            unreachable;
        };

        count2 += 1;
    }

    std.debug.print("Handled {d} events\n", .{events});
}
