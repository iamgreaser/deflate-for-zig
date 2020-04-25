// vim: set sts=4 sw=4 et :
const std = @import("std");
const max = std.math.max;
const min = std.math.min;
const warn = std.debug.warn;

/// Fixed-length element sliding window.
/// Write to the very end.
/// Read from an offset from the end or theoretical start.
/// Older elements are removed.
/// Useful for audio processing and LZ77-style compression.
pub fn SlidingWindow(comptime Element: type, window_length: usize) type {
    return struct {
        const Self = @This();

        elements: [window_length]Element = undefined, //[_]Element{0} ** window_length,
        write_index: usize = 0,
        current_window_length: usize = 0,

        /// Appends an element to the end of the window.
        pub fn appendElement(self: *Self, element: Element) !void {
            // Add it!
            self.elements[self.write_index] = element;
            self.write_index = (self.write_index + 1) % window_length;
            if (self.current_window_length < window_length) {
                self.current_window_length += 1;
            }
        }

        /// Given an offset from the element immediately past the end
        /// of the sliding window, read the element at that point.
        pub fn readElementFromEnd(self: *Self, offset: usize) !Element {
            // Guard against trying to read back through the window
            if (offset > self.current_window_length) {
                return error.IndexOutOfRange;
            }

            // Also, 0 is not a valid distance
            if (offset < 1) {
                return error.IndexOutOfRange;
            }

            // We survived, so return the element
            var idx = ((self.write_index + window_length) - offset) % window_length;
            return self.elements[idx];
        }

        /// Given an offset from the element immediately past the end
        /// of the sliding window, and an array to fill in, read the
        /// elements from that point at that point.
        ///
        /// Returns the number of elements actually read.
        pub fn readElementsFromEnd(self: *Self, buffer: []Element, offset: usize) !usize {
            // Guard against trying to read back through the window
            if (offset > self.current_window_length) {
                return error.IndexOutOfRange;
            }

            var elements_to_read = min(offset, buffer.len);
            var i: usize = 0;
            var beg_idx = ((self.write_index + window_length) - offset) % window_length;
            var end_idx = beg_idx + elements_to_read;

            // Do we need to split this into 2 copies?
            if (end_idx > window_length) {
                // Yes - do 2 copies.
                var block_1_length = window_length - beg_idx;
                var block_2_length = elements_to_read - block_1_length;
                std.mem.copy(Element, buffer[0..block_1_length], self.elements[beg_idx..]);
                std.mem.copy(Element, buffer[block_1_length..], self.elements[0..block_2_length]);
            } else {
                // No - do 1 copy.
                std.mem.copy(Element, buffer, self.elements[beg_idx..end_idx]);
            }

            return elements_to_read;
        }

        /// Copies multiple elements from the end of the sliding window
        /// element-by-element.
        ///
        /// A theoretical `copy_dist` of 0 would point to reading just
        /// past the last element in the sliding window, so the minimum
        /// distance to be provided is 1.
        ///
        /// If `copy_dist` is less than `copy_len` then the elements
        /// are cyclically repeated. For example, if `copy_dist` is 1,
        /// then this will repeat the last byte in the window `copy_len`
        /// times.
        pub fn copyElementsFromEnd(self: *Self, copy_dist: usize, copy_len: usize) !void {
            // Guard against trying to read back through the window
            if (copy_dist > self.current_window_length) {
                return error.IndexOutOfRange;
            }

            // Also, 0 is not a valid distance
            if (copy_dist < 1) {
                return error.IndexOutOfRange;
            }

            // Copy elements
            {
                var i: usize = 0;
                var idx = ((self.write_index + window_length) - copy_dist) % window_length;
                while (i < copy_len) : (i += 1) {
                    self.elements[self.write_index] = self.elements[idx];
                    idx = (idx + 1) % window_length;
                    self.write_index = (self.write_index + 1) % window_length;
                }
                self.current_window_length = max(self.current_window_length + copy_len, window_length);
            }
        }
    };
}
