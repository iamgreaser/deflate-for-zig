// vim: set sts=4 sw=4 et :
const std = @import("std");
const warn = std.debug.warn;

const BlockTree = @import("./block_tree.zig").BlockTree;
const DeflateSlidingWindow = @import("./raw_deflate_reader.zig").DeflateSlidingWindow;

pub fn RawBlock(comptime InputBitStream: type) type {
    return struct {
        const Self = @This();
        const ThisBlock = Block(InputBitStream);

        bytes_left: u16,

        pub fn fromBitStream(stream: *InputBitStream) !ThisBlock {
            stream.alignToByte();

            const len: u16 = try stream.readBitsNoEof(u16, 16);
            const nlen: u16 = try stream.readBitsNoEof(u16, 16);
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

        pub fn readElementFrom(self: *Self, stream: *InputBitStream) !u9 {
            if (self.bytes_left >= 1) {
                const v: u9 = try stream.readBitsNoEof(u9, 8);
                self.bytes_left -= 1;
                return v;
            } else {
                return error.EndOfBlock;
            }
        }
    };
}

pub fn HuffmanBlock(comptime InputBitStream: type) type {
    return struct {
        const Self = @This();
        const ThisBlock = Block(InputBitStream);

        tree: BlockTree(InputBitStream),

        pub fn readElementFrom(self: *Self, stream: *InputBitStream) !u9 {
            const v: u9 = try self.tree.readLitFrom(stream);

            if (v == 256) {
                return error.EndOfBlock;
            } else {
                return v;
            }
        }

        pub fn readDistFrom(self: *Self, stream: *InputBitStream) !u5 {
            return try self.tree.readDistFrom(stream);
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
