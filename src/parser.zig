const Token = @import("tokenizer.zig").Token;
const std = @import("std");
const Allocator = std.mem.Allocator;
const Tokenizer = @import("tokenizer.zig").Tokenizer;

pub const FileEntry = struct {
    length: u64 = 0,
    path: []const u8 = undefined,
    md5sum: ?[]const u8 = null,
};

pub const Torrent = struct {
    allocator: Allocator,
    info_hash: []u8 = undefined,
    announce: []const u8 = undefined,
    announce_list: ?[][]const u8 = null,
    creation_date: ?i64 = null,
    comment: ?[]const u8 = null,
    created_by: ?[]const u8 = null,
    encoding: ?[]const u8 = null,
    info: ?Info = null,

    pub const Info = struct {
        piece_length: u32 = 0,
        pieces: []const u8 = undefined,
        name: []const u8 = undefined,
        private: ?bool = null,
        length: ?u64 = null,
        md5sum: ?[]const u8 = null,
        files: []FileEntry = undefined,
    };

    const Self = @This();

    pub fn init(allocator: Allocator) Self {
        return .{
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        if (self.info) |info| {
            self.allocator.free(info.pieces);
            self.allocator.free(info.name);
            if (info.md5sum) |md5sum| {
                self.allocator.free(md5sum);
            }
            for (info.files) |file| {
                self.allocator.free(file.path);
                self.allocator.free(file.md5sum);
                self.allocator.free(file.length);
            }
            self.allocator.free(info.files);
        }
        self.allocator.free(self.info_hash);
        self.allocator.free(self.announce);
        if (self.announce_list) |announce_list| {
            for (announce_list) |announce| {
                self.allocator.free(announce);
            }
            self.allocator.free(announce_list);
        }
        if (self.comment) |comment| {
            self.allocator.free(comment);
        }
        if (self.created_by) |created_by| {
            self.allocator.free(created_by);
        }
        if (self.encoding) |encoding| {
            self.allocator.free(encoding);
        }
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

        var result = Torrent.init(self.allocator);

        while (true) {
            if (self.current_token.?.tag == .eof) break;
            try self.parseTorrent(&result);
        }
        return result;
    }

    pub fn parseTorrent(self: *Self, result: *Torrent) !void {
        self.current_token = try self.tokenizer.next();
        if (self.current_token.?.tag == .eof) return;

        const bencode_key = self.torrent[self.current_token.?.loc.start..self.current_token.?.loc.end];
        self.current_token = try self.tokenizer.next();

        // parsing the base dict
        if (std.mem.eql(u8, bencode_key, "announce")) {
            result.announce = try self.parseNextToken();
            return;
        }
        if (std.mem.eql(u8, bencode_key, "announce-list")) {
            result.announce_list = try self.parseAnnounceList();
            return;
        }
        if (std.mem.eql(u8, bencode_key, "info_hash")) {
            result.info_hash = try self.parseNextToken();
            return;
        }
        if (std.mem.eql(u8, bencode_key, "creation_date")) {
            result.creation_date = try self.parseNextTokeni64();
            return;
        }
        if (std.mem.eql(u8, bencode_key, "comment")) {
            result.comment = try self.parseNextToken();
            return;
        }
        if (std.mem.eql(u8, bencode_key, "created_by")) {
            result.created_by = try self.parseNextToken();
            return;
        }
        if (std.mem.eql(u8, bencode_key, "encoding")) {
            result.encoding = try self.parseNextToken();
            return;
        }
        // parsing the info dict
        if (std.mem.eql(u8, bencode_key, "info")) {
            result.info = Torrent.Info{};
            return;
        }
        if (std.mem.eql(u8, bencode_key, "piece_length")) {
            result.info.?.piece_length = try self.parseNextTokenu32();
            return;
        }
        if (std.mem.eql(u8, bencode_key, "pieces")) {
            result.info.?.pieces = try self.parseNextToken();
            return;
        }
        if (std.mem.eql(u8, bencode_key, "name")) {
            result.info.?.name = try self.parseNextToken();
            return;
        }
        if (std.mem.eql(u8, bencode_key, "length")) {
            result.info.?.length = try self.parseNextTokenu64();
            return;
        }
        if (std.mem.eql(u8, bencode_key, "md5sum")) {
            result.info.?.md5sum = try self.parseNextToken();
            return;
        }
        // parsing the files dict
        if (std.mem.eql(u8, bencode_key, "files")) result.info.?.files = try self.parseFiles();
    }

    pub fn parseAnnounceList(self: *Self) ![][]const u8 {
        if (self.current_token.?.tag == .eof) return TorrentError.InvalidTorrent;

        var al = std.ArrayList([]const u8).init(self.allocator);
        defer al.deinit();

        self.current_token = try self.tokenizer.next();
        while (self.current_token.?.tag == .end) {
            self.current_token = try self.tokenizer.next();
            try al.append(try self.parseNextToken());
        }

        return al.toOwnedSlice();
    }

    pub fn parseFiles(self: *Self) ![]FileEntry {
        if (self.current_token.?.tag == .eof) return TorrentError.InvalidTorrent;
        // alloc files and own the slice here
        var al = std.ArrayList(FileEntry).init(self.allocator);
        defer al.deinit();

        while ((self.current_token.?.tag == .end)) {
            while ((self.current_token.?.tag == .end)) {
                self.current_token = try self.tokenizer.next();

                var fe = FileEntry{};

                const val = self.torrent[self.current_token.?.loc.start..self.current_token.?.loc.end];
                self.current_token = try self.tokenizer.next();

                if (std.mem.eql(u8, val, "length")) fe.length = try self.parseNextTokenu64();
                if (std.mem.eql(u8, val, "md5sum")) fe.md5sum = try self.parseNextToken();
                if (std.mem.eql(u8, val, "path")) fe.path = try self.parseNextToken();

                try al.append(fe);
                std.debug.print("parsed file\n", .{});
            }
        }
        return try al.toOwnedSlice();
    }

    pub fn parseNextToken(self: *Self) ![]u8 {
        return try self.allocator.dupe(u8, self.torrent[self.current_token.?.loc.start..self.current_token.?.loc.end]);
    }

    pub fn parseNextTokeni64(self: *Self) !i64 {
        return try std.fmt.parseInt(i64, self.torrent[self.current_token.?.loc.start..self.current_token.?.loc.end], 10);
    }

    pub fn parseNextTokenu32(self: *Self) !u32 {
        return try std.fmt.parseInt(u32, self.torrent[self.current_token.?.loc.start..self.current_token.?.loc.end], 10);
    }

    pub fn parseNextTokenu64(self: *Self) !u64 {
        return try std.fmt.parseInt(u64, self.torrent[self.current_token.?.loc.start..self.current_token.?.loc.end], 10);
    }
};

const testing = std.testing;

test "parse basic torrent" {
    const input_const =
        \\d8:announce37:udp://tracker.example.com:80/announce7:comment15:Sample Torrent!13:creation datei1704844800e4:infod6:lengthi1024e4:name10:sample.txt12:piece_lengthi16384e6:pieces20:aabbccddeeffgghhiijjee
    ;

    const input = try testing.allocator.dupeZ(u8, input_const);
    defer testing.allocator.free(input);

    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    var parser = try Parser.init(arena.allocator(), input);

    const torrent = try parser.parse();
    try testing.expectEqualSlices(u8, "udp://tracker.example.com:80/announce", torrent.announce);
    try testing.expectEqualSlices(u8, "Sample Torrent!", torrent.comment.?);
    try testing.expectEqualSlices(u8, "sample.txt", torrent.info.?.name);
    try testing.expectEqual(@as(u64, 1024), torrent.info.?.length.?);
    try testing.expectEqual(@as(u32, 16384), torrent.info.?.piece_length);
}

test "parse torrent with nested dictionaries" {
    const input_const =
        \\d8:announce37:udp://tracker.example.com:80/announce4:infod6:lengthi4096e4:name10:nested.txt12:piece_lengthi65536e5:filesld6:lengthi1024e4:pathl9:file1.txteed6:lengthi2048e4:pathl9:file2.txteee6:pieces20:99887766554433221100ee
    ;

    const input = try testing.allocator.dupeZ(u8, input_const);
    defer testing.allocator.free(input);

    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    var parser = try Parser.init(arena.allocator(), input);

    const torrent = try parser.parse();
    try testing.expectEqualSlices(u8, "udp://tracker.example.com:80/announce", torrent.announce);
    try testing.expectEqualSlices(u8, "nested.txt", torrent.info.?.name);
    try testing.expectEqual(@as(u64, 4096), torrent.info.?.length.?);
    try testing.expectEqual(@as(u32, 65536), torrent.info.?.piece_length);
    try testing.expectEqual(@as(u64, 1024), torrent.info.?.files[0].length);
    try testing.expectEqualSlices(u8, "file1.txt", torrent.info.?.files[0].path);
    try testing.expectEqual(@as(u64, 2048), torrent.info.?.files[1].length);
    try testing.expectEqualSlices(u8, "file2.txt", torrent.info.?.files[1].path);
}

test "parse torrent with missing end marker" {
    const input_const =
        \\d8:announce37:udp://tracker.example.com:80/announce4:infod6:lengthi4096e4:name12:nested.txt12:piece lengthi65536e5:filesld6:lengthi1024e4:pathl8:file1.txteed6:lengthi2048e4:pathl8:file2.txteee6:pieces20:99887766554433221100e
    ;

    const input = try testing.allocator.dupeZ(u8, input_const);
    defer testing.allocator.free(input);

    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    var parser = try Parser.init(arena.allocator(), input);

    const result = parser.parse();
    try testing.expectError(Parser.TorrentError.InvalidTorrent, result);
}

test "parse torrent with invalid integer format" {
    const input_const =
        \\d8:announce37:udp://tracker.example.com:80/announce4:infod6:lengthi40.96e4:name12:invalid.txt12:piece lengthi65536e6:pieces20:99887766554433221100ee
    ;

    const input = try testing.allocator.dupeZ(u8, input_const);
    defer testing.allocator.free(input);

    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    var parser = try Parser.init(arena.allocator(), input);

    const result = parser.parse();
    try testing.expectError(Parser.TorrentError.InvalidTorrent, result);
}
