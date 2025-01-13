const std = @import("std");
const Tokenizer = @import("tokenizer.zig").Tokenizer;
const Token = @import("tokenizer.zig").Token;
const Parser = @import("parser.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    const file = try std.fs.cwd().openFile("./sample.torrent", .{});
    defer file.close();

    const contents = try file.readToEndAllocOptions(allocator, std.math.maxInt(usize), null, @alignOf(u8), 0);
    defer allocator.free(contents);

    var t = Tokenizer.init(contents);
    const torrent = try Parser.parse(allocator, contents, &t);
    std.debug.print("Parsed Torrent: {any}\n", .{torrent});
}
