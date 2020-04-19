// vim: set sts=4 sw=4 et :
const std = @import("std");
const warn = std.debug.warn;

//const InputBitStream = @import("./bitstream.zig").InputBitStream;

pub fn CanonicalHuffmanTree(comptime Tlen: type, comptime Tval: type, maxLen: usize) type {
    const Tkey: type = usize;
    const bitWidthCount: usize = (1<<@typeInfo(Tlen).Int.bits);
    const Tmask: type = usize;
    return struct {
        const Self = @This();

        // Number of symbols that are actually in the tree.
        symbolCount: Tkey,

        // Map: packed symbol index -> symbol.
        //symbolTree: []Tval, // TODO: Understand slices --GM
        symbolTreeRaw: [maxLen]Tval, // backing buffer for symbolTree

        // Map: bit width -> value past last possible value for the bit width.
        symbolEnds: [bitWidthCount]Tmask,

        // Map: bit width -> index into symbolTree to first entry of the given bit width.
        symbolOffsets: [bitWidthCount]Tkey,

        pub fn fromLengths(lengths: []const Tlen) Self {
            const symbolCount = lengths.len;

            // Sort the symbols in length order, ignoring 0-length
            var symbolTree = [1]Tval{0} ** maxLen;
            var symbolEnds = [1]Tkey{0} ** bitWidthCount;
            var symbolOffsets = [1]Tkey{0} ** bitWidthCount;
            var nonzeroCount: usize = 0;
            var endValue: usize = 0;
            {
                var bitWidth: usize = 1;
                while ( bitWidth < bitWidthCount ) : ( bitWidth += 1 ) {
                    endValue <<= 1;
                    var startIndex = nonzeroCount;
                    symbolOffsets[bitWidth] = startIndex;
                    for ( lengths ) |bw, i| {
                        if ( bw == bitWidth ) {
                            //warn("{} entry {} = {}\n", bitWidth, nonzeroCount, i);
                            symbolTree[nonzeroCount] = @intCast(Tval, i);
                            nonzeroCount += 1;
                            endValue += 1;
                        }
                    }
                    symbolEnds[bitWidth] = endValue;
                    //warn("nzcount {} = {} / {}\n", bitWidth, startIndex, endValue);
                }
            }

            // Return our tree
            return Self {
                .symbolCount = symbolCount,
                .symbolTreeRaw = symbolTree,
                //.symbolTree = symbolTree[0..nonzeroCount],
                .symbolEnds = symbolEnds,
                .symbolOffsets = symbolOffsets,
            };
        }

        pub fn readFrom(self: *Self, stream: var) !Tval {
            var v: usize = 0;

            // Calculate the bit width and offset
            // TODO: Clean this mess up, it's quite unintuitive right now
            var bitWidth: usize = 0;
            var valueOffset: usize = 0;
            //warn("{} -> {}\n", bitWidth, self.symbolEnds[bitWidth]);
            while ( v >= self.symbolEnds[bitWidth] ) {
                v <<= 1;
                v |= @intCast(usize, try stream.readBitsNoEof(u1, 1));
                valueOffset = self.symbolEnds[bitWidth]*2;
                bitWidth += 1;
                //warn("{}: v={} - {} -> {} (offs={})\n", bitWidth, v, valueOffset, self.symbolEnds[bitWidth], self.symbolOffsets[bitWidth]);
            }

            // Find the correct index
            var idx: Tkey = @intCast(Tkey, (v - valueOffset) + self.symbolOffsets[bitWidth]);
            //warn("{}\n", idx);

            // Now read it
            var result = self.symbolTreeRaw[idx];
            return result;
        }
    };
}


