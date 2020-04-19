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

    read_stream: *InputBitStream,
    ring: DeflateRing = DeflateRing {},
    is_last_block: bool = false,
    current_block: Block = Block.Empty,

    pub fn readFromBitStream(read_stream: *InputBitStream) Self {
        var self = Self {
            .read_stream = read_stream,
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
        if ( self.is_last_block ) {
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
        var bfinal: u1 = try self.read_stream.readBitsNoEof(u1, 1);
        var btype: u2 = try self.read_stream.readBitsNoEof(u2, 2);

        //warn("New block: bfinal={}, btype={}\n", bfinal, btype);

        self.is_last_block = switch ( bfinal ) {
            0 => false,
            1 => true,
        };
        self.current_block = try switch ( btype ) {
            0 => RawBlock.fromBitStream(self.read_stream),
            1 => Block {
                .Huffman = HuffmanBlock {
                    .tree = BlockTree.makeStatic(),
                }
            },
            2 => Block {
                .Huffman = HuffmanBlock {
                    .tree = try BlockTree.fromBitStream(self.read_stream),
                }
            },
            else => error.Failed,
        };
    }

    fn fetchNextBlockAndByte(self: *Self) !u8 {
        self.current_block = Block.Empty;
        try self.fetchNextBlock();
        return try self.readByte();
    }

    fn readByte(self: *Self) anyerror!u8 {
        // Do we need to fetch a new block?
        if ( self.current_block == Block.Empty ) {
            // Possibly.
            try self.fetchNextBlock();
        }

        //
        return switch ( self.current_block ) {
            Block.Raw => self.current_block.Raw.readByteFrom(
                self.read_stream,
                &self.ring),
            Block.Huffman => self.current_block.Huffman.readByteFrom(
                self.read_stream,
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

