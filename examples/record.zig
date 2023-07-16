//! Redirects input device into ./raw_audio file.

const std = @import("std");
const sysaudio = @import("sysaudio");

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

    file = try std.fs.cwd().createFile("raw_audio", .{});

    std.debug.print("Recording to ./raw_audio using:\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("  device: {s}\n", .{device.name});
    std.debug.print("  channels: {}\n", .{device.channels.len});
    std.debug.print("  sample_rate: {}\n", .{recorder.sampleRate()});
    std.debug.print("\n", .{});
    std.debug.print("You can play this recording back using e.g.:\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("  $ ffplay -f f32le -ar {} -ac {} raw_audio", .{recorder.sampleRate(), device.channels.len});
    std.debug.print("\n", .{});
    // Note: you may also use e.g.:
    //
    // ```
    // paplay -p --format=FLOAT32LE --rate 48000 --raw ./audio
    // aplay -c 2 -f FLOAT_LE -r 48000 ./audio
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
