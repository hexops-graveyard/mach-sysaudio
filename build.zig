const std = @import("std");

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});
    const target = b.standardTargetOptions(.{});

    const mach_sysjs_dep = b.dependency("mach_sysjs", .{
        .target = target,
        .optimize = optimize,
    });
    const mach_objc_dep = b.dependency("mach_objc", .{
        .target = target,
        .optimize = optimize,
    });
    const module = b.addModule("mach-sysaudio", .{
        .target = target,
        .optimize = optimize,
        .root_source_file = .{ .path = "src/main.zig" },
        .imports = &.{
            .{ .name = "sysjs", .module = mach_sysjs_dep.module("mach-sysjs") },
            .{ .name = "objc", .module = mach_objc_dep.module("mach-objc") },
        },
    });
    if (target.result.isDarwin()) {
        // Transitive dependencies, explicit linkage of these works around
        // ziglang/zig#17130
        module.linkSystemLibrary("objc", .{});

        // Direct dependencies
        module.linkFramework("AudioToolbox", .{});
        module.linkFramework("CoreFoundation", .{});
        module.linkFramework("CoreAudio", .{});
    }
    if (target.result.os.tag == .linux) {
        module.link_libc = true;
        module.linkLibrary(b.dependency("linux_audio_headers", .{
            .target = target,
            .optimize = optimize,
        }).artifact("linux-audio-headers"));
        module.addCSourceFile(.{
            .file = .{ .path = "src/pipewire/sysaudio.c" },
            .flags = &.{"-std=gnu99"},
        });
    }

    const main_tests = b.addTest(.{
        .name = "test",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });
    addPaths(main_tests);
    b.installArtifact(main_tests);

    const test_run_cmd = b.addRunArtifact(main_tests);
    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&test_run_cmd.step);

    inline for ([_][]const u8{
        "sine",
        "record",
    }) |example| {
        const example_exe = b.addExecutable(.{
            .name = example,
            .root_source_file = .{ .path = "examples/" ++ example ++ ".zig" },
            .target = target,
            .optimize = optimize,
        });
        example_exe.root_module.addImport("mach-sysaudio", module);
        addPaths(example_exe);
        b.installArtifact(example_exe);

        const example_compile_step = b.step(example, "Compile '" ++ example ++ "' example");
        example_compile_step.dependOn(b.getInstallStep());

        const example_run_cmd = b.addRunArtifact(example_exe);
        example_run_cmd.step.dependOn(b.getInstallStep());
        if (b.args) |args| example_run_cmd.addArgs(args);

        const example_run_step = b.step("run-" ++ example, "Run '" ++ example ++ "' example");
        example_run_step.dependOn(&example_run_cmd.step);
    }
}

pub fn addPaths(step: *std.Build.Step.Compile) void {
    if (step.rootModuleTarget().isDarwin()) @import("xcode_frameworks").addPaths(step);
}

pub fn link(b: *std.Build, step: *std.Build.Step.Compile) void {
    _ = b;
    _ = step;

    @panic("link(b, step) has been deprecated; use addPaths(step) instead.");
}
