// vim: set sts=4 sw=4 et :
const std = @import("std");
const warn = std.debug.warn;

const BlockTree = @import("./block_tree.zig").BlockTree;
const DeflateRing = @import("./deflate_ring.zig").DeflateRing;
const InputBitStream = @import("./bitstream.zig").InputBitStream;


pub const RawBlock = struct {
    const Self = @This();

    bytesLeft: u16,

    pub fn fromBitStream(stream: *InputBitStream) !Block {
        stream.alignToByte();

        var  len: u16 = try stream.readBitsNoEof(u16, 16);
        var nlen: u16 = try stream.readBitsNoEof(u16, 16);
        // Integrity check
        if ( len != (nlen ^ 0xFFFF) ) {
            return error.Failed;
        }

        return Block {
            .Raw = RawBlock {
                .bytesLeft = len,
            }
        };
    }

    pub fn readByteFrom(self: *Self, stream: *InputBitStream, ring: *DeflateRing) !u8 {
        if ( self.bytesLeft >= 1 ) {
            try ring.addByte(try stream.readBitsNoEof(u8, 8));
            var byte: u8 = try ring.pullByte();
            self.bytesLeft -= 1;
            return byte;
        } else {
            return error.EndOfStream;
        }
    }
};
pub const HuffmanBlock = struct {
    const Self = @This();

    const lenExtraBits = result: {
        var table = [_]u3{0} ** 29;
        var i: usize = 4;
        while ( i < table.len-1 ) : ( i += 1 ) {
            var bits = ((i-4)>>2);
            table[i] = @intCast(u4, bits);
        }

        break :result table;
    };

    const lenBase = result: {
        var table = [_]u9{0} ** 29;
        var i: usize = 0;
        var v: u9 = 3;
        while ( i < table.len ) : ( i += 1 ) {
            var bits = lenExtraBits[i];
            table[i] = @intCast(u9, v);
            v += (1<<bits);
            // The second-to-last case is kinda weird.
            // It omits the last theoretically-valid value.
            if ( i == table.len-2 ) { v -= 1; }
        }
        break :result table;
    };

    const distExtraBits = result: {
        var table = [_]u4{0} ** 30;
        var i: usize = 2;
        while ( i < table.len ) : ( i += 1 ) {
            var bits = ((i-2)>>1);
            table[i] = @intCast(u4, bits);
        }
        break :result table;
    };

    const distBase = result: {
        var table = [_]u16{0} ** 30;
        var i: usize = 0;
        var v: u16 = 1;
        while ( i < table.len ) : ( i += 1 ) {
            var bits = distExtraBits[i];
            table[i] = @intCast(u16, v);
            v += (1<<bits);
        }
        break :result table;
    };

    tree: BlockTree,

    pub fn readByteFrom(self: *Self, stream: *InputBitStream, ring: *DeflateRing) !u8 {
        // Do we have anything queued?
        while ( ring.isEmpty() ) {
            // No. Alright, we need more bytes.
            var v: u9 = try self.tree.readLitFrom(stream);

            if ( v >= 0 and v <= 255 ) {
                try ring.addByte(@intCast(u8, v));
            } else if ( v >= 257 and v <= 285 ) {
                var extraBitsForLen = lenExtraBits[v-257];
                var copyLen = lenBase[v-257] + try stream.readBitsNoEof(u5, extraBitsForLen);

                var distOffset: u5 = try self.tree.readDistFrom(stream);
                var extraBitsForDist = distExtraBits[distOffset];
                var copyDist = distBase[distOffset] + try stream.readBitsNoEof(u13, extraBitsForDist);

                //warn("copy {} offset {}\n", copyLen, copyDist);
                //warn("len def v={} base={} len={}\n", v, lenBase[v-257], extraBitsForLen);

                try ring.copyPastBytes(copyLen, copyDist);
            } else if ( v == 256 ) {
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
pub const Block = union(enum) {
    Empty: void,
    Raw: RawBlock,
    Huffman: HuffmanBlock,
};

