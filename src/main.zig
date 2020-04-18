// vim: set sts=4 sw=4 et :
const std = @import("std");
const warn = std.debug.warn;
const File = std.fs.File;
const allocator = std.heap.direct_allocator;

const CanonicalHuffmanTree = @import("./huffman.zig").CanonicalHuffmanTree;
const GZipReader = @import("./gzip.zig").GZipReader;
const InputBitStream = @import("./bitstream.zig").InputBitStream;

pub fn main() anyerror!void {
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    for (args) |arg, i| {
        if ( i >= 1 ) {
            warn("arg {} = '{}'\n", i, arg);

            var readRawStream = try File.openRead(arg);
            defer readRawStream.close();
            var readBitStream = InputBitStream.wrapStream(readRawStream);
            var gzip = try GZipReader.readFromBitStream(&readBitStream);

            var block_buf = [_]u8{0} ** 1024;
            var total_bytes_read: usize = 0;
            while ( true ) {
                var bytes_read = try gzip.read(&block_buf);
                if ( bytes_read == 0 ) {
                    break;
                } else {
                    total_bytes_read += usize(bytes_read);
                    warn("read {} bytes for a total of {} bytes\n", bytes_read, total_bytes_read);
                    warn("contents: [{}]\n", block_buf[0..bytes_read]);
                }
            }
        }
    }
}
