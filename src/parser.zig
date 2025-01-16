const Token = @import("tokenizer.zig").Token;
const std = @import("std");
const Allocator = std.mem.Allocator;
const Tokenizer = @import("tokenizer.zig").Tokenizer;

pub const Torrent = struct {
    // Metadata hash (not encoded in file, computed from info dict)
    info_hash: []u8, // Fixed-size array for SHA1 hash

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

pub const Parser = struct {
    allocator: std.mem.Allocator,
    current_token: ?Token = null,
    tokenizer: Tokenizer,
    torrent: [:0]u8,

    const Self = @This();

    pub const TorrentError = error{
        InvalidTorrent,
    };

    pub fn init(allocator: Allocator, torrent: [:0]u8) !Self {
        return .{
            .allocator = allocator,
            .tokenizer = Tokenizer.init(torrent),
            .torrent = torrent,
        };
    }

    pub fn deinit() !void {}

    pub fn parse(self: *Self) !?Torrent {
        self.current_token = try self.tokenizer.next();

        if (self.current_token.?.tag == .eof) return null;
        if (self.current_token.?.tag != .dict) {
            return TorrentError.InvalidTorrent;
        }

        var result: Torrent = undefined;

        try self.parseTopLevelTorrent(&result);
        return result;
    }

    pub fn parseTopLevelTorrent(self: *Self, result: *Torrent) !void {
        self.current_token = try self.tokenizer.next();
        const val = self.torrent[self.current_token.?.loc.start..self.current_token.?.loc.end];
        if (std.mem.eql(u8, val, "info_hash")) {
            result.info_hash = try self.allocator.dupe(u8, self.torrent[self.current_token.?.loc.start..self.current_token.?.loc.end]);
        }
    }
    // pub fn parseInfoStruct(self: *Self) !void {}
    // pub fn parseFileEntry(self: *Self) !void {}
};
