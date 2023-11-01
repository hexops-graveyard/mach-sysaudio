const builtin = @import("builtin");
const std = @import("std");
const util = @import("util.zig");
const backends = @import("backends.zig");
const bytesAsValue = std.mem.bytesAsValue;

pub const Backend = backends.Backend;
pub const Range = util.Range;

pub const default_sample_rate = 44_100; // Hz
pub const default_latency = 500 * std.time.us_per_ms; // μs
pub const min_sample_rate = 8_000; // Hz
pub const max_sample_rate = 5_644_800; // Hz

pub const Context = struct {
    pub const DeviceChangeFn = *const fn (userdata: ?*anyopaque) void;
    pub const Options = struct {
        app_name: [:0]const u8 = "Mach Game",
        deviceChangeFn: ?DeviceChangeFn = null,
        user_data: ?*anyopaque = null,
    };

    data: backends.Context,

    pub const InitError = error{
        OutOfMemory,
        AccessDenied,
        LibraryNotFound,
        SymbolLookup,
        SystemResources,
        ConnectionRefused,
    };

    pub fn init(comptime backend: ?Backend, allocator: std.mem.Allocator, options: Options) InitError!Context {
        var data: backends.Context = blk: {
            if (backend) |b| {
                break :blk try @typeInfo(
                    std.meta.fieldInfo(backends.Context, b).type,
                ).Pointer.child.init(allocator, options);
            } else {
                inline for (std.meta.fields(Backend), 0..) |b, i| {
                    if (@typeInfo(
                        std.meta.fieldInfo(backends.Context, @as(Backend, @enumFromInt(b.value))).type,
                    ).Pointer.child.init(allocator, options)) |d| {
                        break :blk d;
                    } else |err| {
                        if (i == std.meta.fields(Backend).len - 1)
                            return err;
                    }
                }
                unreachable;
            }
        };

        return .{ .data = data };
    }

    pub inline fn deinit(ctx: Context) void {
        switch (ctx.data) {
            inline else => |b| b.deinit(),
        }
    }

    pub const RefreshError = error{
        OutOfMemory,
        SystemResources,
        OpeningDevice,
    };

    pub inline fn refresh(ctx: Context) RefreshError!void {
        return switch (ctx.data) {
            inline else => |b| b.refresh(),
        };
    }

    pub inline fn devices(ctx: Context) []const Device {
        return switch (ctx.data) {
            inline else => |b| b.devices(),
        };
    }

    pub inline fn defaultDevice(ctx: Context, mode: Device.Mode) ?Device {
        return switch (ctx.data) {
            inline else => |b| b.defaultDevice(mode),
        };
    }

    pub const CreateStreamError = error{
        OutOfMemory,
        SystemResources,
        OpeningDevice,
        IncompatibleDevice,
    };

    pub inline fn createPlayer(ctx: Context, device: Device, writeFn: WriteFn, options: StreamOptions) CreateStreamError!Player {
        std.debug.assert(device.mode == .playback);

        return .{
            .data = switch (ctx.data) {
                inline else => |b| try b.createPlayer(device, writeFn, options),
            },
        };
    }

    pub inline fn createRecorder(ctx: Context, device: Device, readFn: ReadFn, options: StreamOptions) CreateStreamError!Recorder {
        std.debug.assert(device.mode == .capture);

        return .{
            .data = switch (ctx.data) {
                inline else => |b| try b.createRecorder(device, readFn, options),
            },
        };
    }
};

pub const StreamOptions = struct {
    format: Format = .f32,
    sample_rate: u24 = default_sample_rate,
    media_role: MediaRole = .default,
    user_data: ?*anyopaque = null,
};

pub const MediaRole = enum {
    default,
    game,
    music,
    movie,
    communication,
};

// TODO: `*Player` instead `*anyopaque`
// https://github.com/ziglang/zig/issues/12325
pub const WriteFn = *const fn (user_data: ?*anyopaque, frame_count_max: usize) void;
// TODO: `*Recorder` instead `*anyopaque`
pub const ReadFn = *const fn (user_data: ?*anyopaque, frame_count_max: usize) void;

