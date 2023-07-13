//! Redirects input device into stdout.
//! You may write the output into a file
//! and use one of the following tools to hear it:
//!
//! ```
//! paplay -p --format=FLOAT32LE --rate 48000 --raw ./audio
//! aplay -c 2 -f FLOAT_LE -r 48000 ./audio
//! ```

const std = @import("std");
const sysaudio = @import("sysaudio");

var recorder: sysaudio.Recorder = undefined;

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

    while (true) {}
}

fn readCallback(_: ?*anyopaque, frames: usize) void {
    var bw = std.io.bufferedWriter(std.io.getStdOut().writer());
    for (0..frames) |fi| {
        for (recorder.channels()) |ch| {
            const sample = recorder.read(ch, fi, f32);
            const sample_bytes: [4]u8 = @bitCast(sample);
            _ = bw.write(&sample_bytes) catch {};
        }
    }
    bw.flush() catch {};
}
