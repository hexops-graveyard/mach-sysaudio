const std = @import("std");
const mem = std.mem;
const testing = std.testing;
const builtin = @import("builtin");
const Backend = switch (builtin.os.tag) {
    .linux,
    .windows,
    .macos,
    .ios,
    => @import("soundio.zig"),
    else => @compileError("unsupported os"),
};
pub const Error = Backend.Error;
pub const Device = Backend.Device;
pub const DeviceIterator = Backend.DeviceIterator;

pub const Mode = enum {
    input,
    output,
};

pub const Format = enum {
    U8,
    S16,
    S24,
    S32,
    F32,
};

pub const DeviceDescriptor = struct {
    mode: ?Mode = null,
    format: ?Format = null,
    is_raw: ?bool = null,
    channels: ?u8 = null,
    sample_rate: ?u32 = null,
    id: ?[:0]const u8 = null,
    name: ?[]const u8 = null,
};

const Audio = @This();

backend: Backend,

pub fn init() Error!Audio {
    return Audio{
        .backend = try Backend.init(),
    };
}

pub fn deinit(self: Audio) void {
    self.backend.deinit();
}

pub fn waitEvents(self: Audio) void {
    self.backend.waitEvents();
}

pub fn requestDevice(self: Audio, config: DeviceDescriptor) Error!Device {
    return self.backend.requestDevice(config);
}

pub fn inputDeviceIterator(self: Audio) DeviceIterator {
    return self.backend.inputDeviceIterator();
}

pub fn outputDeviceIterator(self: Audio) DeviceIterator {
    return self.backend.outputDeviceIterator();
}

test "list devices" {
    const a = try init();
    defer a.deinit();

    var iter = a.inputDeviceIterator();
    while (try iter.next()) |_| {}
}

test "connect to device" {
    const a = try init();
    defer a.deinit();

    const d = try a.requestDevice(.{ .mode = .output });
    defer d.deinit();
}

test "connect to device from descriptor" {
    const a = try init();
    defer a.deinit();

    var iter = a.outputDeviceIterator();
    var device_desc = (try iter.next()) orelse return error.NoDeviceFound;

    const d = try a.requestDevice(device_desc);
    defer d.deinit();
}

test "requestDevice behavior: null is_raw" {
    const a = try init();
    defer a.deinit();

    var iter = a.outputDeviceIterator();
    var device_desc = (try iter.next()) orelse return error.NoDeviceFound;

    const bad_desc = DeviceDescriptor{
        .is_raw = null,
        .mode = device_desc.mode,
        .id = device_desc.id,
    };
    try testing.expectError(error.InvalidParameter, a.requestDevice(bad_desc));
}

test "requestDevice behavior: null mode" {
    const a = try init();
    defer a.deinit();

    var iter = a.outputDeviceIterator();
    var device_desc = (try iter.next()) orelse return error.NoDeviceFound;

    const bad_desc = DeviceDescriptor{
        .is_raw = device_desc.is_raw,
        .mode = null,
        .id = device_desc.id,
    };
    try testing.expectError(error.InvalidParameter, a.requestDevice(bad_desc));
}

test "requestDevice behavior: invalid id" {
    const a = try init();
    defer a.deinit();

    var iter = a.outputDeviceIterator();
    var device_desc = (try iter.next()) orelse return error.NoDeviceFound;

    const bad_desc = DeviceDescriptor{
        .is_raw = device_desc.is_raw,
        .mode = device_desc.mode,
        .id = "wrong-id",
    };
    try testing.expectError(error.DeviceUnavailable, a.requestDevice(bad_desc));
}
