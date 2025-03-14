const std = @import("std");
const Tokenizer = @import("tokenizer.zig").Tokenizer;
const Token = @import("tokenizer.zig").Token;
const Parser = @import("parser.zig").Parser;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    const file = try std.fs.cwd().openFile("./sample.torrent", .{});
    defer file.close();

    const contents = try file.readToEndAllocOptions(allocator, std.math.maxInt(usize), null, @alignOf(u8), 0);
    defer allocator.free(contents);

    var parser = try Parser.init(allocator, contents);
    defer parser.deinit();

    const torrent = try parser.parse();
    defer torrent.deinit();
    std.debug.print("Parsed Torrent: {any}\n", .{torrent.announce});
}
