const std = @import("std");
const builtin = @import("builtin");
const main = @import("main.zig");
const backends = @import("backends.zig");
const util = @import("util.zig");
const c = @cImport({
    @cInclude("CoreAudio/CoreAudio.h");
    @cInclude("AudioUnit/AudioUnit.h");
});
const native_endian = builtin.cpu.arch.endian();
var is_darling = false;

pub const Context = struct {
    allocator: std.mem.Allocator,
    devices_info: util.DevicesInfo,

    pub fn init(allocator: std.mem.Allocator, options: main.Context.Options) !backends.BackendContext {
        _ = options;

        if (std.fs.accessAbsolute("/usr/lib/darling", .{})) {
            is_darling = true;
        } else |_| {}

        var self = try allocator.create(Context);
        errdefer allocator.destroy(self);
        self.* = .{
            .allocator = allocator,
            .devices_info = util.DevicesInfo.init(),
        };

        return .{ .coreaudio = self };
    }

    pub fn deinit(self: *Context) void {
        for (self.devices_info.list.items) |d|
            freeDevice(self.allocator, d);
        self.devices_info.list.deinit(self.allocator);
        self.allocator.destroy(self);
    }

    pub fn refresh(self: *Context) !void {
        for (self.devices_info.list.items) |d|
            freeDevice(self.allocator, d);
        self.devices_info.clear();

        var prop_address = c.AudioObjectPropertyAddress{
            .mSelector = c.kAudioHardwarePropertyDevices,
            .mScope = c.kAudioObjectPropertyScopeGlobal,
            .mElement = c.kAudioObjectPropertyElementMain,
        };

        var io_size: u32 = 0;
        if (c.AudioObjectGetPropertyDataSize(
            c.kAudioObjectSystemObject,
            &prop_address,
            0,
            null,
            &io_size,
        ) != c.noErr) {
            return error.OpeningDevice;
        }

        const devices_count = io_size / @sizeOf(c.AudioObjectID);
        if (devices_count == 0) return;

        var devs = try self.allocator.alloc(c.AudioObjectID, devices_count);
        defer self.allocator.free(devs);
        if (c.AudioObjectGetPropertyData(
            c.kAudioObjectSystemObject,
            &prop_address,
            0,
            null,
            &io_size,
            @as(*anyopaque, @ptrCast(devs)),
        ) != c.noErr) {
            return error.OpeningDevice;
        }

        var default_input_id: c.AudioObjectID = undefined;
        var default_output_id: c.AudioObjectID = undefined;

        io_size = @sizeOf(c.AudioObjectID);
        if (c.AudioHardwareGetProperty(
            c.kAudioHardwarePropertyDefaultInputDevice,
            &io_size,
            &default_input_id,
        ) != c.noErr) {
            return error.OpeningDevice;
        }

        io_size = @sizeOf(c.AudioObjectID);
        if (c.AudioHardwareGetProperty(
            c.kAudioHardwarePropertyDefaultOutputDevice,
            &io_size,
            &default_output_id,
        ) != c.noErr) {
            return error.OpeningDevice;
        }

        for (devs) |id| {
            var buf_list = try self.allocator.create(c.AudioBufferList);
            defer self.allocator.destroy(buf_list);

            for (std.meta.tags(main.Device.Mode)) |mode| {
                io_size = 0;
                prop_address.mSelector = c.kAudioDevicePropertyStreamConfiguration;
                prop_address.mScope = switch (mode) {
                    .playback => c.kAudioObjectPropertyScopeOutput,
                    .capture => c.kAudioObjectPropertyScopeInput,
                };
                if (c.AudioObjectGetPropertyDataSize(
                    id,
                    &prop_address,
                    0,
                    null,
                    &io_size,
                ) != c.noErr) {
                    continue;
                }

                if (c.AudioObjectGetPropertyData(
                    id,
                    &prop_address,
                    0,
                    null,
                    &io_size,
                    buf_list,
                ) != c.noErr) {
                    return error.OpeningDevice;
                }

                if (buf_list.mBuffers[0].mNumberChannels == 0) break;

                const audio_buffer_list_property_address = c.AudioObjectPropertyAddress{
                    .mSelector = c.kAudioDevicePropertyStreamConfiguration,
                    .mScope = switch (mode) {
                        .playback => c.kAudioDevicePropertyScopeOutput,
                        .capture => c.kAudioDevicePropertyScopeInput,
                    },
                    .mElement = c.kAudioObjectPropertyElementMain,
                };
                var output_audio_buffer_list: c.AudioBufferList = undefined;
                var audio_buffer_list_size: c_uint = undefined;

                if (c.AudioObjectGetPropertyDataSize(
                    id,
                    &audio_buffer_list_property_address,
                    0,
                    null,
                    &audio_buffer_list_size,
                ) != c.noErr) {
                    return error.OpeningDevice;
                }

                if (c.AudioObjectGetPropertyData(
                    id,
                    &prop_address,
                    0,
                    null,
                    &audio_buffer_list_size,
                    &output_audio_buffer_list,
                ) != c.noErr) {
                    return error.OpeningDevice;
                }

                var output_channel_count: usize = 0;
                for (0..output_audio_buffer_list.mNumberBuffers) |mBufferIndex| {
                    output_channel_count += output_audio_buffer_list.mBuffers[mBufferIndex].mNumberChannels;
                }

                var channels = try self.allocator.alloc(main.Channel, output_channel_count);

                prop_address.mSelector = c.kAudioDevicePropertyNominalSampleRate;
                io_size = @sizeOf(f64);
                var sample_rate: f64 = undefined;
                if (c.AudioObjectGetPropertyData(
                    id,
                    &prop_address,
                    0,
                    null,
                    &io_size,
                    &sample_rate,
                ) != c.noErr) {
                    return error.OpeningDevice;
                }

                io_size = @sizeOf([*]const u8);
                if (c.AudioDeviceGetPropertyInfo(
                    id,
                    0,
                    0,
                    c.kAudioDevicePropertyDeviceName,
                    &io_size,
                    null,
                ) != c.noErr) {
                    return error.OpeningDevice;
                }

                const name = try self.allocator.allocSentinel(u8, io_size, 0);
                errdefer self.allocator.free(name);
                if (c.AudioDeviceGetProperty(
                    id,
                    0,
                    0,
                    c.kAudioDevicePropertyDeviceName,
                    &io_size,
                    name.ptr,
                ) != c.noErr) {
                    return error.OpeningDevice;
                }
                const id_str = try std.fmt.allocPrintZ(self.allocator, "{d}", .{id});
                errdefer self.allocator.free(id_str);

                var dev = main.Device{
                    .id = id_str,
                    .name = name,
                    .mode = mode,
                    .channels = channels,
                    .formats = &.{ .i16, .i32, .f32 },
                    .sample_rate = .{
                        .min = @as(u24, @intFromFloat(@floor(sample_rate))),
                        .max = @as(u24, @intFromFloat(@floor(sample_rate))),
                    },
                };

                try self.devices_info.list.append(self.allocator, dev);
                if (id == default_output_id and mode == .playback) {
                    self.devices_info.default_output = self.devices_info.list.items.len - 1;
                }

                if (id == default_input_id and mode == .capture) {
                    self.devices_info.default_input = self.devices_info.list.items.len - 1;
                }
            }
        }
    }

    pub fn devices(self: Context) []const main.Device {
        return self.devices_info.list.items;
    }

    pub fn defaultDevice(self: Context, mode: main.Device.Mode) ?main.Device {
        return self.devices_info.default(mode);
    }

    pub fn createPlayer(self: *Context, device: main.Device, writeFn: main.WriteFn, options: main.StreamOptions) !backends.BackendPlayer {
        var player = try self.allocator.create(Player);
        errdefer self.allocator.destroy(player);

        var component_desc = c.AudioComponentDescription{
            .componentType = c.kAudioUnitType_Output,
            .componentSubType = c.kAudioUnitSubType_HALOutput,
            .componentManufacturer = c.kAudioUnitManufacturer_Apple,
            .componentFlags = 0,
            .componentFlagsMask = 0,
        };
        const component = c.AudioComponentFindNext(null, &component_desc);
        if (component == null) return error.OpeningDevice;

        var audio_unit: c.AudioComponentInstance = undefined;
        if (c.AudioComponentInstanceNew(component, &audio_unit) != c.noErr) return error.OpeningDevice;

        if (c.AudioUnitInitialize(audio_unit) != c.noErr) return error.OpeningDevice;
        errdefer _ = c.AudioUnitUninitialize(audio_unit);

        const device_id = std.fmt.parseInt(c.AudioDeviceID, device.id, 10) catch unreachable;
        if (c.AudioUnitSetProperty(
            audio_unit,
            c.kAudioOutputUnitProperty_CurrentDevice,
            c.kAudioUnitScope_Input,
            0,
            &device_id,
            @sizeOf(c.AudioDeviceID),
        ) != c.noErr) {
            return error.OpeningDevice;
        }

        const stream_desc = try createStreamDesc(options.format, options.sample_rate, device.channels.len);
        if (c.AudioUnitSetProperty(
            audio_unit,
            c.kAudioUnitProperty_StreamFormat,
            c.kAudioUnitScope_Input,
            0,
            &stream_desc,
            @sizeOf(c.AudioStreamBasicDescription),
        ) != c.noErr) {
            return error.OpeningDevice;
        }

        const render_callback = c.AURenderCallbackStruct{
            .inputProc = Player.renderCallback,
            .inputProcRefCon = player,
        };
        if (c.AudioUnitSetProperty(
            audio_unit,
            c.kAudioUnitProperty_SetRenderCallback,
            c.kAudioUnitScope_Input,
            0,
            &render_callback,
            @sizeOf(c.AURenderCallbackStruct),
        ) != c.noErr) {
            return error.OpeningDevice;
        }

        player.* = .{
            .allocator = self.allocator,
            .audio_unit = audio_unit.?,
            .is_paused = false,
            .vol = 1.0,
            .writeFn = writeFn,
            .user_data = options.user_data,
            .channels = device.channels,
            .format = options.format,
            .sample_rate = options.sample_rate,
            .write_step = options.format.frameSize(device.channels.len),
        };
        return .{ .coreaudio = player };
    }

    pub fn createRecorder(self: *Context, device: main.Device, readFn: main.ReadFn, options: main.StreamOptions) !backends.BackendRecorder {
        var recorder = try self.allocator.create(Recorder);
        errdefer self.allocator.destroy(recorder);

        const device_id = std.fmt.parseInt(c.AudioDeviceID, device.id, 10) catch unreachable;
        var io_size: u32 = 0;
        var prop_address = c.AudioObjectPropertyAddress{
            .mSelector = c.kAudioDevicePropertyStreamConfiguration,
            .mScope = c.kAudioObjectPropertyScopeInput,
            .mElement = c.kAudioObjectPropertyElementMain,
        };

        if (c.AudioObjectGetPropertyDataSize(
            device_id,
            &prop_address,
            0,
            null,
            &io_size,
        ) != c.noErr) {
            return error.OpeningDevice;
        }

        std.debug.assert(io_size == @sizeOf(c.AudioBufferList));
        var buf_list = try self.allocator.create(c.AudioBufferList);
        errdefer self.allocator.destroy(buf_list);

        if (c.AudioObjectGetPropertyData(
            device_id,
            &prop_address,
            0,
            null,
            &io_size,
            @as(*anyopaque, @ptrCast(buf_list)),
        ) != c.noErr) {
            return error.OpeningDevice;
        }

        var component_desc = c.AudioComponentDescription{
            .componentType = c.kAudioUnitType_Output,
            .componentSubType = c.kAudioUnitSubType_HALOutput,
            .componentManufacturer = c.kAudioUnitManufacturer_Apple,
            .componentFlags = 0,
            .componentFlagsMask = 0,
        };
        const component = c.AudioComponentFindNext(null, &component_desc);
        if (component == null) return error.OpeningDevice;

        var audio_unit: c.AudioComponentInstance = undefined;
        if (c.AudioComponentInstanceNew(component, &audio_unit) != c.noErr) return error.OpeningDevice;

        if (c.AudioUnitInitialize(audio_unit) != c.noErr) return error.OpeningDevice;
        errdefer _ = c.AudioUnitUninitialize(audio_unit);

        var enable_io: u32 = 1;
        if (c.AudioUnitSetProperty(
            audio_unit,
            c.kAudioOutputUnitProperty_EnableIO,
            c.kAudioUnitScope_Input,
            1,
            &enable_io,
            @sizeOf(u32),
        ) != c.noErr) {
            return error.OpeningDevice;
        }

        enable_io = 0;
        if (c.AudioUnitSetProperty(
            audio_unit,
            c.kAudioOutputUnitProperty_EnableIO,
            c.kAudioUnitScope_Output,
            0,
            &enable_io,
            @sizeOf(u32),
        ) != c.noErr) {
            return error.OpeningDevice;
        }

        if (c.AudioUnitSetProperty(
            audio_unit,
            c.kAudioOutputUnitProperty_CurrentDevice,
            c.kAudioUnitScope_Output,
            1,
            &device_id,
            @sizeOf(c.AudioDeviceID),
        ) != c.noErr) {
            return error.OpeningDevice;
        }

        const stream_desc = try createStreamDesc(options.format, options.sample_rate, device.channels.len);
        if (c.AudioUnitSetProperty(
            audio_unit,
            c.kAudioUnitProperty_StreamFormat,
            c.kAudioUnitScope_Output,
            1,
            &stream_desc,
            @sizeOf(c.AudioStreamBasicDescription),
        ) != c.noErr) {
            return error.OpeningDevice;
        }

        const capture_callback = c.AURenderCallbackStruct{
            .inputProc = Recorder.captureCallback,
            .inputProcRefCon = recorder,
        };
        if (c.AudioUnitSetProperty(
            audio_unit,
            c.kAudioOutputUnitProperty_SetInputCallback,
            c.kAudioUnitScope_Output,
            1,
            &capture_callback,
            @sizeOf(c.AURenderCallbackStruct),
        ) != c.noErr) {
            return error.OpeningDevice;
        }

        recorder.* = .{
            .allocator = self.allocator,
            .audio_unit = audio_unit.?,
            .is_paused = false,
            .vol = 1.0,
            .buf_list = buf_list,
            .readFn = readFn,
            .user_data = options.user_data,
            .channels = device.channels,
            .format = options.format,
            .sample_rate = options.sample_rate,
            .read_step = options.format.frameSize(device.channels.len),
        };
        return .{ .coreaudio = recorder };
    }
};

