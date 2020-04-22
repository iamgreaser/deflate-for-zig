// vim: set sts=4 sw=4 et :
const std = @import("std");
const warn = std.debug.warn;

const BlockTree = @import("./block_tree.zig").BlockTree;
const DeflateRing = @import("./deflate_ring.zig").DeflateRing;

pub fn RawBlock(comptime InputBitStream: type) type {
    return struct {
        const Self = @This();
        const ThisBlock = Block(InputBitStream);

        bytes_left: u16,

        pub fn fromBitStream(stream: *InputBitStream) !ThisBlock {
            stream.alignToByte();

            var len: u16 = try stream.readBitsNoEof(u16, 16);
            var nlen: u16 = try stream.readBitsNoEof(u16, 16);
            // Integrity check
            if (len != (nlen ^ 0xFFFF)) {
                return error.Failed;
            }

            return ThisBlock{
                .Raw = Self{
                    .bytes_left = len,
                },
            };
        }

        pub fn readByteFrom(self: *Self, stream: *InputBitStream, ring: *DeflateRing) !u8 {
            if (self.bytes_left >= 1) {
                try ring.addByte(try stream.readBitsNoEof(u8, 8));
                var byte: u8 = try ring.pullByte();
                self.bytes_left -= 1;
                return byte;
            } else {
                return error.EndOfStream;
            }
        }
    };
}

pub fn HuffmanBlock(comptime InputBitStream: type) type {
    return struct {
        const Self = @This();
        const ThisBlock = Block(InputBitStream);

        const len_extra_bits_table = result: {
            var table = [_]u3{0} ** 29;
            var i: usize = 4;
            while (i < table.len - 1) : (i += 1) {
                var bits = ((i - 4) >> 2);
                table[i] = @intCast(u4, bits);
            }

            break :result table;
        };

        const len_base_table = result: {
            var table = [_]u9{0} ** 29;
            var i: usize = 0;
            var v: u9 = 3;
            while (i < table.len) : (i += 1) {
                var bits = len_extra_bits_table[i];
                table[i] = @intCast(u9, v);
                v += (1 << bits);
                // The second-to-last case is kinda weird.
                // It omits the last theoretically-valid value.
                if (i == table.len - 2) {
                    v -= 1;
                }
            }
            break :result table;
        };

        const dist_extra_bits_table = result: {
            var table = [_]u4{0} ** 30;
            var i: usize = 2;
            while (i < table.len) : (i += 1) {
                var bits = ((i - 2) >> 1);
                table[i] = @intCast(u4, bits);
            }
            break :result table;
        };

        const dist_base_table = result: {
            var table = [_]u16{0} ** 30;
            var i: usize = 0;
            var v: u16 = 1;
            while (i < table.len) : (i += 1) {
                var bits = dist_extra_bits_table[i];
                table[i] = @intCast(u16, v);
                v += (1 << bits);
            }
            break :result table;
        };

        tree: BlockTree(InputBitStream),

        pub fn readByteFrom(self: *Self, stream: *InputBitStream, ring: *DeflateRing) !u8 {
            // Do we have anything queued?
            while (ring.isEmpty()) {
                // No. Alright, we need more bytes.
                var v: u9 = try self.tree.readLitFrom(stream);

                if (v >= 0 and v <= 255) {
                    try ring.addByte(@intCast(u8, v));
                } else if (v >= 257 and v <= 285) {
                    var extra_bits_for_len = len_extra_bits_table[v - 257];
                    var copy_len = len_base_table[v - 257] + try stream.readBitsNoEof(u5, extra_bits_for_len);

                    var dist_offset: u5 = try self.tree.readDistFrom(stream);
                    var extra_bits_for_dist = dist_extra_bits_table[dist_offset];
                    var copy_dist = dist_base_table[dist_offset] + try stream.readBitsNoEof(u13, extra_bits_for_dist);

                    //warn("copy {} offset {}\n", copy_len, copy_dist);
                    //warn("len def v={} base={} len={}\n", v, len_base_table[v-257], extra_bits_for_len);

                    try ring.copyPastBytes(copy_len, copy_dist);
                } else if (v == 256) {
                    return error.EndOfStream;
                } else {
                    return error.Failed;
                }
            }

            // Alright! Read a byte.
            var byte: u8 = try ring.pullByte();
            return byte;
        }
    };
}

pub fn Block(comptime InputBitStream: type) type {
    return union(enum) {
        Empty: void,
        Raw: RawBlock(InputBitStream),
        Huffman: HuffmanBlock(InputBitStream),
    };
}