pub const Player = struct {
    data: backends.Player,

    pub inline fn deinit(player: *Player) void {
        return switch (player.data) {
            inline else => |b| b.deinit(),
        };
    }

    pub const StartError = error{
        CannotPlay,
        OutOfMemory,
        SystemResources,
    };

    pub inline fn start(player: *Player) StartError!void {
        return switch (player.data) {
            inline else => |b| b.start(),
        };
    }

    pub const PlayError = error{
        CannotPlay,
        OutOfMemory,
    };

    pub inline fn play(player: *Player) PlayError!void {
        return switch (player.data) {
            inline else => |b| b.play(),
        };
    }

    pub const PauseError = error{
        CannotPause,
        OutOfMemory,
    };

    pub inline fn pause(player: *Player) PauseError!void {
        return switch (player.data) {
            inline else => |b| b.pause(),
        };
    }

    pub inline fn paused(player: *Player) bool {
        return switch (player.data) {
            inline else => |b| b.paused(),
        };
    }

    pub const SetVolumeError = error{
        CannotSetVolume,
    };

    // confidence interval (±) depends on the device
    pub inline fn setVolume(player: *Player, vol: f32) SetVolumeError!void {
        std.debug.assert(vol <= 1.0);
        return switch (player.data) {
            inline else => |b| b.setVolume(vol),
        };
    }

    pub const GetVolumeError = error{
        CannotGetVolume,
    };

    // confidence interval (±) depends on the device
    pub inline fn volume(player: *Player) GetVolumeError!f32 {
        return switch (player.data) {
            inline else => |b| b.volume(),
        };
    }

    pub inline fn writeAll(player: *Player, frame: usize, value: anytype) void {
        for (player.channels()) |ch| player.write(ch, frame, value);
    }

    pub inline fn write(player: *Player, channel: Channel, frame: usize, sample: anytype) void {
        const T = @TypeOf(sample);
        switch (T) {
            u8, i8, i16, i24, i32, f32 => {},
            else => @compileError(
                \\invalid sample type. supported types are:
                \\u8, i8, i16, i24, i32, f32
            ),
        }

        const ptr = channel.ptr + frame * player.writeStep();
        bytesAsValue(T, ptr[0..@sizeOf(T)]).* = sample;
    }

    pub inline fn writeAllAuto(player: *Player, frame: usize, value: anytype) void {
        for (player.channels()) |ch| player.writeAuto(ch, frame, value);
    }

    pub inline fn writeAuto(player: *Player, channel: Channel, frame: usize, sample: anytype) void {
        const T = @TypeOf(sample);
        switch (T) {
            u8, i8, i16, i24, i32, f32 => {},
            else => @compileError(
                \\invalid sample type. supported types are:
                \\u8, i8, i16, i24, i32, f32
            ),
        }

        const ptr = channel.ptr + frame * player.writeStep();
        switch (player.format()) {
            .u8 => bytesAsValue(u8, ptr[0..@sizeOf(u8)]).* = convertSample(.clip, u8, sample),
            .i16 => bytesAsValue(i16, ptr[0..@sizeOf(i16)]).* = convertSample(.clip, i16, sample),
            .i24, .i24_4b => bytesAsValue(i24, ptr[0..@sizeOf(i24)]).* = convertSample(.clip, i24, sample),
            .i32 => bytesAsValue(i32, ptr[0..@sizeOf(i32)]).* = convertSample(.clip, i32, sample),
            .f32 => bytesAsValue(f32, ptr[0..@sizeOf(f32)]).* = convertSample(.clip, f32, sample),
        }
    }

    pub inline fn sampleRate(player: *Player) u24 {
        return if (@hasField(Backend, "jack")) switch (player.data) {
            .jack => |b| b.sampleRate(),
            inline else => |b| b.sample_rate,
        } else switch (player.data) {
            inline else => |b| b.sample_rate,
        };
    }

    pub inline fn channels(player: *Player) []Channel {
        return switch (player.data) {
            inline else => |b| b.channels,
        };
    }

    pub inline fn format(player: *Player) Format {
        return switch (player.data) {
            inline else => |b| b.format,
        };
    }

    pub inline fn writeStep(player: *Player) u8 {
        return switch (player.data) {
            inline else => |b| b.write_step,
        };
    }
};