pub const Player = struct {
    allocator: std.mem.Allocator,
    audio_unit: c.AudioUnit,
    is_paused: bool,
    vol: f32,
    writeFn: main.WriteFn,
    user_data: ?*anyopaque,

    channels: []main.Channel,
    format: main.Format,
    sample_rate: u24,
    write_step: u8,

    pub fn renderCallback(
        self_opaque: ?*anyopaque,
        action_flags: [*c]c.AudioUnitRenderActionFlags,
        time_stamp: [*c]const c.AudioTimeStamp,
        bus_number: u32,
        frames_left: u32,
        buf: [*c]c.AudioBufferList,
    ) callconv(.C) c.OSStatus {
        _ = action_flags;
        _ = time_stamp;
        _ = bus_number;
        _ = frames_left;

        const self = @as(*Player, @ptrCast(@alignCast(self_opaque.?)));

        for (self.channels, 0..) |*ch, i| {
            ch.ptr = @as([*]u8, @ptrCast(buf.*.mBuffers[0].mData.?)) + self.format.frameSize(i);
        }
        const frames = buf.*.mBuffers[0].mDataByteSize / self.format.frameSize(self.channels.len);
        self.writeFn(self.user_data, frames);

        return c.noErr;
    }

    pub fn deinit(self: *Player) void {
        _ = c.AudioOutputUnitStop(self.audio_unit);
        _ = c.AudioUnitUninitialize(self.audio_unit);
        _ = c.AudioComponentInstanceDispose(self.audio_unit);
        self.allocator.destroy(self);
    }

    pub fn start(self: *Player) !void {
        try self.play();
    }

    pub fn play(self: *Player) !void {
        if (c.AudioOutputUnitStart(self.audio_unit) != c.noErr) {
            return error.CannotPlay;
        }
        self.is_paused = false;
    }

    pub fn pause(self: *Player) !void {
        if (c.AudioOutputUnitStop(self.audio_unit) != c.noErr) {
            return error.CannotPause;
        }
        self.is_paused = true;
    }

    pub fn paused(self: Player) bool {
        return self.is_paused;
    }

    pub fn setVolume(self: *Player, vol: f32) !void {
        if (c.AudioUnitSetParameter(
            self.audio_unit,
            c.kHALOutputParam_Volume,
            c.kAudioUnitScope_Global,
            0,
            vol,
            0,
        ) != c.noErr) {
            if (is_darling) return;
            return error.CannotSetVolume;
        }
    }

    pub fn volume(self: Player) !f32 {
        var vol: f32 = 0;
        if (c.AudioUnitGetParameter(
            self.audio_unit,
            c.kHALOutputParam_Volume,
            c.kAudioUnitScope_Global,
            0,
            &vol,
        ) != c.noErr) {
            if (is_darling) return 1;
            return error.CannotGetVolume;
        }
        return vol;
    }
};

