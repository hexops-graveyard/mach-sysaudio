const std = @import("std");
const system_sdk = @import("system_sdk");

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});
    const target = b.standardTargetOptions(.{});

    const module = b.addModule("mach-sysaudio", .{
        .source_file = .{ .path = "src/main.zig" },
        .dependencies = &.{
            .{
                .name = "sysjs",
                .module = b.dependency("mach_sysjs", .{
                    .optimize = optimize,
                    .target = target,
                }).module("mach-sysjs"),
            },
        },
    });

    const audio_headers = b.dependency(
        "linux_audio_headers",
        .{ .optimize = optimize, .target = target },
    );

    const main_tests = b.addTest(.{
        .name = "sysaudio-tests",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    link(b, main_tests, audio_headers);

    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&b.addRunArtifact(main_tests).step);

    inline for ([_][]const u8{
        "sine-wave",
    }) |example| {
        const example_exe = b.addExecutable(.{
            .name = "example-" ++ example,
            .root_source_file = .{ .path = "examples/" ++ example ++ ".zig" },
            .target = target,
            .optimize = optimize,
        });
        example_exe.addModule("sysaudio", module);

        link(b, example_exe, audio_headers);

        example_exe.install();

        const example_compile_step = b.step("example-" ++ example, "Compile '" ++ example ++ "' example");
        example_compile_step.dependOn(b.getInstallStep());

        const example_run_cmd = example_exe.run();
        example_run_cmd.step.dependOn(b.getInstallStep());
        if (b.args) |args| {
            example_run_cmd.addArgs(args);
        }

        const example_run_step = b.step("run-example-" ++ example, "Run '" ++ example ++ "' example");
        example_run_step.dependOn(&example_run_cmd.step);
    }
}

pub fn link(b: *std.Build, step: *std.Build.CompileStep, audio_headers: *std.Build.Dependency) void {
    // TODO: add this stuff as module dependency once supported
    step.linkLibrary(audio_headers.artifact("linux-audio-headers"));
    if (step.target.getCpuArch() != .wasm32) {
        // TODO(build-system): pass system SDK options through
        system_sdk.include(b, step, .{});
        if (step.target.isDarwin()) {
            step.linkFramework("AudioToolbox");
            step.linkFramework("CoreFoundation");
            step.linkFramework("CoreAudio");
        } else if (step.target.toTarget().os.tag == .linux) {
            step.addCSourceFile("src/pipewire/sysaudio.c", &.{"-std=gnu99"});
            step.linkLibC();
        }
    }
}
