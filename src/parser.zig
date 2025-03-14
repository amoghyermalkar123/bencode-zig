const Token = @import("tokenizer.zig").Token;
const std = @import("std");
const Allocator = std.mem.Allocator;
const Tokenizer = @import("tokenizer.zig").Tokenizer;

pub const FileEntry = struct {
    length: u64,
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

    fn print(self: *Self) void {
        std.debug.print("announce: {s}\n", .{self.announce});
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

        const val = self.torrent[self.current_token.?.loc.start..self.current_token.?.loc.end];
        self.current_token = try self.tokenizer.next();

        // parsing the base dict
        if (std.mem.eql(u8, val, "announce")) result.announce = try self.parseNextToken();
        if (std.mem.eql(u8, val, "info_hash")) result.info_hash = try self.parseNextToken();
        if (std.mem.eql(u8, val, "creation_date")) result.creation_date = try self.parseNextTokeni64();
        if (std.mem.eql(u8, val, "comment")) result.comment = try self.parseNextToken();
        if (std.mem.eql(u8, val, "created_by")) result.created_by = try self.parseNextToken();
        if (std.mem.eql(u8, val, "encoding")) result.encoding = try self.parseNextToken();
        // parsing the info dict
        if (std.mem.eql(u8, val, "info")) result.info = Torrent.Info{};
        if (std.mem.eql(u8, val, "piece_length")) result.info.?.piece_length = try self.parseNextTokenu32();
        if (std.mem.eql(u8, val, "pieces")) result.info.?.pieces = try self.parseNextToken();
        if (std.mem.eql(u8, val, "name")) result.info.?.name = try self.parseNextToken();
        if (std.mem.eql(u8, val, "length")) result.info.?.length = try self.parseNextTokenu64();
        if (std.mem.eql(u8, val, "md5sum")) result.info.?.md5sum = try self.parseNextToken();
        // parsing the files dict
        if (std.mem.eql(u8, val, "files")) {}
    }

    pub fn parseFiles(self: *Self) !void {
        if (self.current_token.?.tag == .eof) return TorrentError.InvalidTorrent;
        // alloc files and own the slice here
        var al = std.ArrayList(Torrent.Info.FileEntry).init(self.allocator);

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
            }
        }
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
        \\d8:announce37:udp://tracker.example.com:80/announce7:comment15:Sample Torrent!13:creation datei1704844800e4:infod6:lengthi1024e4:name10:sample.txt12:piece lengthi16384e6:pieces20:aabbccddeeffgghhiijjee
    ;

    const input = try testing.allocator.dupeZ(u8, input_const);
    defer testing.allocator.free(input);

    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    var parser = try Parser.init(arena.allocator(), input);

    const torrent = try parser.parse();
    std.debug.print("announce: {s}\n", .{torrent.announce});
    std.debug.print("comment: {s}\n", .{torrent.comment.?});
    std.debug.print("info: {s}\n", .{torrent.info.?.name});
    std.debug.print("files: {d}\n", .{torrent.info.?.files.len});
}
