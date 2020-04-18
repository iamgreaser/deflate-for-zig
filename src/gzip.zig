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
    bytesAccumulated: usize = 0,
    didReadFooter: bool = false,

    rawDeflateReader: RawDeflateReader,
    readStream: *InputBitStream,

    pub fn readFromBitStream(readStream: *InputBitStream) !Self {
        // TODO: Actually read stuff from the header

        try Self.readGZipHeader(readStream);

        var rawDeflateReader = RawDeflateReader.readFromBitStream(readStream);

        var self = Self {
            .rawDeflateReader = rawDeflateReader,
            .readStream = readStream,
        };

        return self;
    }

    fn readGZipHeader(readStream: var) !void {
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
        var magic0: u8 = try readStream.readType(u8);
        var magic1: u8 = try readStream.readType(u8);
        var magic2: u8 = try readStream.readType(u8);
        if ( magic0 != 0x1F ) { return error.Failed; }
        if ( magic1 != 0x8B ) { return error.Failed; }

        // Compression method: 0x08 = deflate
        if ( magic2 != 0x08 ) { return error.Failed; }

        // Flags
        const flags: u8 = try readStream.readType(u8);

        // Modification time
        const mtime: u32 = try readStream.readType(u32);

        // eXtra FLags
        const xfl: u8 = try readStream.readType(u8);

        // Operating System used
        const gzip_os: u8 = try readStream.readType(u8);

        // FEXTRA if present
        if ( (flags & FEXTRA) != 0 ) {
            // TODO: Parse if relevant
            var fextra_len: u16 = try readStream.readType(u16);
            var i: usize = 0;
            while ( i < fextra_len ) : ( i += 1 ) {
                _ = try readStream.readType(u8);
            }
        }

        // FNAME if present
        if ( (flags & FNAME) != 0 ) {
            var fname_buf = [_]u8{0} ** 1;
            warn("original file name: \"", .{});
            // Skip until NUL
            while ( true ) {
                fname_buf[0] = try readStream.readType(u8);
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
                fcomment_buf[0] = try readStream.readType(u8);
                if ( fcomment_buf[0] == 0 ) { break; }
            }
        }

        // FHCRC if present
        if ( (flags & FHCRC) != 0 ) {
            warn("Has 16-bit header CRC\n", .{});
            _ = try readStream.readType(u16);
        }
    }

    pub fn read(self: *Self, buffer: []u8) !usize {
        // Read the data
        var bytesJustRead = try self.rawDeflateReader.read(buffer);

        // Process CRC32
        self.crc.update(buffer[0..bytesJustRead]);

        // Process byte count
        self.bytesAccumulated += bytesJustRead;

        // If we hit stream EOF, read the CRC32 and ISIZE fields
        if ( bytesJustRead == 0 ) {
            if ( !self.didReadFooter ) {
                self.didReadFooter = true;
                try self.readStream.alignToByte();
                var crcFinished: u32 = self.crc.final();
                var crcExpected: u32 = try self.readStream.readType(u32);
                var bytesExpected: u32 = try self.readStream.readType(u32);

                if ( crcFinished != crcExpected ) {
                    warn("CRC mismatch: got {}, expected {}\n", .{crcFinished, crcExpected});
                    return error.Failed;
                }

                if ( self.bytesAccumulated != bytesExpected ) {
                    warn("Size mismatch: got {}, expected {}\n", .{self.bytesAccumulated, bytesExpected});
                    return error.Failed;
                }
            }
        }
        return bytesJustRead;
    }
};
