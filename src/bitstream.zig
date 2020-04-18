// vim: set sts=4 sw=4 et :
const std = @import("std");
const File = std.fs.File;

pub const InputBitStream = struct {
    const Self = @This();

    const maxBufferLength = 1024;

    stream: File,
    buffer: [maxBufferLength]u8 = [_]u8{0} ** maxBufferLength,
    bufferLength: usize = 0,
    bufferOffset: usize = 0,
    bitsLeft: u4 = 0,
    doneFetch: bool = false,

    pub fn wrapStream(stream: File) Self {
        return Self {
            .stream = stream,
        };
    }

    pub fn close(self: *Self) void {
        self.stream.close();
    }

    pub fn alignToByte(self: *Self) !void {
        if ( self.bitsLeft < 8 ) {
            self.bitsLeft = 0;
        } else {
            return error.failed;
        }
    }

    pub fn readBit(self: *Self) !u1 {
        if ( self.bitsLeft == 0 ) {
            self.bufferOffset += 1;
            if ( self.bufferOffset >= self.bufferLength ) {
                self.bufferOffset = 0;
                self.bufferLength = try self.stream.read(&self.buffer);
                if ( self.bufferLength == 0 ) {
                    return error.EndOfFile;
                }
            }
            self.bitsLeft = 8;
        }

        var result: u1 = @truncate(u1, self.buffer[self.bufferOffset]);
        self.buffer[self.bufferOffset] >>= 1;
        self.bitsLeft -= 1;
        return result;
    }

    pub fn readBits(self: *Self, bits: u7) !u64 {
        var i: u7 = 0;
        var v: u64 = 0;
        while ( i < bits ) : ( i += 1 ) {
            var bit: u1 = try self.readBit();
            v |= @intCast(u64, @intCast(u64, bit) << @intCast(u6, i));
        }

        return v;
    }

    pub fn readType(self: *Self, comptime T: type) !T {
        comptime const bits = @typeInfo(T).Int.bits;

        var i: u7 = 0;
        var v: T = 0;
        while ( i < bits ) : ( i += 1 ) {
            var bit: u1 = try self.readBit();
            v |= @intCast(T, @intCast(u64, bit) << @intCast(u6, i));
        }

        return v;
    }
};
