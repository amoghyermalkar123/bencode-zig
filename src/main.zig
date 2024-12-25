const std = @import("std");
const Allocator = std.mem.Allocator;

pub fn main() !void {
    const torrent_file = "d4:name5:Alice3:agei25eel4:name3:Bob3:agei26ee";
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const allocator = arena.allocator();

    try parse_torrent(allocator, torrent_file);
}

const Vals = enum {
    int,
    string,
};

const Token = union(Vals) {
    int: u64,
    string: []const u8,
};

const ParseError = error{
    InvalidDictionary,
};

pub fn parse_torrent(allocator: Allocator, torrent: []const u8) !void {
    var cursor: u64 = 0;

    while (cursor < torrent.len) {
        switch (torrent[cursor]) {
            'e' => break,
            'd' => {
                var kv = std.StringHashMap(Token).init(allocator);
                cursor += try parse_dict(allocator, &kv, torrent);
            },
            'l' => {
                var list = std.ArrayList(Token).init(allocator);
                defer list.deinit();
                cursor += try parse_list(allocator, &list, torrent);
            },
            '1'...'9' => {
                var list = std.ArrayList(Token).init(allocator);
                defer list.deinit();
                cursor += try parse_string(allocator, &list, torrent[cursor..]);
            },
            'i' => {
                var list = std.ArrayList(Token).init(allocator);
                defer list.deinit();
                cursor += try parse_integer(allocator, &list, torrent[cursor..]);
            },
            else => {
                std.debug.print("invalid char {c} encountered, exiting program.", .{torrent[cursor]});
                break;
            },
        }
    }
}

pub fn parse_dict(allocator: Allocator, kv: *std.StringHashMap(Token), torrent: []const u8) !usize {
    var parsed_token_list = std.ArrayList(Token).init(allocator);
    defer parsed_token_list.deinit();

    // ignore 'd'
    var cursor: u64 = 1;
    while (cursor < torrent.len) {
        switch (torrent[cursor]) {
            'e' => {
                cursor += 1;
                break;
            },
            '1'...'9' => {
                cursor += try parse_string(allocator, &parsed_token_list, torrent[cursor..]);
            },
            'i' => {
                cursor += try parse_integer(allocator, &parsed_token_list, torrent[cursor..]);
            },
            else => {
                std.debug.print("encountered weird {c}", .{torrent[cursor]});
                break;
            },
        }
    }

    if (parsed_token_list.items.len % 2 != 0) return ParseError.InvalidDictionary;
    if (parsed_token_list.items.len == 0) return ParseError.InvalidDictionary;

    var idx: u64 = 0;
    while (idx < parsed_token_list.items.len) : (idx += 2) {
        var ownedString = try parsed_token_list.toOwnedSlice();
        try kv.put(ownedString, parsed_token_list.items[idx + 1]);
    }
    return cursor;
}

pub fn parse_list(allocator: Allocator, list: *std.ArrayList(Token), torrent: []const u8) !usize {
    // ignore 'l'
    var cursor: u64 = 1;
    while (cursor < torrent.len) {
        switch (torrent[cursor]) {
            'e' => break,
            '1'...'9' => {
                cursor += try parse_string(allocator, list, torrent[cursor..]);
            },
            'i' => {
                cursor += try parse_integer(allocator, list, torrent[cursor..]);
            },
            else => {
                std.debug.print("encountered weird {c}", .{torrent[cursor]});
                break;
            },
        }
    }
    return cursor;
}

pub fn parse_integer(allocator: Allocator, token_list: *std.ArrayList(Token), torrent: []const u8) !usize {
    var l = std.ArrayList(u8).init(allocator);
    defer l.deinit();

    var cursor: u64 = 0;
    for (torrent) |byte| {
        switch (byte) {
            'e' => break,
            'i' => cursor += 1,
            '1'...'9' => try l.append(byte),
            else => break,
        }
        cursor += 1;
    }
    const parsedInt = try std.fmt.parseInt(u64, l.items, 10);
    try token_list.append(Token{ .int = parsedInt });
    return cursor;
}

pub fn parse_string(allocator: Allocator, token_list: *std.ArrayList(Token), torrent: []const u8) !usize {
    var l = std.ArrayList(u8).init(allocator);
    defer l.deinit();

    var cursor: u64 = 0;
    for (torrent) |byte| {
        switch (byte) {
            '1'...'9' => {
                try l.append(byte);
            },
            ':' => {
                cursor += 1;
                break;
            },
            else => break,
        }
        cursor += 1;
    }
    const length = try std.fmt.parseInt(u64, l.items, 10);
    const buf = torrent[cursor .. cursor + length];
    try token_list.append(Token{ .string = buf });
    return cursor + length;
}

const testing = std.testing;

test "parse integer basic" {
    const input = "i25e";
    var list = std.ArrayList(Token).init(testing.allocator);
    defer list.deinit();

    const cursor = try parse_integer(testing.allocator, &list, input);
    try testing.expectEqual(@as(u64, 25), list.items[0].int);
    try testing.expectEqual(@as(usize, 4), cursor);
}

test "parse string basic" {
    const input = "5:hello";
    var list = std.ArrayList(Token).init(testing.allocator);
    defer list.deinit();

    const cursor = try parse_string(testing.allocator, &list, input);
    try testing.expectEqualSlices(u8, list.items[0].string, "hello");
    try testing.expectEqual(@as(usize, 7), cursor);
}

test "parse list basic" {
    const input = "l5:helloi25ee";
    var list = std.ArrayList(Token).init(testing.allocator);
    defer list.deinit();

    const cursor = try parse_list(testing.allocator, &list, input);
    try testing.expectEqual(@as(usize, 2), list.items.len);
    try testing.expectEqualSlices(u8, list.items[0].string, "hello");
    try testing.expectEqual(@as(u64, 25), list.items[1].int);
    try testing.expectEqual(@as(usize, 12), cursor);
}

test "parse dictionary basic" {
    const input = "d4:name5:Alice3:agei25ee";
    var dict = std.StringHashMap(Token).init(testing.allocator);
    defer dict.deinit();

    const cursor = try parse_dict(testing.allocator, &dict, input);
    try testing.expectEqual(@as(usize, 2), dict.count());

    if (dict.get("name")) |name| {
        try testing.expectEqualSlices(u8, name.string, "Alice");
    } else {
        return error.TestUnexpectedNull;
    }

    if (dict.get("age")) |age| {
        try testing.expectEqual(@as(u64, 25), age.int);
    } else {
        return error.TestUnexpectedNull;
    }

    try testing.expectEqual(@as(usize, 24), cursor);
}

test "parse complete torrent" {
    const input = "d4:name5:Alice3:agei25eel4:name3:Bob3:agei26ee";
    try parse_torrent(testing.allocator, input);
}

test "invalid dictionary" {
    const input = "d4:name5:Alice3:agee"; // Missing value for age
    var dict = std.StringHashMap(Token).init(testing.allocator);
    defer dict.deinit();

    try testing.expectError(error.InvalidDictionary, parse_dict(testing.allocator, &dict, input));
}

test "parse string with large length" {
    const input = "10:helloworld";
    var list = std.ArrayList(Token).init(testing.allocator);
    defer list.deinit();

    const cursor = try parse_string(testing.allocator, &list, input);
    try testing.expectEqualSlices(u8, list.items[0].string, "helloworld");
    try testing.expectEqual(@as(usize, 12), cursor);
}
