const builtin = @import("builtin");
const std = @import("std");

pub const Backend = std.meta.Tag(BackendContext);
pub const BackendContext = switch (builtin.os.tag) {
    .linux => union(enum) {
        alsa: *@import("alsa.zig").Context,
        pipewire: *@import("pipewire.zig").Context,
        jack: *@import("jack.zig").Context,
        pulseaudio: *@import("pulseaudio.zig").Context,
        dummy: *@import("dummy.zig").Context,
    },
    .freebsd, .netbsd, .openbsd, .solaris => union(enum) {
        pipewire: *@import("pipewire.zig").Context,
        jack: *@import("jack.zig").Context,
        pulseaudio: *@import("pulseaudio.zig").Context,
        dummy: *@import("dummy.zig").Context,
    },
    .macos, .ios, .watchos, .tvos => union(enum) {
        coreaudio: *@import("coreaudio.zig").Context,
        dummy: *@import("dummy.zig").Context,
    },
    .windows => union(enum) {
        wasapi: *@import("wasapi.zig").Context,
        dummy: *@import("dummy.zig").Context,
    },
    .freestanding => switch (builtin.cpu.arch) {
        .wasm32 => union(enum) {
            webaudio: *@import("webaudio.zig").Context,
            dummy: *@import("dummy.zig").Context,
        },
        else => union(enum) {
            dummy: *@import("dummy.zig").Context,
        },
    },
    else => union(enum) {
        dummy: *@import("dummy.zig").Context,
    },
};
pub const BackendPlayer = switch (builtin.os.tag) {
    .linux => union(enum) {
        alsa: *@import("alsa.zig").Player,
        pipewire: *@import("pipewire.zig").Player,
        jack: *@import("jack.zig").Player,
        pulseaudio: *@import("pulseaudio.zig").Player,
        dummy: *@import("dummy.zig").Player,
    },
    .freebsd, .netbsd, .openbsd, .solaris => union(enum) {
        pipewire: *@import("pipewire.zig").Player,
        jack: *@import("jack.zig").Player,
        pulseaudio: *@import("pulseaudio.zig").Player,
        dummy: *@import("dummy.zig").Player,
    },
    .macos, .ios, .watchos, .tvos => union(enum) {
        coreaudio: *@import("coreaudio.zig").Player,
        dummy: *@import("dummy.zig").Player,
    },
    .windows => union(enum) {
        wasapi: *@import("wasapi.zig").Player,
        dummy: *@import("dummy.zig").Player,
    },
    .freestanding => switch (builtin.cpu.arch) {
        .wasm32 => union(enum) {
            webaudio: *@import("webaudio.zig").Player,
            dummy: *@import("dummy.zig").Player,
        },
        else => union(enum) {
            dummy: *@import("dummy.zig").Player,
        },
    },
    else => union(enum) {
        dummy: *@import("dummy.zig").Player,
    },
};
