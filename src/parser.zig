const Token = @import("tokenizer.zig").Token;
const std = @import("std");
const Allocator = std.mem.Allocator;
const Tokenizer = @import("tokenizer.zig").Tokenizer;

pub const Torrent = struct {
    // main allocator
    allocator: Allocator,

    // Metadata hash (not encoded in file, computed from info dict)
    info_hash: []u8 = undefined, // Fixed-size array for SHA1 hash

    // Required fields
    announce: []const u8 = undefined, // Main tracker URL as string slice

    // Optional metadata (marked with ?)
    announce_list: ?[][]const u8 = null, // Optional list of backup trackers
    creation_date: ?i64 = null, // Optional unix timestamp
    comment: ?[]const u8 = null, // Optional comment
    created_by: ?[]const u8 = null, // Optional creator info
    encoding: ?[]const u8 = null, // Optional character encoding

    // The main info dictionary (required)
    info: Info = undefined,

    // Nested Info dictionary type
    pub const Info = struct {
        // allocators
        allocator: Allocator,
        // Required info fields
        piece_length: u32 = 0, // Size of each piece
        pieces: []const u8 = undefined, // Concatenated SHA1 hashes
        name: []const u8 = undefined, // Suggested save name

        // Optional info fields
        private: ?bool = null,

        // Single-file mode fields (optional)
        length: ?u64 = null, // File size
        md5sum: ?[]const u8 = null, // Optional hash

        files: *std.ArrayList(FileEntry),

        // File entry type for multi-file torrents
        pub const FileEntry = struct {
            length: u64, // Size of file
            path: []const u8 = undefined, // File path
            md5sum: ?[]const u8 = null, // Optional hash
        };

        pub fn init(allocator: Allocator, list: *std.ArrayList(FileEntry)) Info {
            return .{
                .allocator = allocator,
                .files = list,
            };
        }

        pub fn deinit(self: *Info) void {
            // Don't free piece_length (it's a primitive u32)

            if (self.pieces.len > 0) {
                self.allocator.free(self.pieces);
            }

            if (self.name.len > 0) {
                self.allocator.free(self.name);
            }

            // Handle optional fields
            if (self.md5sum) |md5| {
                self.allocator.free(md5);
            }

            self.files.deinit();
        }
    };

    const Self = @This();

    pub fn init(allocator: Allocator, list: *std.ArrayList(Self.Info.FileEntry)) Self {
        return .{
            .allocator = allocator,
            .info = Info.init(allocator, list),
        };
    }

    pub fn deinit(self: *Self) void {
        // Handle required fields
        if (self.announce.len > 0) {
            self.allocator.free(self.announce);
        }

        // Handle optional fields
        if (self.announce_list) |list| {
            for (list) |urls| {
                self.allocator.free(urls);
            }
            self.allocator.free(list);
        }

        // Don't free creation_date since it's a primitive type (i64)

        if (self.comment) |comm| {
            self.allocator.free(comm);
        }

        if (self.created_by) |creator| {
            self.allocator.free(creator);
        }

        if (self.encoding) |enc| {
            self.allocator.free(enc);
        }

        // Handle info struct
        self.info.deinit();
    }

    fn print(self: *Self) void {
        std.debug.print("announce: {s}\n", .{self.announce});
        std.debug.print("info- name: {s}\n", .{self.info.name});
        std.debug.print("info- pieces: {s}\n", .{self.info.pieces});
        std.debug.print("info- pieces_len: {d}\n============", .{self.info.piece_length});
    }
};

