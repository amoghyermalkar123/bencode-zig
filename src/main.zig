const std = @import("std");
const Tokenizer = @import("tokenizer.zig").Tokenizer;
const Token = @import("tokenizer.zig").Token;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    const file = try std.fs.cwd().openFile("./sample.torrent", .{});
    defer file.close();

    const contents = try file.readToEndAllocOptions(allocator, std.math.maxInt(usize), null, @alignOf(u8), 0);
    defer allocator.free(contents);

    var t = Tokenizer.init(contents);
    var tokens = std.ArrayList(Token).init(std.heap.page_allocator);
    defer tokens.deinit();

    var next = try t.next();
    while (next.tag != .eof) {
        std.debug.print("TOKEN {any}\n", .{next.tag});
        try tokens.append(next);
        next = try t.next();
    }
}