pub const Recorder = struct {
    data: backends.Recorder,

    pub inline fn deinit(recorder: *Recorder) void {
        return switch (recorder.data) {
            inline else => |b| b.deinit(),
        };
    }

    pub const StartError = error{
        CannotRecord,
        OutOfMemory,
        SystemResources,
    };

    pub inline fn start(recorder: *Recorder) StartError!void {
        return switch (recorder.data) {
            inline else => |b| b.start(),
        };
    }

    pub const RecordError = error{
        CannotRecord,
        OutOfMemory,
    };

    pub inline fn record(recorder: *Recorder) RecordError!void {
        return switch (recorder.data) {
            inline else => |b| b.record(),
        };
    }

    pub const PauseError = error{
        CannotPause,
        OutOfMemory,
    };

    pub inline fn pause(recorder: *Recorder) PauseError!void {
        return switch (recorder.data) {
            inline else => |b| b.pause(),
        };
    }

    pub inline fn paused(recorder: *Recorder) bool {
        return switch (recorder.data) {
            inline else => |b| b.paused(),
        };
    }

    pub const SetVolumeError = error{
        CannotSetVolume,
    };

    // confidence interval (±) depends on the device
    pub inline fn setVolume(recorder: *Recorder, vol: f32) SetVolumeError!void {
        std.debug.assert(vol <= 1.0);
        return switch (recorder.data) {
            inline else => |b| b.setVolume(vol),
        };
    }

    pub const GetVolumeError = error{
        CannotGetVolume,
    };

    // confidence interval (±) depends on the device
    pub inline fn volume(recorder: *Recorder) GetVolumeError!f32 {
        return switch (recorder.data) {
            inline else => |b| b.volume(),
        };
    }

    pub inline fn readAll(recorder: *Recorder, frame: usize, comptime T: type, samples: []T) void {
        for (recorder.channels(), samples) |ch, *sample| sample.* = recorder.read(ch, frame, T);
    }

    pub inline fn read(recorder: *Recorder, channel: Channel, frame: usize, comptime T: type) T {
        switch (T) {
            u8, i8, i16, i24, i32, f32 => {},
            else => @compileError(
                \\invalid sample type. supported types are:
                \\u8, i8, i16, i24, i32, f32
            ),
        }

        const ptr = channel.ptr + frame * recorder.readStep();
        return bytesAsValue(T, ptr[0..@sizeOf(T)]).*;
    }

    pub inline fn readAllAuto(recorder: *Recorder, frame: usize, comptime T: type, samples: []T) void {
        for (recorder.channels(), samples) |ch, *sample| sample.* = recorder.readAuto(ch, frame, T);
    }

    pub inline fn readAuto(recorder: *Recorder, channel: Channel, frame: usize, comptime T: type) T {
        switch (T) {
            u8, i8, i16, i24, i32, f32 => {},
            else => @compileError(
                \\invalid sample type. supported types are:
                \\u8, i8, i16, i24, i32, f32
            ),
        }

        const ptr = channel.ptr + frame * recorder.readStep();
        return switch (recorder.format()) {
            .u8 => convertSample(.clip, T, bytesAsValue(u8, ptr[0..@sizeOf(u8)]).*),
            .i16 => convertSample(.clip, T, bytesAsValue(i16, ptr[0..@sizeOf(i16)]).*),
            .i24, .i24_4b => convertSample(.clip, T, bytesAsValue(i24, ptr[0..@sizeOf(i24)]).*),
            .i32 => convertSample(.clip, T, bytesAsValue(i32, ptr[0..@sizeOf(i32)]).*),
            .f32 => convertSample(.clip, T, bytesAsValue(f32, ptr[0..@sizeOf(f32)]).*),
        };
    }

    pub inline fn sampleRate(recorder: *Recorder) u24 {
        return if (@hasField(Backend, "jack")) switch (recorder.data) {
            .jack => |b| b.sampleRate(),
            inline else => |b| b.sample_rate,
        } else switch (recorder.data) {
            inline else => |b| b.sample_rate,
        };
    }

    pub inline fn channels(recorder: *Recorder) []Channel {
        return switch (recorder.data) {
            inline else => |b| b.channels,
        };
    }

    pub inline fn format(recorder: *Recorder) Format {
        return switch (recorder.data) {
            inline else => |b| b.format,
        };
    }

    pub inline fn readStep(recorder: *Recorder) u8 {
        return switch (recorder.data) {
            inline else => |b| b.read_step,
        };
    }
};