pub const Parser = struct {
    allocator: std.mem.Allocator,
    arena: std.heap.ArenaAllocator,
    current_token: ?Token = null,
    tokenizer: Tokenizer,
    torrent: [:0]u8,

    const Self = @This();

    pub const TorrentError = error{
        InvalidTorrent,
        EOF,
    };

    pub fn init(allocator: Allocator, torrent: [:0]u8) !Self {
        var arena = std.heap.ArenaAllocator.init(allocator);

        return .{
            .allocator = arena.allocator(),
            .arena = arena,
            .tokenizer = Tokenizer.init(torrent),
            .torrent = torrent,
        };
    }

    pub fn deinit(self: *Self) void {
        self.arena.deinit();
    }

    pub fn parse(self: *Self) !Torrent {
        self.current_token = try self.tokenizer.next();

        if (self.current_token.?.tag == .eof) return TorrentError.EOF;
        if (self.current_token.?.tag != .dict) return TorrentError.InvalidTorrent;

        var l = std.ArrayList(Torrent.Info.FileEntry).init(self.allocator);
        var result = Torrent.init(self.allocator, &l);

        try self.parseTopLevelTorrent(&result);
        return result;
    }

    pub fn parseTopLevelTorrent(self: *Self, result: *Torrent) !void {
        self.current_token = try self.tokenizer.next();
        const val = self.torrent[self.current_token.?.loc.start..self.current_token.?.loc.end];
        if (std.mem.eql(u8, val, "announce")) result.announce = try self.parseNextToken(result);
        if (std.mem.eql(u8, val, "info_hash")) result.info_hash = try self.parseNextToken(result);
        if (std.mem.eql(u8, val, "creation_date")) result.creation_date = try self.parseNextTokeni64();
        if (std.mem.eql(u8, val, "comment")) result.comment = try self.parseNextToken(result);
        if (std.mem.eql(u8, val, "created_by")) result.created_by = try self.parseNextToken(result);
        if (std.mem.eql(u8, val, "encoding")) result.encoding = try self.parseNextToken(result);
        if (std.mem.eql(u8, val, "info")) try self.parseInfoStruct(result);
    }

    pub fn parseInfoStruct(self: *Self, result: *Torrent) !void {
        self.current_token = try self.tokenizer.next();
        const val = self.torrent[self.current_token.?.loc.start..self.current_token.?.loc.end];
        if (std.mem.eql(u8, val, "piece_length")) result.info.piece_length = try self.parseNextTokenu32();
        if (std.mem.eql(u8, val, "pieces")) result.info.pieces = try self.parseNextToken(result);
        if (std.mem.eql(u8, val, "name")) result.info.name = try self.parseNextToken(result);
        // if (std.mem.eql(u8, val, "private")) result.comment = try self.parseNextToken(result);
        if (std.mem.eql(u8, val, "length")) result.info.length = try self.parseNextTokenu64();
        if (std.mem.eql(u8, val, "md5sum")) result.info.md5sum = try self.parseNextToken(result);
        if (std.mem.eql(u8, val, "files")) try self.parseFileEntry(result);
    }

    pub fn parseFileEntry(self: *Self, result: *Torrent) !void {
        self.current_token = try self.tokenizer.next();
        const val = self.torrent[self.current_token.?.loc.start..self.current_token.?.loc.end];
        while (true) {
            if (self.current_token.?.tag == .end) break;
            var fe: Torrent.Info.FileEntry = undefined;
            if (std.mem.eql(u8, val, "length")) fe.length = try self.parseNextTokenu64();
            if (std.mem.eql(u8, val, "path")) fe.path = try self.parseNextToken(result);
            if (std.mem.eql(u8, val, "md5sum")) fe.md5sum = try self.parseNextToken(result);
            try result.info.files.append(fe);
        }
    }

    pub fn parseNextToken(self: *Self, result: *Torrent) ![]u8 {
        self.current_token = try self.tokenizer.next();
        return try result.allocator.dupe(u8, self.torrent[self.current_token.?.loc.start..self.current_token.?.loc.end]);
    }

    pub fn parseNextTokeni64(self: *Self) !i64 {
        self.current_token = try self.tokenizer.next();
        return try std.fmt.parseInt(i64, self.torrent[self.current_token.?.loc.start..self.current_token.?.loc.end], 10);
    }

    pub fn parseNextTokenu32(self: *Self) !u32 {
        self.current_token = try self.tokenizer.next();
        return try std.fmt.parseInt(u32, self.torrent[self.current_token.?.loc.start..self.current_token.?.loc.end], 10);
    }

    pub fn parseNextTokenu64(self: *Self) !u64 {
        self.current_token = try self.tokenizer.next();
        return try std.fmt.parseInt(u64, self.torrent[self.current_token.?.loc.start..self.current_token.?.loc.end], 10);
    }
};

const testing = std.testing;

test "parse basic torrent" {
    const input_const =
        \\d8:announce37:udp://tracker.example.com:80/announce
        \\7:comment15:Sample Torrent!
        \\13:creation datei1704844800e
        \\4:infod
        \\6:lengthi1024e
        \\4:name10:sample.txt
        \\12:piece lengthi16384e
        \\6:pieces20:aabbccddeeffgghhiijj
        \\ee
    ;

    // Use testing.allocator for the input string
    const input = try testing.allocator.dupeZ(u8, input_const);
    defer testing.allocator.free(input);

    // Create a dedicated arena allocator for the parser
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    var parser = try Parser.init(arena.allocator(), input);
    // No need to defer parser.deinit() since arena handles cleanup

    const torrent = try parser.parse();
    // No need to defer torrent.deinit() since arena handles cleanup

    // Add null checks for optional fields
    try testing.expectEqualStrings("udp://tracker.example.com:80/announce", torrent.announce);
    try testing.expectEqualStrings("sample.txt", torrent.info.name);
    try testing.expectEqualStrings("Sample Torrent!", torrent.comment.?);
    try testing.expectEqual(@as(u32, 16384), torrent.info.piece_length);
    try testing.expectEqual(@as(u64, 1024), torrent.info.length.?);
    try testing.expectEqualStrings("aabbccddeeffgghhiijj", torrent.info.pieces);
}
