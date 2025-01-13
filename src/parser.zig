const Token = @import("tokenizer.zig").Token;
const std = @import("std");
const Allocator = std.mem.Allocator;
const Tokenizer = @import("tokenizer.zig").Tokenizer;

pub const Torrent = struct {
    // Metadata hash (not encoded in file, computed from info dict)
    info_hash: [20]u8, // Fixed-size array for SHA1 hash

    // Required fields
    announce: []const u8, // Main tracker URL as string slice

    // Optional metadata (marked with ?)
    announce_list: ?[][]const u8 = null, // Optional list of backup trackers
    creation_date: ?i64 = null, // Optional unix timestamp
    comment: ?[]const u8 = null, // Optional comment
    created_by: ?[]const u8 = null, // Optional creator info
    encoding: ?[]const u8 = null, // Optional character encoding

    // The main info dictionary (required)
    info: Info,

    // Nested Info dictionary type
    pub const Info = struct {
        // Required info fields
        piece_length: u32, // Size of each piece
        pieces: []const u8, // Concatenated SHA1 hashes
        name: []const u8, // Suggested save name

        // Optional info fields
        private: ?bool = null,

        // Single-file mode fields (optional)
        length: ?u64 = null, // File size
        md5sum: ?[]const u8 = null, // Optional hash

        // Multi-file mode fields (optional)
        files: ?[]FileEntry = null, // List of files if multi-file

        // File entry type for multi-file torrents
        pub const FileEntry = struct {
            length: u64, // Size of file
            path: []const u8, // File path
            md5sum: ?[]const u8 = null, // Optional hash
        };
    };
};

pub fn parse(allocator: Allocator, torrent: []u8, t: *Tokenizer) !?Torrent {
    _ = torrent;
    var buf_list = std.ArrayList(Token).init(allocator);
    defer buf_list.deinit();

    var buf_dict = std.StringHashMap([]u8).init(allocator);
    defer buf_dict.deinit();

    var next = try t.next();
    while (true) {
        switch (next.tag) {
            .dict => {
                std.debug.print("dict not impl", .{});
            },
            .list => {
                std.debug.print("list not impl", .{});
            },
            .string => {
                std.debug.print("string not impl", .{});
            },
            .int => {
                std.debug.print("int not impl", .{});
            },
            .end => {
                std.debug.print("end not impl", .{});
            },
            .eof => {
                std.debug.print("finished!", .{});
                break;
            },
        }
        next = try t.next();
    }
    return null;
}
