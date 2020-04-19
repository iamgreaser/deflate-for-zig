// vim: set sts=4 sw=4 et :
const std = @import("std");
const warn = std.debug.warn;

pub const DeflateRing = struct {
    const Self = @This();

    const RING_LENGTH = 32 * 1024;

    ring_entries: [RING_LENGTH]u8 = [_]u8{0} ** RING_LENGTH,
    ring_read_index: usize = 0,
    ring_write_index: usize = 0,
    ring_amount_to_read: usize = 0,
    ring_amount_written: usize = 0,

    pub fn addByte(self: *Self, byte: u8) !void {
        // Check...
        if (self.ring_amount_to_read >= RING_LENGTH) {
            // Overflow!
            return error.Failed;
        }

        // OK, add it!
        self.ring_entries[self.ring_write_index] = byte;
        self.ring_write_index = (self.ring_write_index + 1) % RING_LENGTH;
        self.ring_amount_to_read += 1;
        self.ring_amount_written += 1;
    }

    pub fn copyPastBytes(self: *Self, copy_len: usize, copy_dist: usize) !void {
        // Guard against trying to read back through the window
        //warn("distance {} vs {}\n", distance, self.ring_amount_written);
        if (copy_dist > self.ring_amount_written) {
            return error.Failed;
        }

        // Also, 0 is not a valid distance
        if (copy_dist < 1) {
            return error.Failed;
        }

        // Check ahead of time
        if (self.ring_amount_to_read + copy_len > RING_LENGTH) {
            // Overflow!
            return error.Failed;
        }

        // Copy bytes
        {
            var i: usize = 0;
            var idx = ((self.ring_write_index + RING_LENGTH) - copy_dist) % RING_LENGTH;
            while (i < copy_len) : (i += 1) {
                self.ring_entries[self.ring_write_index] = self.ring_entries[idx];
                idx = (idx + 1) % RING_LENGTH;
                self.ring_write_index = (self.ring_write_index + 1) % RING_LENGTH;
            }
            self.ring_amount_to_read += copy_len;
            self.ring_amount_written += copy_len;
        }

        // Sanity check
        if (self.ring_amount_to_read > RING_LENGTH) {
            // Overflow!
            return error.Failed;
        }
    }

    pub fn pullByte(self: *Self) !u8 {
        // We need to actually have something to read here
        if (self.isEmpty()) {
            return error.Failed;
        }

        var byte: u8 = self.ring_entries[self.ring_read_index];
        self.ring_read_index = (self.ring_read_index + 1) % RING_LENGTH;
        self.ring_amount_to_read -= 1;

        return byte;
    }

    pub fn isEmpty(self: *Self) bool {
        return (self.ring_amount_to_read < 1);
    }
};
