// vim: set sts=4 sw=4 et :
const std = @import("std");
const warn = std.debug.warn;

/// Fixed-length element sliding window.
/// Write to the very end.
/// Read from an offset from the end or theoretical start.
/// Older entries are removed.
/// Useful for audio processing and LZ77-style compression.
pub fn SlidingWindow(comptime Element: type, comptime window_length: comptime_int) type {
    return struct {
        const Self = @This();

        entries: [window_length]Element = undefined, //[_]Element{0} ** window_length,
        read_index: usize = 0,
        write_index: usize = 0,
        amount_to_read: usize = 0,
        amount_written: usize = 0,

        /// Appends an element to the end of the window.
        pub fn appendElement(self: *Self, element: Element) !void {
            // Check...
            // TODO: remove the read index stuff from this type
            if (self.amount_to_read >= window_length) {
                // Overflow!
                return error.Overflow;
            }

            // OK, add it!
            self.entries[self.write_index] = element;
            self.write_index = (self.write_index + 1) % window_length;
            self.amount_to_read += 1;
            self.amount_written += 1;
        }

        /// Copies multiple elements from the end of the sliding window.
        pub fn copyElementsFromEnd(self: *Self, copy_dist: usize, copy_len: usize) !void {
            // Guard against trying to read back through the window
            //warn("distance {} vs {}\n", distance, self.amount_written);
            if (copy_dist > self.amount_written) {
                return error.OutOfRangeIndex;
            }

            // Also, 0 is not a valid distance
            if (copy_dist < 1) {
                return error.OutOfRangeIndex;
            }

            // Check ahead of time
            if (self.amount_to_read + copy_len > window_length) {
                // Overflow!
                return error.Overflow;
            }

            // Copy elements
            {
                var i: usize = 0;
                var idx = ((self.write_index + window_length) - copy_dist) % window_length;
                while (i < copy_len) : (i += 1) {
                    self.entries[self.write_index] = self.entries[idx];
                    idx = (idx + 1) % window_length;
                    self.write_index = (self.write_index + 1) % window_length;
                }
                self.amount_to_read += copy_len;
                self.amount_written += copy_len;
            }

            // Sanity check
            if (self.amount_to_read > window_length) {
                // Overflow!
                return error.Overflow;
            }
        }

        pub fn readElement(self: *Self) !Element {
            // We need to actually have something to read here
            if (self.isEmpty()) {
                return error.Underflow;
            }

            var element: Element = self.entries[self.read_index];
            self.read_index = (self.read_index + 1) % window_length;
            self.amount_to_read -= 1;

            return element;
        }

        pub fn isEmpty(self: *Self) bool {
            return (self.amount_to_read < 1);
        }
    };
}
