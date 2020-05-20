// vim: set sts=4 sw=4 et :
const std = @import("std");
const warn = std.debug.warn;

const CanonicalHuffmanTree = @import("./huffman.zig").CanonicalHuffmanTree;

pub fn BlockTree(comptime InputBitStream: type) type {
    return struct {
        const Self = @This();

        lit_tree: CanonicalHuffmanTree(u4, u9, 31 + 257),
        dist_tree: CanonicalHuffmanTree(u4, u6, 31 + 1),

        pub fn makeStatic() Self {
            // FIXME: zig fmt seems to ignore these comments --GM
            // zig fmt: off
            const lit_table = (([_]u4{8} ** (144 - 0)) ++ ([_]u4{9} ** (256 - 144)) ++ ([_]u4{7} ** (280 - 256)) ++ ([_]u4{8} ** (288 - 280)));
            // zig fmt: on
            const lit_tree = CanonicalHuffmanTree(u4, u9, 31 + 257).fromLengths(&lit_table);

            const dist_table = [_]u4{5} ** 32;
            const dist_tree = CanonicalHuffmanTree(u4, u6, 31 + 1).fromLengths(&dist_table);

            return Self{
                .lit_tree = lit_tree,
                .dist_tree = dist_tree,
            };
        }

        pub fn fromBitStream(stream: *InputBitStream) !Self {
            const raw_hlit: u5 = try stream.readBitsNoEof(u5, 5);
            const raw_hdist: u5 = try stream.readBitsNoEof(u5, 5);
            const raw_hclen: u4 = try stream.readBitsNoEof(u4, 4);

            // Convert to their real values
            const real_hclen: u5 = @intCast(u5, raw_hclen) + 4;
            const real_hdist: u6 = @intCast(u6, raw_hdist) + 1;
            const real_hlit: u9 = @intCast(u9, raw_hlit) + 257;
            //warn("HLIT  = {} -> {}\n", raw_hlit,  real_hlit);
            //warn("HDIST = {} -> {}\n", raw_hdist, real_hdist);
            //warn("HCLEN = {} -> {}\n", raw_hclen, real_hclen);

            var clen_table: [15 + 4]u3 = [_]u3{0} ** (15 + 4);
            const clen_remap: [15 + 4]u5 = [_]u5{
                16, 17, 18, 0,  8,
                7,  9,  6,  10, 5,
                11, 4,  12, 3,  13,
                2,  14, 1,  15,
            };

            // Parse the code length table
            {
                var i: u5 = 0;
                while (i < real_hclen) : (i += 1) {
                    const k: u5 = clen_remap[i];
                    const v: u3 = try stream.readBitsNoEof(u3, 3);
                    clen_table[k] = v;
                    //warn("clen {} = {}\n", k, v);
                }
            }

            // Build a canonical huffman tree
            const clen_tree = CanonicalHuffmanTree(u3, u5, 15 + 4).fromLengths(&clen_table);

            // Build the other trees
            const lit_tree = try buildDeflateHuffmanTree(u9, 31 + 257, real_hlit, &clen_tree, stream);
            const dist_tree = try buildDeflateHuffmanTree(u6, 31 + 1, real_hdist, &clen_tree, stream);

            return Self{
                .lit_tree = lit_tree,
                .dist_tree = dist_tree,
            };
        }

        pub fn readLitFrom(self: *Self, stream: *InputBitStream) !u9 {
            return try self.lit_tree.readFrom(stream);
        }

        pub fn readDistFrom(self: *Self, stream: *InputBitStream) !u6 {
            return try self.dist_tree.readFrom(stream);
        }

        fn buildDeflateHuffmanTree(comptime Tval: type, comptime max_len: Tval, actual_len: Tval, clen_tree: *const CanonicalHuffmanTree(u3, u5, 15 + 4), stream: *InputBitStream) !CanonicalHuffmanTree(u4, Tval, max_len) {
            // Read tree lengths
            var table: [max_len]u4 = [_]u4{0} ** (max_len);
            {
                var i: Tval = 0;
                var prev: u4 = undefined;
                while (i < actual_len) {
                    const v: u5 = try clen_tree.readFrom(stream);
                    //warn("hlit {} = {}\n", i, v);

                    switch (v) {
                        // Copy previous 3+u2 times
                        16 => {
                            // Can't copy a previous value if it's not there
                            if (i < 1) {
                                return error.Failed;
                            }
                            const times: usize = 3 + @as(usize, try stream.readBitsNoEof(u2, 2));
                            var j: usize = 0;
                            while (j < times) : (j += 1) {
                                table[i] = prev;
                                i += 1;
                            }
                        },

                        // Repeat 0 for 3+u3 times
                        17 => {
                            const times: usize = 3 + @as(usize, try stream.readBitsNoEof(u3, 3));
                            var j: usize = 0;
                            while (j < times) : (j += 1) {
                                table[i] = 0;
                                i += 1;
                            }
                        },

                        // Repeat 0 for 11+u7 times
                        18 => {
                            const times: usize = 11 + @as(usize, try stream.readBitsNoEof(u7, 7));
                            var j: usize = 0;
                            while (j < times) : (j += 1) {
                                table[i] = 0;
                                i += 1;
                            }
                        },

                        else => {
                            prev = @intCast(u4, v);
                            table[i] = prev;
                            i += 1;
                        },
                    }
                }
            }

            // Build a canonical huffman tree
            return CanonicalHuffmanTree(u4, Tval, max_len).fromLengths(&table);
        }
    };
}