pub const Recorder = struct {
    allocator: std.mem.Allocator,
    audio_unit: c.AudioUnit,
    is_paused: bool,
    vol: f32,
    buf_list: *c.AudioBufferList,
    m_data: ?[]u8 = null,
    readFn: main.ReadFn,
    user_data: ?*anyopaque,

    channels: []main.Channel,
    format: main.Format,
    sample_rate: u24,
    read_step: u8,

    pub fn captureCallback(
        self_opaque: ?*anyopaque,
        action_flags: [*c]c.AudioUnitRenderActionFlags,
        time_stamp: [*c]const c.AudioTimeStamp,
        bus_number: u32,
        num_frames: u32,
        buffer_list: [*c]c.AudioBufferList,
    ) callconv(.C) c.OSStatus {
        _ = buffer_list;

        const self = @as(*Recorder, @ptrCast(@alignCast(self_opaque.?)));

        // We want interleaved multi-channel audio, when multiple channels are available-so we'll
        // only use a single buffer. If we wanted non-interleaved audio we would use multiple
        // buffers.
        var m_buffer = &self.buf_list.*.mBuffers[0];

        // Ensure our buffer matches the size needed for the render operation. Note that the buffer
        // may grow (in the case of multi-channel audio during the first render callback) or shrink
        // in e.g. the event of the device being unplugged and the default input device switching.
        const new_len = self.format.size() * num_frames * self.channels.len;
        if (self.m_data == null or self.m_data.?.len != new_len) {
            if (self.m_data) |old| self.allocator.free(old);
            self.m_data = self.allocator.alloc(u8, new_len) catch return c.noErr;
        }
        self.buf_list.*.mNumberBuffers = 1;
        m_buffer.mData = self.m_data.?.ptr;
        m_buffer.mDataByteSize = @intCast(self.m_data.?.len);
        m_buffer.mNumberChannels = @intCast(self.channels.len);

        const err_no = c.AudioUnitRender(
            self.audio_unit,
            action_flags,
            time_stamp,
            bus_number,
            num_frames,
            self.buf_list,
        );
        if (err_no != c.noErr) {
            // TODO: err_no here is rather helpful, we should indicate what it is back to the user
            // in this event probably?
            return c.noErr;
        }

        if (self.buf_list.*.mNumberBuffers == 1) {
            for (self.channels, 0..) |*ch, i| {
                ch.ptr = @as([*]u8, @ptrCast(self.buf_list.*.mBuffers[0].mData.?)) + self.format.frameSize(i);
            }
        } else {
            for (self.channels, 0..) |*ch, i| {
                ch.ptr = @as([*]u8, @ptrCast(self.buf_list.*.mBuffers[i].mData.?));
            }
        }

        self.readFn(self.user_data, num_frames);
        return c.noErr;
    }

    pub fn deinit(self: *Recorder) void {
        _ = c.AudioOutputUnitStop(self.audio_unit);
        _ = c.AudioUnitUninitialize(self.audio_unit);
        _ = c.AudioComponentInstanceDispose(self.audio_unit);
        self.allocator.destroy(self.buf_list);
        self.allocator.destroy(self);
    }

    pub fn start(self: *Recorder) !void {
        try self.record();
    }

    pub fn record(self: *Recorder) !void {
        if (c.AudioOutputUnitStart(self.audio_unit) != c.noErr) {
            return error.CannotRecord;
        }
        self.is_paused = false;
    }

    pub fn pause(self: *Recorder) !void {
        if (c.AudioOutputUnitStop(self.audio_unit) != c.noErr) {
            return error.CannotPause;
        }
        self.is_paused = true;
    }

    pub fn paused(self: Recorder) bool {
        return self.is_paused;
    }

    pub fn setVolume(self: *Recorder, vol: f32) !void {
        if (c.AudioUnitSetParameter(
            self.audio_unit,
            c.kHALOutputParam_Volume,
            c.kAudioUnitScope_Global,
            0,
            vol,
            0,
        ) != c.noErr) {
            if (is_darling) return;
            return error.CannotSetVolume;
        }
    }

    pub fn volume(self: Recorder) !f32 {
        var vol: f32 = 0;
        if (c.AudioUnitGetParameter(
            self.audio_unit,
            c.kHALOutputParam_Volume,
            c.kAudioUnitScope_Global,
            0,
            &vol,
        ) != c.noErr) {
            if (is_darling) return 1;
            return error.CannotGetVolume;
        }
        return vol;
    }
};

