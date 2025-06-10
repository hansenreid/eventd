const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});

    const optimize = b.standardOptimizeOption(.{});

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

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
        .optimize = .ReleaseSafe,
    });

    benchmark_mod.export_symbol_names = &.{
        "run",
    };

    const benchmark_exe = b.addExecutable(.{
        .name = "eventd_benchmark",
        .root_module = benchmark_mod,
    });

    const benchmark_run = b.addRunArtifact(benchmark_exe);

    const benchmark_step = b.step("benchmark", "Run the benchmark");
    benchmark_step.dependOn(&benchmark_run.step);
}
