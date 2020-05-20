// vim: set sts=4 sw=4 et :
const std = @import("std");
const TypeInfo = std.builtin.TypeInfo;
const warn = std.debug.warn;

pub fn CanonicalHuffmanTree(comptime Tlen: type, max_len: usize) type {
    return struct {
        const Self = @This();

        pub const Tval: type = @Type(TypeInfo{
            .Int = .{
                .is_signed = false,
                .bits = @floatToInt(comptime_int, @ceil(@log2(@intToFloat(f64, max_len)))),
            },
        });
        const bit_width_count: usize = (1 << @typeInfo(Tlen).Int.bits);
        pub const Tkey: type = @Type(TypeInfo{
            .Int = .{
                .is_signed = false,
                .bits = bit_width_count,
            },
        });

        // Number of symbols that are actually in the tree.
        symbol_count: Tkey,

        // Map: packed symbol index -> symbol.
        //symbol_tree: []Tval, // TODO: Understand slices --GM
        symbol_tree_raw: [max_len]Tval, // backing buffer for symbol_tree

        // Map: bit width -> value past last possible value for the bit width.
        symbol_ends: [bit_width_count]Tkey,

        // Map: bit width -> index into symbol_tree to first entry of the given bit width.
        symbol_offsets: [bit_width_count]Tkey,

        pub fn fromLengths(lengths: []const Tlen) Self {
            const symbol_count = @intCast(Tkey, lengths.len);

            // Sort the symbols in length order, ignoring 0-length
            var symbol_tree = [1]Tval{0} ** max_len;
            var symbol_ends = [1]Tkey{0} ** bit_width_count;
            var symbol_offsets = [1]Tkey{0} ** bit_width_count;
            var nonzero_count: Tkey = 0;
            var end_value: Tkey = 0;
            {
                var bit_width: usize = 1;
                while (bit_width < bit_width_count) : (bit_width += 1) {
                    end_value <<= 1;
                    var start_index = nonzero_count;
                    symbol_offsets[bit_width] = start_index;
                    for (lengths) |bw, i| {
                        if (bw == bit_width) {
                            //warn("{} entry {} = {}\n", bit_width, nonzero_count, i);
                            symbol_tree[nonzero_count] = @intCast(Tval, i);
                            nonzero_count += 1;
                            end_value += 1;
                        }
                    }
                    symbol_ends[bit_width] = end_value;
                    //warn("nzcount {} = {} / {}\n", bit_width, start_index, end_value);
                }
            }

            // Return our tree
            return Self{
                .symbol_count = symbol_count,
                .symbol_tree_raw = symbol_tree,
                //.symbol_tree = symbol_tree[0..nonzero_count],
                .symbol_ends = symbol_ends,
                .symbol_offsets = symbol_offsets,
            };
        }

        pub fn readFrom(self: *const Self, stream: var) !Tval {
            var v: usize = 0;

            // Calculate the bit width and offset
            // TODO: Clean this mess up, it's quite unintuitive right now
            var bit_width: usize = 0;
            var value_offset: usize = 0;
            //warn("{} -> {}\n", bit_width, self.symbol_ends[bit_width]);
            while (v >= self.symbol_ends[bit_width]) {
                v <<= 1;
                v |= try stream.readBitsNoEof(u1, 1);
                value_offset = self.symbol_ends[bit_width] * 2;
                bit_width += 1;
                //warn("{}: v={} - {} -> {} (offs={})\n", bit_width, v, value_offset, self.symbol_ends[bit_width], self.symbol_offsets[bit_width]);
            }

            // Find the correct index
            const idx: Tkey = @intCast(Tkey, (v - value_offset) + self.symbol_offsets[bit_width]);
            //warn("{}\n", idx);

            // Now read it
            const result = self.symbol_tree_raw[idx];
            return result;
        }
    };
}
