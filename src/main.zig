// vim: set sts=4 sw=4 et :
const std = @import("std");
const warn = std.debug.warn;
const BitInStream = std.io.BitInStream;
const File = std.fs.File;
const cwd = std.fs.cwd;
const allocator = std.heap.page_allocator;

const CanonicalHuffmanTree = @import("./huffman.zig").CanonicalHuffmanTree;
const GZipReader = @import("./gzip.zig").GZipReader;
const InputBitStream = @import("./bitstream.zig").InputBitStream;

var block_buf = [_]u8{0} ** 10240;

pub fn main() anyerror!void {
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    for (args) |arg, i| {
        if ( i >= 1 ) {
            warn("arg {} = '{}'\n", .{i, arg});

            var readRawStream = try cwd().openFile(arg, .{});
            defer readRawStream.close();
            var readBitStream = InputBitStream.init(readRawStream.inStream());
            var gzip = try GZipReader.readFromBitStream(&readBitStream);

            var total_bytes_read: usize = 0;
            while ( true ) {
                var bytes_read = try gzip.read(&block_buf);
                if ( bytes_read == 0 ) {
                    break;
                } else {
                    total_bytes_read += @intCast(usize, bytes_read);
                    warn("read {} bytes for a total of {} bytes\n", .{bytes_read, total_bytes_read});
                    //warn("contents: [{}]\n", .{block_buf[0..bytes_read]});
                }
            }
        }
    }
}
