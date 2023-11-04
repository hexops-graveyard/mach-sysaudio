const std = @import("std");
const expectEqual = std.testing.expectEqual;
const shr = std.math.shr;
const maxInt = std.math.maxInt;
const clamp = std.math.clamp;

pub inline fn unsignedToSigned(comptime SrcType: type, src: []const SrcType, comptime DestType: type, dst: []DestType) void {
    for (src, dst) |*in_sample, *out_sample| {
        const half = 1 << (@bitSizeOf(SrcType) - 1);
        const trunc = @bitSizeOf(DestType) - @bitSizeOf(SrcType);
        out_sample.* = @as(DestType, @intCast(in_sample.* -% half)) << trunc;
    }
}

test unsignedToSigned {
    var u8_to_i16: [1]i16 = undefined;
    var u8_to_i24: [1]i24 = undefined;
    var u8_to_i32: [1]i32 = undefined;

    unsignedToSigned(u8, &.{5}, i16, &u8_to_i16);
    unsignedToSigned(u8, &.{5}, i24, &u8_to_i24);
    unsignedToSigned(u8, &.{5}, i32, &u8_to_i32);

    try expectEqual(@as(i16, -31488), u8_to_i16[0]);
    try expectEqual(@as(i24, -8060928), u8_to_i24[0]);
    try expectEqual(@as(i32, -2063597568), u8_to_i32[0]);
}

pub inline fn unsignedToFloat(comptime SrcType: type, src: []const SrcType, comptime DestType: type, dst: []DestType) void {
    for (src, dst) |*in_sample, *out_sample| {
        const half = (1 << @typeInfo(SrcType).Int.bits) / 2;
        out_sample.* = (@as(DestType, @floatFromInt(in_sample.*)) - half) * 1.0 / half;
    }
}

test unsignedToFloat {
    var u8_to_f32: [1]f32 = undefined;
    unsignedToFloat(u8, &.{5}, f32, &u8_to_f32);
    try expectEqual(@as(f32, -0.9609375), u8_to_f32[0]);
}

pub inline fn signedToUnsigned(comptime SrcType: type, src: []const SrcType, comptime DestType: type, dst: []DestType) void {
    for (src, dst) |*in_sample, *out_sample| {
        const half = 1 << @bitSizeOf(DestType) - 1;
        const trunc = @bitSizeOf(SrcType) - @bitSizeOf(DestType);
        out_sample.* = @intCast((in_sample.* >> trunc) + half);
    }
}

test signedToUnsigned {
    var i16_to_u8: [1]u8 = undefined;
    var i24_to_u8: [1]u8 = undefined;
    var i32_to_u8: [1]u8 = undefined;

    signedToUnsigned(i16, &.{5}, u8, &i16_to_u8);
    signedToUnsigned(i24, &.{5}, u8, &i24_to_u8);
    signedToUnsigned(i32, &.{5}, u8, &i32_to_u8);

    try expectEqual(@as(u8, 128), i16_to_u8[0]);
    try expectEqual(@as(u8, 128), i24_to_u8[0]);
    try expectEqual(@as(u8, 128), i32_to_u8[0]);
}

pub inline fn signedToSigned(comptime SrcType: type, src: []const SrcType, comptime DestType: type, dst: []DestType) void {
    for (src, dst) |*in_sample, *out_sample| {
        const trunc = @bitSizeOf(SrcType) - @bitSizeOf(DestType);
        out_sample.* = shr(DestType, @intCast(in_sample.*), trunc);
    }
}

test signedToSigned {
    var i16_to_i24: [1]i24 = undefined;
    var i16_to_i32: [1]i32 = undefined;
    var i24_to_i16: [1]i16 = undefined;
    var i24_to_i32: [1]i32 = undefined;
    var i32_to_i16: [1]i16 = undefined;
    var i32_to_i24: [1]i24 = undefined;

    signedToSigned(i24, &.{5}, i16, &i24_to_i16);
    signedToSigned(i32, &.{5}, i16, &i32_to_i16);

    signedToSigned(i16, &.{5}, i24, &i16_to_i24);
    signedToSigned(i32, &.{5}, i24, &i32_to_i24);

    signedToSigned(i16, &.{5}, i32, &i16_to_i32);
    signedToSigned(i24, &.{5}, i32, &i24_to_i32);

    try expectEqual(@as(i24, 1280), i16_to_i24[0]);
    try expectEqual(@as(i32, 327680), i16_to_i32[0]);

    try expectEqual(@as(i16, 0), i24_to_i16[0]);
    try expectEqual(@as(i32, 1280), i24_to_i32[0]);

    try expectEqual(@as(i16, 0), i32_to_i16[0]);
    try expectEqual(@as(i24, 0), i32_to_i24[0]);
}

pub inline fn signedToFloat(comptime SrcType: type, src: []const SrcType, comptime DestType: type, dst: []DestType) void {
    for (src, dst) |*in_sample, *out_sample| {
        const max: comptime_float = maxInt(SrcType) + 1;
        out_sample.* = @as(DestType, @floatFromInt(in_sample.*)) * (1.0 / max);
    }
}

test signedToFloat {
    var i16_to_f32: [1]f32 = undefined;
    var i24_to_f32: [1]f32 = undefined;
    var i32_to_f32: [1]f32 = undefined;

    signedToFloat(i16, &.{5}, f32, &i16_to_f32);
    signedToFloat(i24, &.{5}, f32, &i24_to_f32);
    signedToFloat(i32, &.{5}, f32, &i32_to_f32);

    try expectEqual(@as(f32, 1.52587890625e-4), i16_to_f32[0]);
    try expectEqual(@as(f32, 5.9604644775391e-7), i24_to_f32[0]);
    try expectEqual(@as(f32, 2.32830643e-09), i32_to_f32[0]);
}

pub inline fn floatToUnsigned(comptime SrcType: type, src: []const SrcType, comptime DestType: type, dst: []DestType) void {
    for (src, dst) |*in_sample, *out_sample| {
        const half = maxInt(DestType) / 2;
        out_sample.* = @intFromFloat(clamp((in_sample.* * half) + (half + 1), 0, maxInt(DestType)));
    }
}

test floatToUnsigned {
    var f32_to_u8: [1]u8 = undefined;
    floatToUnsigned(f32, &.{0.5}, u8, &f32_to_u8);
    try expectEqual(@as(u8, 191), f32_to_u8[0]);
}

pub inline fn floatToSigned(comptime SrcType: type, src: []const SrcType, comptime DestType: type, dst: []DestType) void {
    for (src, dst) |*in_sample, *out_sample| {
        const max = maxInt(DestType);
        out_sample.* = @truncate(@as(i32, @intFromFloat(in_sample.* * max)));
    }
}

test floatToSigned {
    var f32_to_i16: [1]i16 = undefined;
    var f32_to_i24: [1]i24 = undefined;
    var f32_to_i32: [1]i32 = undefined;

    floatToSigned(f32, &.{0.5}, i16, &f32_to_i16);
    floatToSigned(f32, &.{0.5}, i24, &f32_to_i24);
    floatToSigned(f32, &.{0.5}, i32, &f32_to_i32);

    try expectEqual(@as(i16, 16383), f32_to_i16[0]);
    try expectEqual(@as(i24, 4194303), f32_to_i24[0]);
    try expectEqual(@as(i32, 1073741824), f32_to_i32[0]);
}
