const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const options = b.addOptions();

    const tracy_enable = b.option(bool, "tracy_enable", "Enable profiling") orelse false;
    options.addOption(bool, "tracy_enable", tracy_enable);

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    exe_mod.addOptions("build_options", options);

    exe_mod.export_symbol_names = &.{
        "run",
    };

    const exe = b.addExecutable(.{
        .name = "eventd",
        .root_module = exe_mod,
    });

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);

    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const exe_unit_tests = b.addTest(.{
        .root_module = exe_mod,
    });

    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_exe_unit_tests.step);

    const benchmark_mod = b.createModule(.{
        .root_source_file = b.path("src/benchmark.zig"),
        .target = target,
        .optimize = optimize,
    });

    benchmark_mod.addOptions("build_options", options);

    benchmark_mod.export_symbol_names = &.{
        "run",
    };

    const benchmark_exe = b.addExecutable(.{
        .name = "eventd_benchmark",
        .root_module = benchmark_mod,
    });

    const benchmark_install = b.addInstallArtifact(benchmark_exe, .{});
    const benchmark_run = b.addRunArtifact(benchmark_exe);

    const benchmark_step = b.step("benchmark", "Build the benchmark");
    benchmark_step.dependOn(&benchmark_install.step);

    const benchmark_run_step = b.step("run-bench", "Build the benchmark");
    benchmark_run_step.dependOn(&benchmark_run.step);

    if (tracy_enable) {
        const client_cpp = "../../tools/tracy/public/TracyClient.cpp";
        const tracy_c_flags: []const []const u8 = if (target.result.os.tag == .windows and target.result.abi == .gnu)
            &[_][]const u8{ "-DTRACY_ENABLE=1", "-fno-sanitize=undefined", "-D_WIN32_WINNT=0x601" }
        else
            &[_][]const u8{ "-DTRACY_ENABLE=1", "-fno-sanitize=undefined" };

        exe.addIncludePath(.{ .cwd_relative = "../../tools/tracy" });
        benchmark_exe.addIncludePath(.{ .cwd_relative = "../../tools/tracy" });
        exe.addCSourceFile(.{ .file = .{ .cwd_relative = client_cpp }, .flags = tracy_c_flags });
        benchmark_exe.addCSourceFile(.{ .file = .{ .cwd_relative = client_cpp }, .flags = tracy_c_flags });
        exe.root_module.linkSystemLibrary("c++", .{ .use_pkg_config = .no });
        benchmark_exe.root_module.linkSystemLibrary("c++", .{ .use_pkg_config = .no });
        exe.linkLibC();
        benchmark_exe.linkLibC();
    }
}
