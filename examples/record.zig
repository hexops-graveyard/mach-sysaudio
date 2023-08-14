//! Redirects input device into zig-out/raw_audio file.

const std = @import("std");
const sysaudio = @import("mach-sysaudio");

var recorder: sysaudio.Recorder = undefined;
var file: std.fs.File = undefined;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var ctx = try sysaudio.Context.init(null, gpa.allocator(), .{});
    defer ctx.deinit();
    try ctx.refresh();

    const device = ctx.defaultDevice(.capture) orelse return error.NoDevice;

    recorder = try ctx.createRecorder(device, readCallback, .{});
    defer recorder.deinit();
    try recorder.start();

    const zig_out = try std.fs.cwd().makeOpenPath("zig-out", .{});
    file = try zig_out.createFile("raw_audio", .{});

    std.debug.print(
        \\Recording to zig-out/raw_audio using:
        \\
        \\  device: {s}
        \\  channels: {}
        \\  sample_rate: {}
        \\
        \\You can play this recording back using e.g.:
        \\  $ ffplay -f f32le -ar {} -ac {} zig-out/raw_audio
        \\
    , .{
        device.name,
        device.channels.len,
        recorder.sampleRate(),
        recorder.sampleRate(),
        device.channels.len,
    });
    // Note: you may also use e.g.:
    //
    // ```
    // paplay -p --format=FLOAT32LE --rate 48000 --raw zig-out/raw_audio
    // aplay -c 2 -f FLOAT_LE -r 48000 zig-out/raw_audio
    // ```

    while (true) {}
}

fn readCallback(_: ?*anyopaque, frames: usize) void {
    var bw = std.io.bufferedWriter(file.writer());
    for (0..frames) |fi| {
        for (recorder.channels()) |ch| {
            const sample = recorder.read(ch, fi, f32);
            const sample_bytes: [4]u8 = @bitCast(sample);
            _ = bw.write(&sample_bytes) catch {};
        }
    }
    bw.flush() catch {};
}
