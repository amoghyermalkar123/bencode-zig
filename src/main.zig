const std = @import("std");
const Allocator = std.mem.Allocator;

pub fn main() !void {
    const torrent_file = "d4:name5:Alice3:agei25ee";
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const allocator = arena.allocator();

    var kv = std.StringHashMap(Token).init(allocator);
    _ = try parse_dict(allocator, &kv, torrent_file);

    var iter = kv.iterator();
    var item = iter.next();
    while (item != null) : (item = iter.next()) {
        const k = item.?.key_ptr.*;
        const v = item.?.value_ptr.*;
        switch (v) {
            .int => {
                std.debug.print("{s} : {d}\n", .{ k, v.int });
            },
            .string => {
                std.debug.print("{s} : {s}\n", .{ k, v.string });
            },
        }
    }
}

const Vals = enum {
    int,
    string,
};

const Token = union(Vals) {
    int: u64,
    string: []u8,
};

const ParseError = error{
    InvalidDictionary,
};

pub fn parse_dict(allocator: Allocator, kv: *std.StringHashMap(Token), torrent: []const u8) !usize {
    var parsed_token_list = std.ArrayList(Token).init(allocator);
    defer parsed_token_list.deinit();

    // ignore 'd'
    var cursor: u64 = 1;
    while (cursor < torrent.len) {
        switch (torrent[cursor]) {
            'e' => break,
            '1'...'9' => {
                var l = std.ArrayList(u8).init(allocator);
                defer l.deinit();
                cursor += try parse_string(&l, torrent[cursor..]);
                const buf = try l.toOwnedSlice();
                try parsed_token_list.append(Token{ .string = buf });
            },
            'i' => {
                var parsed_int: u64 = 0;
                var l = std.ArrayList(u8).init(allocator);
                defer l.deinit();
                cursor += try parse_integer(&l, &parsed_int, torrent[cursor..]);
                std.debug.assert(parsed_int != 0);
                try parsed_token_list.append(Token{ .int = parsed_int });
            },
            else => {
                std.debug.print("encountered weird {c}", .{torrent[cursor]});
                break;
            },
        }
    }

    if (parsed_token_list.items.len % 2 != 0) return ParseError.InvalidDictionary;

    const l = try parsed_token_list.toOwnedSlice();

    for (l, 0..) |_, idx| {
        if (idx == l.len - 1) break;
        try kv.put(l[idx].string, l[idx + 1]);
    }
    return cursor;
}

pub fn parse_integer(l: *std.ArrayList(u8), parse_into: *u64, torrent: []const u8) !usize {
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
    const buf = try l.toOwnedSlice();
    parse_into.* = try std.fmt.parseInt(u64, buf, 10);
    return cursor;
}

pub fn parse_string(l: *std.ArrayList(u8), torrent: []const u8) !usize {
    var cursor: u64 = 0;
    for (torrent) |byte| {
        switch (byte) {
            '1'...'9' => try l.append(byte),
            ':' => {
                cursor += 1;
                break;
            },
            else => break,
        }
        cursor += 1;
    }
    const buf = try l.toOwnedSlice();
    const length = try std.fmt.parseInt(u64, buf, 10);

    try l.appendSlice(torrent[cursor .. cursor + length]);
    return cursor + length;
}

test "simple test" {}
