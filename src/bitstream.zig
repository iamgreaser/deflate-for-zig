// vim: set sts=4 sw=4 et :
const std = @import("std");
const File = std.fs.File;

pub const InputBitStream = struct {
    const Self = @This();

    stream: File,
    bitValue: [1]u8 = [1]u8{ 0 },
    bitsLeft: u4 = 0,

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
            self.bitValue[0] = 0;
        } else {
            return error.failed;
        }
    }

    pub fn readBit(self: *Self) !u1 {
        if ( self.bitsLeft == 0 ) {
            var bytes_read = try self.stream.read(&self.bitValue);
            if ( bytes_read != 1 ) { return error.EndOfFile; }
            self.bitsLeft = 8;
        }

        var result: u1 = @truncate(u1, self.bitValue[0]);
        self.bitValue[0] >>= 1;
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
