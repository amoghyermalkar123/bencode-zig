const std = @import("std");
const Tokenizer = @import("tokenizer.zig").Tokenizer;
const Token = @import("tokenizer.zig").Token;

pub fn main() !void {
    const torrent = "d3:foo3:bar5:helloi52ee";
    var t = Tokenizer.init(torrent);

    var tokens = std.ArrayList(Token).init(std.heap.page_allocator);
    defer tokens.deinit();

    var next = try t.next();
    while (next.tag != .eof) {
        std.debug.print("TOKEN {any}\n", .{next.tag});
        try tokens.append(next);
        next = try t.next();
    }
}
