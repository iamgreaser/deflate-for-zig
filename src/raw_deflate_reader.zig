// vim: set sts=4 sw=4 et :
const std = @import("std");
const warn = std.debug.warn;

const Block = @import("./block.zig").Block;
    const HuffmanBlock = @import("./block.zig").HuffmanBlock;
    const RawBlock = @import("./block.zig").RawBlock;
const BlockTree = @import("./block_tree.zig").BlockTree;
const DeflateRing = @import("./deflate_ring.zig").DeflateRing;
const InputBitStream = @import("./bitstream.zig").InputBitStream;

pub const RawDeflateReader = struct {
    const Self = @This();

    readStream: *InputBitStream,
    ring: DeflateRing = DeflateRing {},
    isLastBlock: bool = false,
    currentBlock: Block = Block.Empty,

    pub fn readFromBitStream(readStream: *InputBitStream) Self {
        var self = Self {
            .readStream = readStream,
        };

        return self;
    }

    pub fn read(self: *Self, buffer: []u8) !usize {
        var i: usize = 0;
        while ( i < buffer.len ) : ( i += 1 ) {
            var j: usize = 0;

            var byte = self.readByte() catch |err| {
                if ( err == error.EndOfStream ) {
                    return i;
                } else {
                    return err;
                }
            };
            buffer[i] = byte;
        }

        return i;
    }

    fn fetchNextBlock(self: *Self) !void {
        //
        if ( self.isLastBlock ) {
            return error.EndOfStream;
        } else {
            self.fetchNextBlockUnconditionally() catch |err| {
                if ( err == error.EndOfStream ) {
                    return error.Failed;
                } else {
                    return err;
                }
            };
        }
    }
    fn fetchNextBlockUnconditionally(self: *Self) !void {
        // Not EOF, so grab a new block.
        var bfinal: u1 = try self.readStream.readBitsNoEof(u1, 1);
        var btype: u2 = try self.readStream.readBitsNoEof(u2, 2);

        //warn("New block: bfinal={}, btype={}\n", bfinal, btype);

        self.isLastBlock = switch ( bfinal ) {
            0 => false,
            1 => true,
        };
        self.currentBlock = try switch ( btype ) {
            0 => RawBlock.fromBitStream(self.readStream),
            1 => Block {
                .Huffman = HuffmanBlock {
                    .tree = BlockTree.makeStatic(),
                }
            },
            2 => Block {
                .Huffman = HuffmanBlock {
                    .tree = try BlockTree.fromBitStream(self.readStream),
                }
            },
            else => error.Failed,
        };
    }

    fn fetchNextBlockAndByte(self: *Self) !u8 {
        self.currentBlock = Block.Empty;
        try self.fetchNextBlock();
        return try self.readByte();
    }

    fn readByte(self: *Self) anyerror!u8 {
        // Do we need to fetch a new block?
        if ( self.currentBlock == Block.Empty ) {
            // Possibly.
            try self.fetchNextBlock();
        }

        //
        return switch ( self.currentBlock ) {
            Block.Raw => self.currentBlock.Raw.readByteFrom(
                self.readStream,
                &self.ring),
            Block.Huffman => self.currentBlock.Huffman.readByteFrom(
                self.readStream,
                &self.ring),
            else => error.Failed,
        } catch |err| {
            if ( err == error.EndOfStream ) {
                return try self.fetchNextBlockAndByte();
            } else {
                return err;
            }
        };
    }
};

