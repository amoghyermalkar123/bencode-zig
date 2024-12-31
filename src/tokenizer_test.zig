const std = @import("std");
const testing = std.testing;
const Tokenizer = @import("tokenizer.zig").Tokenizer;
const Token = @import("tokenizer.zig").Token;

// Helper function to collect all tokens from a string
fn collectTokens(tokens: *std.ArrayList(Token), input: [:0]const u8) anyerror!void {
    var tokenizer = Tokenizer.init(input);

    var next = try tokenizer.next();
    while (next.tag != .eof) {
        try tokens.append(next);
        next = try tokenizer.next();
    }
    try tokens.append(next); // Include EOF token
}

// Helper function to verify token sequence
fn verifyTokenSequence(tokens: *std.ArrayList(Token), expected_tags: []const Token.Tag) !void {
    try testing.expectEqual(expected_tags.len, tokens.items.len);

    for (tokens.items, 0..) |token, i| {
        try testing.expectEqual(expected_tags[i], token.tag);
    }
}

test "empty string results in EOF token" {
    const input = "";
    var tokensList = std.ArrayList(Token).init(testing.allocator);
    defer tokensList.deinit();
    try collectTokens(
        &tokensList,
        input,
    );

    try verifyTokenSequence(&tokensList, &.{.eof});
}

test "simple dictionary with string" {
    const input = "d3:foo3:bare";
    var tokensList = std.ArrayList(Token).init(testing.allocator);
    defer tokensList.deinit();
    try collectTokens(
        &tokensList,
        input,
    );

    try verifyTokenSequence(&tokensList, &.{
        .dict,
        .string,
        .string,
        .end,
        .eof,
    });

    // Verify string content locations
    try testing.expectEqualSlices(u8, "foo", input[tokensList.items[1].loc.start..tokensList.items[1].loc.end]);
    try testing.expectEqualSlices(u8, "bar", input[tokensList.items[2].loc.start..tokensList.items[2].loc.end]);
}

test "nested dictionary" {
    const input = "d3:food3:bar3:bazee";
    var tokensList = std.ArrayList(Token).init(testing.allocator);
    defer tokensList.deinit();
    try collectTokens(
        &tokensList,
        input,
    );

    try verifyTokenSequence(&tokensList, &.{
        .dict,
        .string,
        .dict,
        .string,
        .string,
        .end,
        .end,
        .eof,
    });
}

test "integer parsing" {
    const input = "i52e";
    var tokensList = std.ArrayList(Token).init(testing.allocator);
    defer tokensList.deinit();
    try collectTokens(
        &tokensList,
        input,
    );

    try verifyTokenSequence(&tokensList, &.{
        .int,
        .eof,
    });

    // Verify the integer content location
    const int_str = input[tokensList.items[0].loc.start..tokensList.items[0].loc.end];
    const parsed = try std.fmt.parseInt(i64, int_str, 10);
    try testing.expectEqual(@as(i64, 52), parsed);
}

test "list with mixed types" {
    const input = "l3:fooi52e5:helloe";
    var tokensList = std.ArrayList(Token).init(testing.allocator);
    defer tokensList.deinit();
    try collectTokens(
        &tokensList,
        input,
    );

    try verifyTokenSequence(&tokensList, &.{
        .list,
        .string,
        .int,
        .string,
        .end,
        .eof,
    });
}

test "string with multi-digit length" {
    const input = "12:Hello World!";
    var tokensList = std.ArrayList(Token).init(testing.allocator);
    defer tokensList.deinit();
    try collectTokens(
        &tokensList,
        input,
    );

    try verifyTokenSequence(&tokensList, &.{
        .string,
        .eof,
    });

    try testing.expectEqualSlices(u8, "Hello World!", input[tokensList.items[0].loc.start..tokensList.items[0].loc.end]);
}

test "invalid integer format should return Invalid character error" {
    const input = "i52.3e";
    var tokensList = std.ArrayList(Token).init(testing.allocator);
    defer tokensList.deinit();
    try testing.expectError(error.InvalidCharacter, collectTokens(&tokensList, input));
}

test "invalid string length format" {
    const input = "a3:foo";
    var tokensList = std.ArrayList(Token).init(testing.allocator);
    defer tokensList.deinit();
    try testing.expectError(error.InvalidCharacter, collectTokens(&tokensList, input));
}

test "missing end marker" {
    const input = "i52";
    var tokensList = std.ArrayList(Token).init(testing.allocator);
    defer tokensList.deinit();
    try testing.expectError(error.UnexpectedEndOfInput, collectTokens(&tokensList, input));
}

test "dictionary with multiple entries" {
    const input = "d4:name5:Alice3:agei25e7:studiesl4:john3:doee";
    var tokensList = std.ArrayList(Token).init(testing.allocator);
    defer tokensList.deinit();
    try collectTokens(
        &tokensList,
        input,
    );

    try verifyTokenSequence(&tokensList, &.{
        .dict,
        .string,
        .string,
        .string,
        .int,
        .string,
        .list,
        .string,
        .string,
        .end,
        .eof,
    });
}

test "dictionary with multiple entries but one entry is weird" {
    const input = "d4:name5:Alice3:agei25e7:studiesltrueeee";

    var tokensList = std.ArrayList(Token).init(testing.allocator);
    defer tokensList.deinit();

    try testing.expectError(error.InvalidCharacter, collectTokens(&tokensList, input));

    try verifyTokenSequence(&tokensList, &.{
        .dict,
        .string,
        .string,
        .string,
        .int,
        .string,
        .list,
    });
}
