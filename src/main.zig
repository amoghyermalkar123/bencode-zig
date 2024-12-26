const std = @import("std");
const Allocator = std.mem.Allocator;

const Token = enum {
    int,
    string,
    dictionary,
    list,
};

const Lexeme = union(Token) {
    int: u64,
    string: []const u8,
    dictionary: void,
    list: void,
};

const ParserError = error{
    InvalidDictionary,
    InvalidInput,
};

pub fn main() !void {
    const torrent_file = "d4:name5:Alice3:agei25eel4:name3:Bob3:agei26ee";
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);

    defer arena.deinit();
    const allocator = arena.allocator();

    var list = std.ArrayList(Lexeme).init(allocator);
    defer list.deinit();

    var parser = try Parser.init(&list, torrent_file);
    try parser.parse(allocator);
}

const Parser = struct {
    lexemes: *std.ArrayList(Lexeme),
    cursor: u64 = 0,
    torrent: []const u8,

    const Self = @This();

    pub fn init(lex_al: *std.ArrayList(Lexeme), torrent: []const u8) !Self {
        return Self{
            .lexemes = lex_al,
            .torrent = torrent,
        };
    }

    pub fn parse(self: *Self, allocator: Allocator) !void {
        while (self.cursor < self.torrent.len) {
            switch (self.torrent[self.cursor]) {
                'e' => break,
                // parse dictionary
                'd' => try self.parse_dict(allocator),
                // parse list
                'l' => try self.parse_list(allocator),
                // parse string
                '1'...'9' => try self.parse_string(allocator),
                // parse integer
                'i' => try self.parse_int(allocator),
                // panic
                else => return ParserError.InvalidInput,
            }
        }
    }

    fn parse_list(self: *Self, allocator: Allocator) anyerror!void {
        // ignore the first 'l'
        self.cursor += 1;
        try self.lexemes.append(Lexeme.list);
        while (self.cursor < self.torrent.len) {
            switch (self.torrent[self.cursor]) {
                'e' => {
                    self.cursor += 1;
                    break;
                },
                'd' => try self.parse_dict(allocator),
                'l' => try self.parse_list(allocator),
                'i' => try self.parse_int(allocator),
                '1'...'9' => try self.parse_string(allocator),
                else => break,
            }
        }
        try self.lexemes.append(Lexeme.list);
    }

    fn parse_dict(self: *Self, allocator: Allocator) anyerror!void {
        // ignore the first 'd'
        self.cursor += 1;
        try self.lexemes.append(Lexeme.dictionary);
        while (self.cursor < self.torrent.len) {
            switch (self.torrent[self.cursor]) {
                'e' => {
                    self.cursor += 1;
                    break;
                },
                'd' => try self.parse_dict(allocator),
                'l' => try self.parse_list(allocator),
                'i' => try self.parse_int(allocator),
                '1'...'9' => try self.parse_string(allocator),
                else => break,
            }
        }
        try self.lexemes.append(Lexeme.dictionary);
    }

    fn parse_int(self: *Self, allocator: Allocator) !void {
        var buf = std.ArrayList(u8).init(allocator);
        defer buf.deinit();

        const parsedInt = try self.retrieve_bencode_integer(&buf);
        try self.lexemes.append(Lexeme{ .int = parsedInt });
    }

    fn parse_string(self: *Self, allocator: Allocator) !void {
        var buf = std.ArrayList(u8).init(allocator);
        defer buf.deinit();
        const string_length = try self.retrieve_bencode_string_length(&buf);
        try self.lexemes.append(Lexeme{ .string = self.torrent[self.cursor .. self.cursor + string_length] });
        self.cursor += string_length;
    }

    fn retrieve_bencode_integer(self: *Self, buf: *std.ArrayList(u8)) !u64 {
        while (self.cursor < self.torrent.len) {
            switch (self.torrent[self.cursor]) {
                'e' => {
                    self.cursor += 1;
                    break;
                },
                'i' => self.cursor += 1,
                '1'...'9' => {
                    try buf.append(self.torrent[self.cursor]);
                    self.cursor += 1;
                },
                else => break,
            }
        }
        const parsedInt = try std.fmt.parseInt(u64, buf.items, 10);
        return parsedInt;
    }

    fn retrieve_bencode_string_length(self: *Self, buf: *std.ArrayList(u8)) !u64 {
        while (self.cursor < self.torrent.len) {
            switch (self.torrent[self.cursor]) {
                '1'...'9' => try buf.append(self.torrent[self.cursor]),
                ':' => {
                    self.cursor += 1;
                    break;
                },
                else => break,
            }
            self.cursor += 1;
        }
        const length = try std.fmt.parseInt(u64, buf.items, 10);
        return length;
    }
};

