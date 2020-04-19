// vim: set sts=4 sw=4 et :
const std = @import("std");
const Crc32 = std.hash.Crc32;
const warn = std.debug.warn;

const InputBitStream = @import("./bitstream.zig").InputBitStream;
const RawDeflateReader = @import("./raw_deflate_reader.zig").RawDeflateReader;

pub const GZipReader = struct {
    const Self = @This();

    const crc32Table: [0x100]u32 = result: {
        @setEvalBranchQuota(0x1000*8+100);
        var table = [_]u32{0} ** 256;
        var i: usize = 0;
        while ( i < 0x100 ) : ( i += 1 ) {
            var v: u32 = @intCast(u32, i);
            var j: usize = 0;
            while ( j < 8 ) : ( j += 1 ) {
                if ( (v & 0x1) != 0 ) {
                    v = (0xEDB88320 ^ (v>>1));
                } else {
                    v >>= 1;
                }
            }
            table[i] = v;
        }
        break :result table;
    };
    crc: Crc32 = Crc32.init(),
    bytes_accumulated: usize = 0,
    did_read_footer: bool = false,

    raw_deflate_reader: RawDeflateReader,
    read_stream: *InputBitStream,

    pub fn readFromBitStream(read_stream: *InputBitStream) !Self {
        // TODO: Actually read stuff from the header

        try Self.readGZipHeader(read_stream);

        var raw_deflate_reader = RawDeflateReader.readFromBitStream(read_stream);

        var self = Self {
            .raw_deflate_reader = raw_deflate_reader,
            .read_stream = read_stream,
        };

        return self;
    }

    fn readGZipHeader(read_stream: var) !void {
        // GZip fields are in Little-Endian.
        // FTEXT: File is probably ASCII text (not relevant)
        const FTEXT    = 0x01;
        // FHCRC: File has a 16-bit header CRC
        // (2 LSBs of 32-bit CRC up to but excluding the compressed data)
        const FHCRC    = 0x02;
        // FEXTRA: File has extra fields
        const FEXTRA   = 0x04;
        // FNAME: File has an original filename in ISO 8859-1 (LATIN-1) encoding
        const FNAME    = 0x08;
        // FCOMMENT: File has a comment
        const FCOMMENT = 0x10;
        // And these are the flags which are valid.
        const VALID_FLAGS = FTEXT|FHCRC|FEXTRA|FNAME|FCOMMENT;

        // GZip header magic number
        var magic0: u8 = try read_stream.readBitsNoEof(u8, 8);
        var magic1: u8 = try read_stream.readBitsNoEof(u8, 8);
        var magic2: u8 = try read_stream.readBitsNoEof(u8, 8);
        if ( magic0 != 0x1F ) { return error.Failed; }
        if ( magic1 != 0x8B ) { return error.Failed; }

        // Compression method: 0x08 = deflate
        if ( magic2 != 0x08 ) { return error.Failed; }

        // Flags
        const flags: u8 = try read_stream.readBitsNoEof(u8, 8);

        // Modification time
        const mtime: u32 = try read_stream.readBitsNoEof(u32, 32);

        // eXtra FLags
        const xfl: u8 = try read_stream.readBitsNoEof(u8, 8);

        // Operating System used
        const gzip_os: u8 = try read_stream.readBitsNoEof(u8, 8);

        // FEXTRA if present
        if ( (flags & FEXTRA) != 0 ) {
            // TODO: Parse if relevant
            var fextra_len: u16 = try read_stream.readBitsNoEof(u16, 16);
            var i: usize = 0;
            while ( i < fextra_len ) : ( i += 1 ) {
                _ = try read_stream.readBitsNoEof(u8, 8);
            }
        }

        // FNAME if present
        if ( (flags & FNAME) != 0 ) {
            var fname_buf = [_]u8{0} ** 1;
            warn("original file name: \"", .{});
            // Skip until NUL
            while ( true ) {
                fname_buf[0] = try read_stream.readBitsNoEof(u8, 8);
                if ( fname_buf[0] == 0 ) { break; }
                warn("{}", .{fname_buf[0..1]});
            }
            warn("\"\n", .{});
        }

        // FCOMMENT if present
        if ( (flags & FCOMMENT) != 0 ) {
            var fcomment_buf = [_]u8{0} ** 1;
            // Skip until NUL
            while ( true ) {
                fcomment_buf[0] = try read_stream.readBitsNoEof(u8, 8);
                if ( fcomment_buf[0] == 0 ) { break; }
            }
        }

        // FHCRC if present
        if ( (flags & FHCRC) != 0 ) {
            warn("Has 16-bit header CRC\n", .{});
            _ = try read_stream.readBitsNoEof(u16, 16);
        }
    }

    pub fn read(self: *Self, buffer: []u8) !usize {
        // Read the data
        var bytes_just_read = try self.raw_deflate_reader.read(buffer);

        // Process CRC32
        self.crc.update(buffer[0..bytes_just_read]);

        // Process byte count
        self.bytes_accumulated += bytes_just_read;

        // If we hit stream EOF, read the CRC32 and ISIZE fields
        if ( bytes_just_read == 0 ) {
            if ( !self.did_read_footer ) {
                self.did_read_footer = true;
                self.read_stream.alignToByte();
                var crc_finished: u32 = self.crc.final();
                var crc_expected: u32 = try self.read_stream.readBitsNoEof(u32, 32);
                var bytes_expected: u32 = try self.read_stream.readBitsNoEof(u32, 32);

                if ( crc_finished != crc_expected ) {
                    warn("CRC mismatch: got {}, expected {}\n", .{crc_finished, crc_expected});
                    return error.Failed;
                }

                if ( self.bytes_accumulated != bytes_expected ) {
                    warn("Size mismatch: got {}, expected {}\n", .{self.bytes_accumulated, bytes_expected});
                    return error.Failed;
                }
            }
        }
        return bytes_just_read;
    }
};
