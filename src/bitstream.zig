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
            return error.Failed;
        }
    }

    pub fn readBit(self: *Self) !u1 {
        return @intCast(u1, try self.readBits(1));
    }

    fn fetchNextByte(self: *Self) !void {
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

    pub fn readBits(self: *Self, bits: u7) !u64 {
        var i: u7 = 0;
        var v: u64 = 0;
        var bitsStillToFetch: u7 = bits;

        // If we need to fetch something, do so now.
        if ( self.bitsLeft == 0 ) {
            try self.fetchNextByte();
        }

        while ( true ) {
            var bitsInByte: u4 = self.bitsLeft;
            var byte: u8 = self.buffer[self.bufferOffset];

            // Do we have enough bits to fill what's left?
            if ( bitsStillToFetch <= bitsInByte ) {
                // Yes - grab it and bail out.
                if ( bitsStillToFetch != 8 ) {
                    byte &= (@intCast(u8, 1)<<@intCast(u3, bitsStillToFetch))-1;
                }
                v |= @intCast(u64, @intCast(u64, byte) << @intCast(u6, i));
                i += bitsInByte;
                self.bitsLeft -= @intCast(u4, bitsStillToFetch);
                if ( bitsStillToFetch != 8 ) {
                    self.buffer[self.bufferOffset] >>= @intCast(u3, bitsStillToFetch);
                }
                return v;

            } else {
                // No - grab what's left and continue.
                v |= @intCast(u64, @intCast(u64, byte) << @intCast(u6, i));
                i += bitsInByte;
                bitsStillToFetch -= bitsInByte;

                // Fetch the next byte, because it will be needed
                try self.fetchNextByte();
            }
        }
    }

    pub fn readType(self: *Self, comptime T: type) !T {
        comptime const bits = @intCast(u7, @typeInfo(T).Int.bits);
        return @intCast(T, try self.readBits(bits));
    }
};
