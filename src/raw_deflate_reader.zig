// vim: set sts=4 sw=4 et :
const std = @import("std");
const warn = std.debug.warn;

const Block = @import("./block.zig").Block;
const RawBlock = @import("./block.zig").RawBlock;
const HuffmanBlock = @import("./block.zig").HuffmanBlock;
const BlockTree = @import("./block_tree.zig").BlockTree;
const SlidingWindow = @import("./sliding_window.zig").SlidingWindow;

pub const DeflateSlidingWindow = SlidingWindow(u8, 32 * 1024);

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

pub fn RawDeflateReader(comptime InputBitStream: type) type {
    return struct {
        const Self = @This();
        const ThisBlock = Block(InputBitStream);
        const ThisRawBlock = RawBlock(InputBitStream);
        const ThisHuffmanBlock = HuffmanBlock(InputBitStream);
        const ThisBlockTree = BlockTree(InputBitStream);

        read_stream: *InputBitStream,
        window: DeflateSlidingWindow = DeflateSlidingWindow{},
        bytes_to_read_from_window: usize = 0,
        is_last_block: bool = false,
        current_block: ThisBlock = ThisBlock.Empty,

        pub fn readFromBitStream(read_stream: *InputBitStream) Self {
            var self = Self{
                .read_stream = read_stream,
            };

            return self;
        }

        pub fn read(self: *Self, buffer: []u8) !usize {
            var i: usize = 0;
            while (i < buffer.len) : (i += 1) {
                var j: usize = 0;

                var byte = self.readByte() catch |err| {
                    if (err == error.EndOfStream) {
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
            if (self.is_last_block) {
                return error.EndOfStream;
            } else {
                self.fetchNextBlockUnconditionally() catch |err| {
                    if (err == error.EndOfStream) {
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

            //warn("New block: bfinal={}, btype={}\n", .{ bfinal, btype });

            self.is_last_block = switch (bfinal) {
                0 => false,
                1 => true,
            };
            self.current_block = try switch (btype) {
                0 => ThisRawBlock.fromBitStream(self.read_stream),
                1 => ThisBlock{
                    .Huffman = ThisHuffmanBlock{
                        .tree = ThisBlockTree.makeStatic(),
                    },
                },
                2 => ThisBlock{
                    .Huffman = ThisHuffmanBlock{
                        .tree = try ThisBlockTree.fromBitStream(self.read_stream),
                    },
                },
                else => error.Failed,
            };
        }

        fn readByteFromWindow(self: *Self) !u8 {
            var idx: usize = self.bytes_to_read_from_window;
            var byte: u8 = try self.window.readElementFromEnd(idx);
            self.bytes_to_read_from_window -= 1;
            return byte;
        }

        fn readElementFromBlockDirectly(self: *Self) !u9 {
            return try switch (self.current_block) {
                .Empty => error.EndOfBlock,
                .Raw => self.current_block.Raw.readElementFrom(self.read_stream),
                .Huffman => self.current_block.Huffman.readElementFrom(self.read_stream),
                else => error.Failed,
            };
        }

        fn readElementFromBlock(self: *Self) !u9 {
            return self.readElementFromBlockDirectly() catch |err| {
                if (err == error.EndOfBlock) {
                    self.current_block = ThisBlock.Empty;
                    try self.fetchNextBlock();
                    return try self.readElementFromBlockDirectly();
                } else {
                    return err;
                }
            };
        }

        fn processBlockElement(self: *Self, v: u9) !void {
            if (v >= 0 and v <= 255) {
                try self.window.appendElement(@intCast(u8, v));
                self.bytes_to_read_from_window += 1;
            } else if (v >= 257 and v <= 285) {
                var extra_bits_for_len = len_extra_bits_table[v - 257];
                var copy_len = len_base_table[v - 257] + try self.read_stream.readBitsNoEof(u5, extra_bits_for_len);

                var dist_offset: u9 = try switch (self.current_block) {
                    .Huffman => self.current_block.Huffman.readDistFrom(self.read_stream),
                    else => error.Failed,
                };
                var extra_bits_for_dist = dist_extra_bits_table[dist_offset];
                var copy_dist = dist_base_table[dist_offset] + try self.read_stream.readBitsNoEof(u13, extra_bits_for_dist);

                //warn("copy {} offset {}\n", copy_len, copy_dist);
                //warn("len def v={} base={} len={}\n", v, len_base_table[v-257], extra_bits_for_len);

                try self.window.copyElementsFromEnd(copy_dist, copy_len);
                self.bytes_to_read_from_window += copy_len;
            } else {
                // NOTE: 256 (end of block) does NOT appear in this layer!
                return error.Failed;
            }
        }

        fn readByte(self: *Self) !u8 {
            // Do we have bytes to read from the window?
            if (self.bytes_to_read_from_window >= 1) {
                // Yes - read from there first.
                return try self.readByteFromWindow();
            }

            var v: u9 = try self.readElementFromBlock();
            try self.processBlockElement(v);

            // At this point we should have something in the window.
            // If not, well, enjoy your runtime error.
            return try self.readByteFromWindow();
        }
    };
}
