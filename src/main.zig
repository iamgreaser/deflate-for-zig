// vim: set sts=4 sw=4 et :
const std = @import("std");
const warn = std.debug.warn;
const BitInStream = std.io.BitInStream;
const Endian = std.builtin.Endian;
const File = std.fs.File;
const bufferedInStream = std.io.bufferedInStream;
const bufferedOutStream = std.io.bufferedOutStream;
const cwd = std.fs.cwd;

const CanonicalHuffmanTree = @import("./huffman.zig").CanonicalHuffmanTree;
const gzipInStream = @import("./gzip.zig").gzipInStream;

pub fn main() anyerror!void {
    // Input stream
    const read_raw_file = std.io.getStdIn();
    //defer read_raw_file.close();
    const read_raw_stream = read_raw_file.inStream();
    var read_buffered = bufferedInStream(read_raw_stream);
    const read_buffered_stream = read_buffered.inStream();
    var gzip = gzipInStream(read_buffered_stream);
    _ = try gzip.readHeader();

    // Output stream
    const write_raw_file = std.io.getStdOut();
    //defer write_raw_file.close();
    const write_raw_stream = write_raw_file.outStream();
    var write_buffered_stream = bufferedOutStream(write_raw_stream);
    defer {
        write_buffered_stream.flush() catch |err| {};
    }

    var total_bytes_read: usize = 0;
    while (true) {
        var block_buf = [_]u8{0} ** 4096;
        var bytes_read = try gzip.read(&block_buf);
        if (bytes_read == 0) {
            break;
        } else {
            total_bytes_read += bytes_read;
            var bytes_written = try write_buffered_stream.write(block_buf[0..bytes_read]);
            if (bytes_written != bytes_read) {
                return error.Failed;
            }
            //warn("read {} bytes for a total of {} bytes\n", .{ bytes_read, total_bytes_read });
            //warn("contents: [{}]\n", .{block_buf[0..bytes_read]});
        }
    }
}