fn freeDevice(allocator: std.mem.Allocator, device: main.Device) void {
    allocator.free(device.id);
    allocator.free(device.name);
    allocator.free(device.channels);
}

fn createStreamDesc(format: main.Format, sample_rate: u24, ch_count: usize) !c.AudioStreamBasicDescription {
    var desc = c.AudioStreamBasicDescription{
        .mSampleRate = @as(f64, @floatFromInt(sample_rate)),
        .mFormatID = c.kAudioFormatLinearPCM,
        .mFormatFlags = switch (format) {
            .i16 => c.kAudioFormatFlagIsSignedInteger,
            .i24 => c.kAudioFormatFlagIsSignedInteger,
            .i32 => c.kAudioFormatFlagIsSignedInteger,
            .f32 => c.kAudioFormatFlagIsFloat,
            .u8 => return error.IncompatibleDevice,
            .i24_4b => return error.IncompatibleDevice,
        },
        .mBytesPerPacket = format.frameSize(ch_count),
        .mFramesPerPacket = 1,
        .mBytesPerFrame = format.frameSize(ch_count),
        .mChannelsPerFrame = @as(c_uint, @intCast(ch_count)),
        .mBitsPerChannel = switch (format) {
            .i16 => 16,
            .i24 => 24,
            .i32 => 32,
            .f32 => 32,
            .u8 => unreachable,
            .i24_4b => unreachable,
        },
        .mReserved = 0,
    };

    if (native_endian == .Big) {
        desc.mFormatFlags |= c.kAudioFormatFlagIsBigEndian;
    }

    return desc;
}

test {
    std.testing.refAllDeclsRecursive(@This());
}
