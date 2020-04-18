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

    pub fn getPastByte(self: *Self, distance: usize) !u8 {
        // Guard against trying to read back through the window
        //warn("distance {} vs {}\n", distance, self.ringAmountWritten);
        if ( distance > self.ringAmountWritten ) {
            return error.Failed;
        }

        // Also, 0 is not a valid distance
        if ( distance < 1 ) {
            return error.Failed;
        }

        // Grab a byte!
        var idx = ((self.ringWriteIndex + RING_LENGTH) - distance) % RING_LENGTH;
        return self.ringEntries[idx];
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


