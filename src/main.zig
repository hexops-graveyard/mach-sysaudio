const builtin = @import("builtin");
const std = @import("std");
const util = @import("util.zig");
const backends = @import("backends.zig");

pub const Backend = backends.Backend;
pub const default_sample_rate = 44_100; // Hz
pub const default_latency = 500 * std.time.us_per_ms; // μs
pub const min_sample_rate = 8_000; // Hz
pub const max_sample_rate = 5_644_800; // Hz

pub const Context = struct {
    pub const DeviceChangeFn = *const fn (self: ?*anyopaque) void;
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

    pub fn deinit(self: Context) void {
        switch (self.data) {
            inline else => |b| b.deinit(),
        }
    }

    pub const RefreshError = error{
        OutOfMemory,
        SystemResources,
        OpeningDevice,
    };

    pub fn refresh(self: Context) RefreshError!void {
        return switch (self.data) {
            inline else => |b| b.refresh(),
        };
    }

    pub fn devices(self: Context) []const Device {
        return switch (self.data) {
            inline else => |b| b.devices(),
        };
    }

    pub fn defaultDevice(self: Context, mode: Device.Mode) ?Device {
        return switch (self.data) {
            inline else => |b| b.defaultDevice(mode),
        };
    }

    pub const CreateStreamError = error{
        OutOfMemory,
        SystemResources,
        OpeningDevice,
        IncompatibleDevice,
    };

    pub fn createPlayer(self: Context, device: Device, writeFn: WriteFn, options: StreamOptions) CreateStreamError!Player {
        std.debug.assert(device.mode == .playback);

        return .{
            .data = switch (self.data) {
                inline else => |b| try b.createPlayer(device, writeFn, options),
            },
        };
    }

    pub fn createRecorder(self: Context, device: Device, readFn: ReadFn, options: StreamOptions) CreateStreamError!Recorder {
        std.debug.assert(device.mode == .capture);

        return .{
            .data = switch (self.data) {
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

    pub fn deinit(self: *Player) void {
        return switch (self.data) {
            inline else => |b| b.deinit(),
        };
    }

    pub const StartError = error{
        CannotPlay,
        OutOfMemory,
        SystemResources,
    };

    pub fn start(self: *Player) StartError!void {
        return switch (self.data) {
            inline else => |b| b.start(),
        };
    }

    pub const PlayError = error{
        CannotPlay,
        OutOfMemory,
    };

    pub fn play(self: *Player) PlayError!void {
        return switch (self.data) {
            inline else => |b| b.play(),
        };
    }

    pub const PauseError = error{
        CannotPause,
        OutOfMemory,
    };

    pub fn pause(self: *Player) PauseError!void {
        return switch (self.data) {
            inline else => |b| b.pause(),
        };
    }

    pub fn paused(self: *Player) bool {
        return switch (self.data) {
            inline else => |b| b.paused(),
        };
    }

    pub const SetVolumeError = error{
        CannotSetVolume,
    };

    // confidence interval (±) depends on the device
    pub fn setVolume(self: *Player, vol: f32) SetVolumeError!void {
        std.debug.assert(vol <= 1.0);
        return switch (self.data) {
            inline else => |b| b.setVolume(vol),
        };
    }

    pub const GetVolumeError = error{
        CannotGetVolume,
    };

    // confidence interval (±) depends on the device
    pub fn volume(self: *Player) GetVolumeError!f32 {
        return switch (self.data) {
            inline else => |b| b.volume(),
        };
    }

    pub fn writeAll(self: *Player, frame: usize, value: anytype) void {
        for (self.channels()) |ch|
            self.write(ch, frame, value);
    }

    pub fn write(self: *Player, channel: Channel, frame: usize, sample: anytype) void {
        switch (@TypeOf(sample)) {
            u8, i8, i16, i24, i32, f32 => {},
            else => @compileError(
                \\invalid sample type. supported types are:
                \\u8, i8, i16, i24, i32, f32
            ),
        }

        var ptr = channel.ptr + frame * self.writeStep();
        switch (self.format()) {
            .u8 => std.mem.bytesAsValue(u8, ptr[0..@sizeOf(u8)]).* = switch (@TypeOf(sample)) {
                u8 => sample,
                i8, i16, i24, i32 => signedToUnsigned(u8, sample),
                f32 => floatToUnsigned(u8, sample),
                else => unreachable,
            },
            .i16 => std.mem.bytesAsValue(i16, ptr[0..@sizeOf(i16)]).* = switch (@TypeOf(sample)) {
                i16 => sample,
                u8 => unsignedToSigned(i16, sample),
                // i8, i24, i32 => signedToSigned(i16, sample),
                f32 => floatToSigned(i16, sample),
                else => unreachable,
            },
            .i24 => std.mem.bytesAsValue(i24, ptr[0..@sizeOf(i24)]).* = switch (@TypeOf(sample)) {
                i24 => sample,
                u8 => unsignedToSigned(i24, sample),
                i8, i16, i32 => signedToSigned(i24, sample),
                // TODO: uncomment once https://github.com/ziglang/zig/issues/16390 resolved
                // f32 => floatToSigned(i24, sample),
                else => unreachable,
            },
            .i24_4b => @panic("TODO"),
            .i32 => std.mem.bytesAsValue(i32, ptr[0..@sizeOf(i32)]).* = switch (@TypeOf(sample)) {
                i32 => sample,
                u8 => unsignedToSigned(i32, sample),
                // i8, i16, i24 => signedToSigned(i32, sample),
                f32 => floatToSigned(i32, sample),
                else => unreachable,
            },
            .f32 => std.mem.bytesAsValue(f32, ptr[0..@sizeOf(f32)]).* = switch (@TypeOf(sample)) {
                f32 => sample,
                u8 => unsignedToFloat(f32, sample),
                i8, i16, i24, i32 => signedToFloat(f32, sample),
                else => unreachable,
            },
        }
    }

    pub fn sampleRate(self: *Player) u24 {
        return if (@hasField(Backend, "jack")) switch (self.data) {
            .jack => |b| b.sampleRate(),
            inline else => |b| b.sample_rate,
        } else switch (self.data) {
            inline else => |b| b.sample_rate,
        };
    }

    pub fn channels(self: *Player) []Channel {
        return switch (self.data) {
            inline else => |b| b.channels,
        };
    }

    pub fn format(self: *Player) Format {
        return switch (self.data) {
            inline else => |b| b.format,
        };
    }

    pub fn writeStep(self: *Player) u8 {
        return switch (self.data) {
            inline else => |b| b.write_step,
        };
    }
};

pub const Recorder = struct {
    data: backends.Recorder,

    pub fn deinit(self: *Recorder) void {
        return switch (self.data) {
            inline else => |b| b.deinit(),
        };
    }

    pub const StartError = error{
        CannotRecord,
        OutOfMemory,
        SystemResources,
    };

    pub fn start(self: *Recorder) StartError!void {
        return switch (self.data) {
            inline else => |b| b.start(),
        };
    }

    pub const RecordError = error{
        CannotRecord,
        OutOfMemory,
    };

    pub fn record(self: *Recorder) RecordError!void {
        return switch (self.data) {
            inline else => |b| b.record(),
        };
    }

    pub const PauseError = error{
        CannotPause,
        OutOfMemory,
    };

    pub fn pause(self: *Recorder) PauseError!void {
        return switch (self.data) {
            inline else => |b| b.pause(),
        };
    }

    pub fn paused(self: *Recorder) bool {
        return switch (self.data) {
            inline else => |b| b.paused(),
        };
    }

    pub const SetVolumeError = error{
        CannotSetVolume,
    };

    // confidence interval (±) depends on the device
    pub fn setVolume(self: *Recorder, vol: f32) SetVolumeError!void {
        std.debug.assert(vol <= 1.0);
        return switch (self.data) {
            inline else => |b| b.setVolume(vol),
        };
    }

    pub const GetVolumeError = error{
        CannotGetVolume,
    };

    // confidence interval (±) depends on the device
    pub fn volume(self: *Recorder) GetVolumeError!f32 {
        return switch (self.data) {
            inline else => |b| b.volume(),
        };
    }

    pub fn readAll(self: *Recorder, frame: usize, comptime T: type, samples: []T) void {
        for (self.channels(), samples) |ch, *sample|
            sample.* = self.read(ch, frame, T);
    }

    pub fn read(self: *Recorder, channel: Channel, frame: usize, comptime T: type) T {
        switch (T) {
            u8, i8, i16, i24, i32, f32 => {},
            else => @compileError(
                \\invalid sample type. supported types are:
                \\u8, i8, i16, i24, i32, f32
            ),
        }

        var ptr = channel.ptr + frame * self.readStep();
        switch (self.format()) {
            .u8 => {
                const sample = std.mem.bytesAsValue(u8, ptr[0..@sizeOf(u8)]).*;
                return switch (T) {
                    u8 => sample,
                    i8, i16, i24, i32 => unsignedToSigned(T, sample),
                    f32 => unsignedToFloat(T, sample),
                    else => unreachable,
                };
            },
            .i16 => {
                const sample = std.mem.bytesAsValue(i16, ptr[0..@sizeOf(i16)]).*;
                return switch (T) {
                    i16 => sample,
                    u8 => signedToUnsigned(T, sample),
                    i8, i24, i32 => signedToSigned(T, sample),
                    f32 => signedToFloat(T, sample),
                    else => unreachable,
                };
            },
            .i24 => {
                const sample = std.mem.bytesAsValue(i24, ptr[0..@sizeOf(i24)]).*;
                return switch (T) {
                    i24 => sample,
                    u8 => signedToUnsigned(T, sample),
                    i8, i16, i32 => signedToSigned(T, sample),
                    // f32 => signedToFloat(T, sample),
                    else => unreachable,
                };
            },
            .i24_4b => @panic("TODO"),
            .i32 => {
                const sample = std.mem.bytesAsValue(i32, ptr[0..@sizeOf(i32)]).*;
                return switch (T) {
                    i32 => sample,
                    u8 => signedToUnsigned(T, sample),
                    i8, i16, i24 => signedToSigned(T, sample),
                    f32 => signedToFloat(T, sample),
                    else => unreachable,
                };
            },
            .f32 => {
                const sample = std.mem.bytesAsValue(f32, ptr[0..@sizeOf(f32)]).*;
                return switch (T) {
                    f32 => sample,
                    u8 => floatToUnsigned(T, sample),
                    i8, i16, i32 => floatToSigned(T, sample),
                    // TODO: uncomment once https://github.com/ziglang/zig/issues/16390 resolved
                    // i24 => floatToSigned(T, sample),
                    else => unreachable,
                };
            },
        }
    }

    pub fn sampleRate(self: *Recorder) u24 {
        return if (@hasField(Backend, "jack")) switch (self.data) {
            .jack => |b| b.sampleRate(),
            inline else => |b| b.sample_rate,
        } else switch (self.data) {
            inline else => |b| b.sample_rate,
        };
    }

    pub fn channels(self: *Recorder) []Channel {
        return switch (self.data) {
            inline else => |b| b.channels,
        };
    }

    pub fn format(self: *Recorder) Format {
        return switch (self.data) {
            inline else => |b| b.format,
        };
    }

    pub fn readStep(self: *Recorder) u8 {
        return switch (self.data) {
            inline else => |b| b.read_step,
        };
    }
};

fn unsignedToSigned(comptime T: type, sample: anytype) T {
    const half = 1 << (@bitSizeOf(@TypeOf(sample)) - 1);
    const trunc = @bitSizeOf(T) - @bitSizeOf(@TypeOf(sample));
    return @as(T, @intCast(sample -% half)) << trunc;
}

fn unsignedToFloat(comptime T: type, sample: anytype) T {
    const max_int = std.math.maxInt(@TypeOf(sample)) + 1.0;
    return (@as(T, @floatFromInt(sample)) - max_int) * 1.0 / max_int;
}

fn signedToSigned(comptime T: type, sample: anytype) T {
    const trunc = @bitSizeOf(@TypeOf(sample)) - @bitSizeOf(T);
    return std.math.shr(T, @as(T, @intCast(sample)), trunc);
}

fn signedToUnsigned(comptime T: type, sample: anytype) T {
    const half = 1 << (@bitSizeOf(T) - 1);
    const trunc = @bitSizeOf(@TypeOf(sample)) - @bitSizeOf(T);
    return @intCast((sample >> trunc) + half);
}

fn signedToFloat(comptime T: type, sample: anytype) T {
    const max_int = std.math.maxInt(@TypeOf(sample)) + 1.0;
    return @as(T, @floatFromInt(sample)) * 1.0 / max_int;
}

fn floatToSigned(comptime T: type, sample: f64) T {
    return @intFromFloat(sample * std.math.maxInt(T));
}

fn floatToUnsigned(comptime T: type, sample: f64) T {
    const half = 1 << @bitSizeOf(T) - 1;
    return @intFromFloat(sample * (half - 1) + half);
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

    pub fn preferredFormat(self: Device, format: ?Format) Format {
        if (format) |f| {
            for (self.formats) |fmt| {
                if (f == fmt) {
                    return fmt;
                }
            }
        }

        var best: Format = self.formats[0];
        for (self.formats) |fmt| {
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

    pub fn size(self: Format) u8 {
        return switch (self) {
            .u8 => 1,
            .i16 => 2,
            .i24 => 3,
            .i24_4b, .i32, .f32 => 4,
        };
    }

    pub fn validSize(self: Format) u8 {
        return switch (self) {
            .u8 => 1,
            .i16 => 2,
            .i24, .i24_4b => 3,
            .i32, .f32 => 4,
        };
    }

    pub fn sizeBits(self: Format) u8 {
        return self.size() * 8;
    }

    pub fn validSizeBits(self: Format) u8 {
        return self.validSize() * 8;
    }

    pub fn frameSize(self: Format, ch_count: usize) u8 {
        return self.size() * @as(u5, @intCast(ch_count));
    }
};

test {
    std.testing.refAllDeclsRecursive(@This());
}
