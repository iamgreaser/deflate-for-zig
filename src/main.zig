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
const GZipReader = @import("./gzip.zig").GZipReader;

pub fn main() anyerror!void {
    var block_buf = [_]u8{0} ** 4096;

    // Input stream
    var read_raw_file = std.io.getStdIn();
    //defer read_raw_file.close();
    var read_raw_stream = read_raw_file.inStream();
    var read_buffered = bufferedInStream(read_raw_stream);
    var read_buffered_stream = read_buffered.inStream();
    var gzip = try GZipReader(@TypeOf(read_buffered_stream)).init(read_buffered_stream);
    //var gzip = try GZipReader(File.InStream).init(read_raw_stream);

    // Output stream
    var write_raw_file = std.io.getStdOut();
    //defer write_raw_file.close();
    var write_raw_stream = write_raw_file.outStream();
    var write_buffered_stream = bufferedOutStream(write_raw_stream);
    defer {
        write_buffered_stream.flush() catch |err| {};
    }

    var total_bytes_read: usize = 0;
    while (true) {
        var bytes_read = try gzip.read(&block_buf);
        if (bytes_read == 0) {
            break;
        } else {
            total_bytes_read += @intCast(usize, bytes_read);
            var bytes_written = try write_buffered_stream.write(block_buf[0..bytes_read]);
            if (bytes_written != bytes_read) {
                return error.Failed;
            }
            //warn("read {} bytes for a total of {} bytes\n", .{ bytes_read, total_bytes_read });
            //warn("contents: [{}]\n", .{block_buf[0..bytes_read]});
        }
    }
}
