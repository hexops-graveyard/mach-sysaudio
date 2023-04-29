const std = @import("std");

pub fn Sdk(comptime deps: anytype) type {
    return struct {
        pub const Options = struct {
            install_libs: bool = false,

            /// System SDK options.
            system_sdk: deps.system_sdk.Options = .{},
        };

        var _module: ?*std.build.Module = null;

        pub fn module(b: *std.Build) *std.build.Module {
            if (_module) |m| return m;
            _module = b.createModule(.{
                .source_file = .{ .path = sdkPath("/src/main.zig") },
                .dependencies = &.{
                    .{ .name = "sysjs", .module = b.createModule(.{
                        .source_file = .{ .path = "libs/mach-sysjs/src/main.zig" },
                    }) },
                },
            });
            return _module.?;
        }

        pub fn testStep(b: *std.Build, optimize: std.builtin.OptimizeMode, target: std.zig.CrossTarget) *std.build.RunStep {
            const main_tests = b.addTest(.{
                .name = "sysaudio-tests",
                .root_source_file = .{ .path = sdkPath("/src/main.zig") },
                .target = target,
                .optimize = optimize,
            });
            link(b, main_tests, .{});
            b.installArtifact(main_tests);
            return b.addRunArtifact(main_tests);
        }

        pub fn link(b: *std.Build, step: *std.build.CompileStep, options: Options) void {
            if (step.target.toTarget().cpu.arch != .wasm32) {
                // TODO(build-system): pass system SDK options through
                deps.system_sdk.include(b, step, .{});
                if (step.target.toTarget().isDarwin()) {
                    step.linkFramework("AudioToolbox");
                    step.linkFramework("CoreFoundation");
                    step.linkFramework("CoreAudio");
                } else if (step.target.toTarget().os.tag == .linux) {
                    step.addCSourceFile(sdkPath("/src/pipewire/sysaudio.c"), &.{"-std=gnu99"});
                    step.linkLibC();
                }
            }
            if (options.install_libs) {
                b.installArtifact(step);
            }
        }

        fn ensureDependencySubmodule(allocator: std.mem.Allocator, path: []const u8) !void {
            if (std.process.getEnvVarOwned(allocator, "NO_ENSURE_SUBMODULES")) |no_ensure_submodules| {
                defer allocator.free(no_ensure_submodules);
                if (std.mem.eql(u8, no_ensure_submodules, "true")) return;
            } else |_| {}
            var child = std.ChildProcess.init(&.{ "git", "submodule", "update", "--init", path }, allocator);
            child.cwd = sdkPath("/");
            child.stderr = std.io.getStdErr();
            child.stdout = std.io.getStdOut();

            _ = try child.spawnAndWait();
        }

        fn sdkPath(comptime suffix: []const u8) []const u8 {
            if (suffix[0] != '/') @compileError("suffix must be an absolute path");
            return comptime blk: {
                const root_dir = std.fs.path.dirname(@src().file) orelse ".";
                break :blk root_dir ++ suffix;
            };
        }
    };
}
