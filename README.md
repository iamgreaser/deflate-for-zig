# Deflate implementation for Zig

This is an implementation of the Deflate compression algorithm as per RFC 1951, and the GZip container as per RFC 1952.

This is a work in progress.

Currently it:

* reads GZip files
* decompresses them to nowhere
* validates the contents against the CRC32 and uncompressed length inside the GZip footer