const testing = std.testing;

test "parse empty dictionary" {
    const input = "de";
    var list = std.ArrayList(Lexeme).init(testing.allocator);
    defer list.deinit();

    var parser = try Parser.init(&list, input);
    try parser.parse(testing.allocator);

    try testing.expectEqual(@as(usize, 2), list.items.len);
    try testing.expect(list.items[0] == .dictionary);
    try testing.expect(list.items[1] == .dictionary);
}

test "parse simple string" {
    const input = "4:test";
    var list = std.ArrayList(Lexeme).init(testing.allocator);
    defer list.deinit();

    var parser = try Parser.init(&list, input);
    try parser.parse(testing.allocator);

    try testing.expectEqual(@as(usize, 1), list.items.len);
    try testing.expect(list.items[0] == .string);
    try testing.expectEqualStrings("test", list.items[0].string);
}

test "parse integer" {
    const input = "i42e";
    var list = std.ArrayList(Lexeme).init(testing.allocator);
    defer list.deinit();

    var parser = try Parser.init(&list, input);
    try parser.parse(testing.allocator);

    try testing.expectEqual(@as(usize, 1), list.items.len);
    try testing.expect(list.items[0] == .int);
    try testing.expectEqual(@as(u64, 42), list.items[0].int);
}

test "parse empty list" {
    const input = "le";
    var list = std.ArrayList(Lexeme).init(testing.allocator);
    defer list.deinit();

    var parser = try Parser.init(&list, input);
    try parser.parse(testing.allocator);

    try testing.expectEqual(@as(usize, 2), list.items.len);
    try testing.expect(list.items[0] == .list);
    try testing.expect(list.items[1] == .list);
}

test "parse complex nested structure" {
    const input = "d4:listl3:one3:twoe4:dictd3:key5:valueee";
    var list = std.ArrayList(Lexeme).init(testing.allocator);
    defer list.deinit();

    var parser = try Parser.init(&list, input);
    try parser.parse(testing.allocator);

    try testing.expectEqual(@as(usize, 12), list.items.len);
    try testing.expect(list.items[0] == .dictionary);
    try testing.expectEqualStrings("list", list.items[1].string);
    try testing.expect(list.items[2] == .list);
    try testing.expectEqualStrings("one", list.items[3].string);
    try testing.expectEqualStrings("two", list.items[4].string);
    try testing.expect(list.items[5] == .list);
}

test "invalid input handling" {
    const input = "x";
    var list = std.ArrayList(Lexeme).init(testing.allocator);
    defer list.deinit();

    var parser = try Parser.init(&list, input);
    try testing.expectError(ParserError.InvalidInput, parser.parse(testing.allocator));
}

test "parse your example" {
    const input = "d4:name5:Alice3:agei25eel4:name3:Bob3:agei26ee";
    var list = std.ArrayList(Lexeme).init(testing.allocator);
    defer list.deinit();

    var parser = try Parser.init(&list, input);
    try parser.parse(testing.allocator);

    try testing.expectEqual(@as(usize, 12), list.items.len);
}
