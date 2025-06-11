const std = @import("std");
const test_io = @import("io/test.zig");
const IOLoop = @import("io_loop.zig");
const commands = @import("io_commands.zig");

fn dummy(context: *anyopaque) void {
    const continuation: *IOLoop.Continuation = @ptrCast(@alignCast(context));
    const r: *commands.WriteCommand.WriteResult = @ptrCast(@alignCast(continuation.result));
    r.code = 0;
}

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    const seed: u64 = 0x3b5f92f093d3071b;
    // try std.posix.getrandom(std.mem.asBytes(&seed));
    var prng = std.Random.DefaultPrng.init(seed);

    std.debug.print("Seed: {x}\n", .{seed});

    const rand = prng.random();
    var io_impl = test_io.init(allocator, rand);
    var io = io_impl.io();

    var loop = IOLoop.init(allocator, &io);
    var events: usize = 0;

    var count: usize = 0;
    while (count < 10_000) {
        for (0..rand.int(u4)) |_| {
            const buffer: [256]u8 = undefined;
            var write = commands.WriteCommand.init(allocator, &buffer) catch {
                unreachable;
            };

            loop.enqueue(&write, dummy, write.write.result) catch |err| {
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
