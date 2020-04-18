// vim: set sts=4 sw=4 et :
const std = @import("std");
const builtin = std.builtin;
const BitInStream = std.io.BitInStream;
const File = std.fs.File;

pub const InputBitStream = struct {
    const Self = @This();
    const ThisBitInStream = BitInStream(builtin.Endian.Little, File.InStream);

    bitInStream: ThisBitInStream,

    pub fn wrapStream(stream: File) Self {
        return Self {
            .bitInStream = ThisBitInStream.init(stream.inStream()),
        };
    }

    pub inline fn alignToByte(self: *Self) !void {
        // No name change needed!
        return self.bitInStream.alignToByte();
    }

    pub inline fn readBit(self: *Self) !u1 {
        return @intCast(u1, try self.readBits(1));
    }

    pub inline fn readBits(self: *Self, bits: u7) !u64 {
        return self.bitInStream.readBitsNoEof(u64, bits) catch |err| {
            if ( err == error.EndOfStream ) {
                return error.EndOfFile;
            } else {
                return err;
            }
        };
    }

    pub inline fn readType(self: *Self, comptime T: type) !T {
        comptime const bits = @intCast(u7, @typeInfo(T).Int.bits);
        return @intCast(T, try self.readBits(bits));
    }
};