pub const FloatConvertionStrategy = enum { clip, dither };

inline fn convertSample(comptime strategy: FloatConvertionStrategy, comptime T: type, sample: anytype) T {
    const ST = @TypeOf(sample);
    return switch (ST) {
        u8 => switch (T) {
            u8 => sample,
            i8, i16, i24, i32 => unsignedToSigned(T, sample),
            f32 => unsignedToFloat(T, sample),
            else => unreachable,
        },
        i16 => switch (T) {
            i16 => sample,
            u8 => signedToUnsigned(T, sample),
            i8, i24, i32 => signedToSigned(T, sample),
            f32 => signedToFloat(T, sample),
            else => unreachable,
        },
        i24 => switch (T) {
            i24 => sample,
            u8 => signedToUnsigned(T, sample),
            i8, i16, i32 => signedToSigned(T, sample),
            f32 => signedToFloat(T, sample),
            else => unreachable,
        },
        i32 => switch (T) {
            i32 => sample,
            u8 => signedToUnsigned(T, sample),
            i8, i16, i24 => signedToSigned(T, sample),
            f32 => signedToFloat(T, sample),
            else => unreachable,
        },
        f32 => switch (T) {
            f32 => sample,
            u8 => switch (strategy) {
                .clip => floatToUnsignedClip(T, sample),
                .dither => @compileError("TODO"),
            },
            i8, i16, i24, i32 => switch (strategy) {
                .clip => floatToSignedClip(T, sample),
                .dither => @compileError("TODO"),
            },
            else => unreachable,
        },
        else => @compileError("invalid type"),
    };
}

test convertSample {
    try std.testing.expectEqual(@as(i16, -31488), convertSample(.clip, i16, @as(u8, 5)));
    try std.testing.expectEqual(@as(i24, -8060928), convertSample(.clip, i24, @as(u8, 5)));
    try std.testing.expectEqual(@as(i32, -2063597568), convertSample(.clip, i32, @as(u8, 5)));
    try std.testing.expectEqual(@as(f32, -0.9609375), convertSample(.clip, f32, @as(u8, 5)));

    try std.testing.expectEqual(@as(u8, 128), convertSample(.clip, u8, @as(i16, 5)));
    try std.testing.expectEqual(@as(i24, 1280), convertSample(.clip, i24, @as(i16, 5)));
    try std.testing.expectEqual(@as(i32, 327680), convertSample(.clip, i32, @as(i16, 5)));
    try std.testing.expectEqual(@as(f32, 1.52587890625e-4), convertSample(.clip, f32, @as(i16, 5)));

    try std.testing.expectEqual(@as(u8, 128), convertSample(.clip, u8, @as(i24, 5)));
    try std.testing.expectEqual(@as(i16, 0), convertSample(.clip, i16, @as(i24, 5)));
    try std.testing.expectEqual(@as(i32, 1280), convertSample(.clip, i32, @as(i24, 5)));
    try std.testing.expectEqual(@as(f32, 5.9604644775391e-7), convertSample(.clip, f32, @as(i24, 5)));

    try std.testing.expectEqual(@as(u8, 191), convertSample(.clip, u8, @as(f32, 0.5)));
    try std.testing.expectEqual(@as(i16, 16383), convertSample(.clip, i16, @as(f32, 0.5)));
    try std.testing.expectEqual(@as(i24, 4194303), convertSample(.clip, i24, @as(f32, 0.5)));
    try std.testing.expectEqual(@as(i32, 1073741824), convertSample(.clip, i32, @as(f32, 0.5)));
}

inline fn unsignedToSigned(comptime T: type, sample: anytype) T {
    const half = 1 << (@bitSizeOf(@TypeOf(sample)) - 1);
    const trunc = @bitSizeOf(T) - @bitSizeOf(@TypeOf(sample));
    return @as(T, @intCast(sample -% half)) << trunc;
}

