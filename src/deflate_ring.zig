// vim: set sts=4 sw=4 et :
const std = @import("std");
const warn = std.debug.warn;


pub const DeflateRing = struct {
    const Self = @This();

    const RING_LENGTH = 32 * 1024;

    ringEntries: [RING_LENGTH]u8 = [_]u8{0} ** RING_LENGTH,
    ringReadIndex: usize = 0,
    ringWriteIndex: usize = 0,
    ringAmountToRead: usize = 0,
    ringAmountWritten: usize = 0,

    pub fn addByte(self: *Self, byte: u8) !void {
        // Check...
        if ( self.ringAmountToRead >= RING_LENGTH ) {
            // Overflow!
            return error.Failed;
        }

        // OK, add it!
        self.ringEntries[self.ringWriteIndex] = byte;
        self.ringWriteIndex = (self.ringWriteIndex + 1) % RING_LENGTH;
        self.ringAmountToRead += 1;
        self.ringAmountWritten += 1;
    }

    pub fn copyPastBytes(self: *Self, copyLen: usize, copyDist: usize) !void {
        // Guard against trying to read back through the window
        //warn("distance {} vs {}\n", distance, self.ringAmountWritten);
        if ( copyDist > self.ringAmountWritten ) {
            return error.Failed;
        }

        // Also, 0 is not a valid distance
        if ( copyDist < 1 ) {
            return error.Failed;
        }

        // Check ahead of time
        if ( self.ringAmountToRead + copyLen > RING_LENGTH ) {
            // Overflow!
            return error.Failed;
        }

        // Copy bytes
        {
            var i: usize = 0;
            var idx = ((self.ringWriteIndex + RING_LENGTH) - copyDist) % RING_LENGTH;
            while ( i < copyLen ) : ( i += 1 ) {
                self.ringEntries[self.ringWriteIndex] = self.ringEntries[idx];
                idx = (idx + 1) % RING_LENGTH;
                self.ringWriteIndex = (self.ringWriteIndex + 1) % RING_LENGTH;
            }
            self.ringAmountToRead += copyLen;
            self.ringAmountWritten += copyLen;
        }

        // Sanity check
        if ( self.ringAmountToRead > RING_LENGTH ) {
            // Overflow!
            return error.Failed;
        }
    }

    pub fn pullByte(self: *Self) !u8 {
        // We need to actually have something to read here
        if ( self.isEmpty() ) {
            return error.Failed;
        }

        var byte: u8 = self.ringEntries[self.ringReadIndex];
        self.ringReadIndex = (self.ringReadIndex + 1) % RING_LENGTH;
        self.ringAmountToRead -= 1;

        return byte;
    }

    pub fn isEmpty(self: *Self) bool {
        return ( self.ringAmountToRead < 1 );
    }
};


