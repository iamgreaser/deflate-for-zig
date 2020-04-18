// vim: set sts=4 sw=4 et :
const std = @import("std");
const warn = std.debug.warn;

const CanonicalHuffmanTree = @import("./huffman.zig").CanonicalHuffmanTree;
const InputBitStream = @import("./bitstream.zig").InputBitStream;


pub const BlockTree = struct {
    const Self = @This();

    litTree: CanonicalHuffmanTree(u4, u9, 31+257),
    distTree: CanonicalHuffmanTree(u4, u5, 31+1),

    pub fn makeStatic() BlockTree {
        const litTable = (
               ([_]u4{8} ** (144-  0))
            ++ ([_]u4{9} ** (256-144))
            ++ ([_]u4{7} ** (280-256))
            ++ ([_]u4{8} ** (288-280)));
        var litTree = CanonicalHuffmanTree(u4, u9, 31+257).fromLengths(&litTable);

        const distTable = [_]u4{5} ** 32;
        var distTree = CanonicalHuffmanTree(u4, u5, 31+1).fromLengths(&distTable);

        return BlockTree {
            .litTree = litTree,
            .distTree = distTree,
        };
    }

    pub fn fromBitStream(stream: *InputBitStream) !BlockTree {
        var rawHlit:  u5 = try stream.readType(u5);
        var rawHdist: u5 = try stream.readType(u5);
        var rawHclen: u4 = try stream.readType(u4);

        // Convert to their real values
        var realHclen: u5 = u5(rawHclen) + 4;
        var realHdist: u6 = u6(rawHdist) + 1;
        var realHlit:  u9 = u9(rawHlit)  + 257;
        //warn("HLIT  = {} -> {}\n", rawHlit,  realHlit);
        //warn("HDIST = {} -> {}\n", rawHdist, realHdist);
        //warn("HCLEN = {} -> {}\n", rawHclen, realHclen);

        var clenTable: [15+4]u3 = [_]u3{0} ** (15+4);
        const clenRemap: [15+4]u5 = [_]u5{
            16, 17, 18, 0, 8,
            7, 9, 6, 10, 5, 11, 4, 12,
            3, 13, 2, 14, 1, 15,
        };

        // Parse the code length table
        {
            var i: u5 = 0;
            while ( i < realHclen ) : ( i += 1 ) {
                var k: u5 = clenRemap[i];
                var v: u3 = try stream.readType(u3);
                clenTable[k] = v;
                //warn("clen {} = {}\n", k, v);
            }
        }

        // Build a canonical huffman tree
        var clenTree = CanonicalHuffmanTree(u3, u5, 15+4).fromLengths(&clenTable);

        // Read literal tree
        var litTable: [31+257]u4 = [_]u4{0} ** (31+257);
        {
            var i: u9 = 0;
            var prev: u4 = undefined;
            while ( i < realHlit ) {
                var v: u5 = try clenTree.readFrom(stream);
                //warn("hlit {} = {}\n", i, v);

                switch ( v ) {
                    // Copy previous 3+u2 times
                    16 => {
                        // Can't copy a previous value if it's not there
                        if ( i < 1 ) { return error.Failed; }
                        var times: usize = 3 + usize(try stream.readType(u2));
                        var j: usize = 0;
                        while ( j < times ) : ( j += 1 ) {
                            litTable[i] = prev;
                            i += 1;
                        }
                    },

                    // Repeat 0 for 3+u3 times
                    17 => {
                        var times: usize = 3 + usize(try stream.readType(u3));
                        var j: usize = 0;
                        while ( j < times ) : ( j += 1 ) {
                            litTable[i] = 0;
                            i += 1;
                        }
                    },

                    // Repeat 0 for 11+u7 times
                    18 => {
                        var times: usize = 11 + usize(try stream.readType(u7));
                        var j: usize = 0;
                        while ( j < times ) : ( j += 1 ) {
                            litTable[i] = 0;
                            i += 1;
                        }
                    },

                    else => {
                        prev = @intCast(u4, v);
                        litTable[i] = prev;
                        i += 1;
                    },
                }
            }
        }

        // Build another canonical huffman tree
        var litTree = CanonicalHuffmanTree(u4, u9, 31+257).fromLengths(&litTable);

        // TODO: NOT COPY-PASTE THE ABOVE

        // Read distance tree
        var distTable: [31+1]u4 = [_]u4{0} ** (31+1);
        {
            var i: u6 = 0;
            var prev: u4 = undefined;
            while ( i < realHdist ) {
                var v: u5 = try clenTree.readFrom(stream);
                //warn("hdist {} = {}\n", i, v);

                switch ( v ) {
                    // Copy previous 3+u2 times
                    16 => {
                        // Can't copy a previous value if it's not there
                        if ( i < 1 ) { return error.Failed; }
                        var times: usize = 3 + usize(try stream.readType(u2));
                        var j: usize = 0;
                        while ( j < times ) : ( j += 1 ) {
                            distTable[i] = prev;
                            i += 1;
                        }
                    },

                    // Repeat 0 for 3+u3 times
                    17 => {
                        var times: usize = 3 + usize(try stream.readType(u3));
                        var j: usize = 0;
                        while ( j < times ) : ( j += 1 ) {
                            distTable[i] = 0;
                            i += 1;
                        }
                    },

                    // Repeat 0 for 11+u7 times
                    18 => {
                        var times: usize = 11 + usize(try stream.readType(u7));
                        var j: usize = 0;
                        while ( j < times ) : ( j += 1 ) {
                            distTable[i] = 0;
                            i += 1;
                        }
                    },

                    else => {
                        prev = @intCast(u4, v);
                        distTable[i] = prev;
                        i += 1;
                    },
                }
            }
        }

        // Build another canonical huffman tree
        var distTree = CanonicalHuffmanTree(u4, u5, 31+1).fromLengths(&distTable);

        return BlockTree {
            .litTree = litTree,
            .distTree = distTree,
        };
    }

    pub fn readLitFrom(self: *Self, stream: *InputBitStream) !u9 {
        return try self.litTree.readFrom(stream);
    }

    pub fn readDistFrom(self: *Self, stream: *InputBitStream) !u5 {
        return try self.distTree.readFrom(stream);
    }
};

