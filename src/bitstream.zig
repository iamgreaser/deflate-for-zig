// vim: set sts=4 sw=4 et :
const std = @import("std");
const Endian = std.builtin.Endian;
const InStream = std.io.InStream;
const BitInStream = std.io.BitInStream;
const BufferedInStream = std.io.BufferedInStream;
const File = std.fs.File;

pub fn InputBitStreamBase(comptime TInStream: type) type {
    return BitInStream(Endian.Little, TInStream);
}

pub const InputBitStream = InputBitStreamBase(File.InStream);