inline fn unsignedToFloat(comptime T: type, sample: anytype) T {
    const half = (1 << @typeInfo(@TypeOf(sample)).Int.bits) / 2;
    return (@as(T, @floatFromInt(sample)) - half) * 1.0 / half;
}

inline fn signedToSigned(comptime T: type, sample: anytype) T {
    const trunc = @bitSizeOf(@TypeOf(sample)) - @bitSizeOf(T);
    return std.math.shr(T, @as(T, @intCast(sample)), trunc);
}

inline fn signedToUnsigned(comptime T: type, sample: anytype) T {
    const half = 1 << @bitSizeOf(T) - 1;
    const trunc = @bitSizeOf(@TypeOf(sample)) - @bitSizeOf(T);
    return @intCast((sample >> trunc) + half);
}

inline fn signedToFloat(comptime T: type, sample: anytype) T {
    const max: f32 = std.math.maxInt(@TypeOf(sample)) + 1;
    return @as(T, @floatFromInt(sample)) * (1.0 / max);
}

inline fn floatToSignedClip(comptime T: type, sample: f32) T {
    const max = std.math.maxInt(T);
    return @truncate(@as(i32, @intFromFloat(sample * max)));
}

inline fn floatToUnsignedClip(comptime T: type, sample: f32) T {
    const half = std.math.maxInt(T) / 2;
    return @intFromFloat(std.math.clamp((sample * half) + (half + 1), 0, std.math.maxInt(T)));
}

pub const Device = struct {
    id: [:0]const u8,
    name: [:0]const u8,
    mode: Mode,
    channels: []Channel,
    formats: []const Format,
    sample_rate: util.Range(u24),

    pub const Mode = enum {
        playback,
        capture,
    };

    pub fn preferredFormat(device: Device, format: ?Format) Format {
        if (format) |f| {
            for (device.formats) |fmt| {
                if (f == fmt) {
                    return fmt;
                }
            }
        }

        var best: Format = device.formats[0];
        for (device.formats) |fmt| {
            if (fmt.size() >= best.size()) {
                if (fmt == .i24_4b and best == .i24)
                    continue;
                best = fmt;
            }
        }
        return best;
    }
};

pub const Channel = struct {
    ptr: [*]u8 = undefined,
    id: Id,

    pub const Id = enum {
        front_center,
        front_left,
        front_right,
        front_left_center,
        front_right_center,
        back_center,
        back_left,
        back_right,
        side_left,
        side_right,
        top_center,
        top_front_center,
        top_front_left,
        top_front_right,
        top_back_center,
        top_back_left,
        top_back_right,
        lfe,
    };
};

pub const Format = enum {
    u8,
    i16,
    i24,
    i24_4b,
    i32,
    f32,

    pub inline fn size(format: Format) u8 {
        return switch (format) {
            .u8 => 1,
            .i16 => 2,
            .i24 => 3,
            .i24_4b, .i32, .f32 => 4,
        };
    }

    pub inline fn validSize(format: Format) u8 {
        return switch (format) {
            .u8 => 1,
            .i16 => 2,
            .i24, .i24_4b => 3,
            .i32, .f32 => 4,
        };
    }

    pub inline fn sizeBits(format: Format) u8 {
        return format.size() * 8;
    }

    pub inline fn validSizeBits(format: Format) u8 {
        return format.validSize() * 8;
    }

    pub inline fn validRange(format: Format) Range(i32) {
        return switch (format) {
            .u8 => .{ .min = std.math.minInt(u8), .max = std.math.maxInt(u8) },
            .i16 => .{ .min = std.math.minInt(i16), .max = std.math.maxInt(i16) },
            .i24, .i24_4b => .{ .min = std.math.minInt(i24), .max = std.math.maxInt(i24) },
            .i32 => .{ .min = std.math.minInt(i32), .max = std.math.maxInt(i32) },
            .f32 => .{ .min = -1, .max = 1 },
        };
    }

    pub inline fn frameSize(format: Format, channels: usize) u8 {
        return format.size() * @as(u5, @intCast(channels));
    }
};

test "reference declarations" {
    std.testing.refAllDeclsRecursive(@This());
}
