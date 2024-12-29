const std = @import("std");

pub const Token = struct {
    tag: Tag,
    loc: Loc,

    pub const Loc = struct {
        start: usize,
        end: usize,
    };

    pub const Tag = enum {
        dict,
        list,
        int,
        end,
        string,
        eof,
    };
};


const Torrent = struct {
};

pub fn main() !void{
    const torrent = "d4:name5:Alice3:agei25eel4:name3:Bob3:agei26ee";
    var t = Tokenizer.init(torrent);

    var tokens = std.ArrayList(Token).init(std.heap.page_allocator);
    defer tokens.deinit();

    var next= try t.next();
    while (next.tag != .eof) {
        try tokens.append(next);
        next = try t.next();
    }

    var decoded_torrent = Torrent{};
}

pub const Tokenizer = struct {
    buffer: [:0]const u8,
    index: u64,

    const Self = @This();

    pub fn init(buffer: [:0]const u8) Self {
        return .{
            .buffer = buffer,
            .index = 0,
        };
    }

    const State = enum {
        start,
        bee_int,
        bee_string,
        invalid,
    };

    pub fn next(self: *Tokenizer) !Token {
        var result: Token = .{
            .tag = undefined,
            .loc = .{
                .start = self.index,
                .end = undefined,
            },
        };

        state: switch (State.start) {
            .start => switch (self.buffer[self.index]) {
                'd' => {
                    result.tag = .dict;
                    result.loc.start = self.index;
                    result.loc.end = self.index;
                    self.index += 1;
                },
                'l' => {
                    result.tag = .list;
                    result.loc.start = self.index;
                    result.loc.end = self.index;
                    self.index += 1;
                },
                'i' => {
                    result.tag = .int;
                    result.loc.start = self.index;
                    continue :state .bee_int;
                },
                '1'...'9' => {
                    result.tag = .string;
                    result.loc.start = self.index;
                    continue :state .bee_string;
                },
                'e' => {
                    result.tag = .end;
                    result.loc.start = self.index;
                    result.loc.end = self.index;
                    self.index += 1;
                },
                0 => {
                    result.tag = .eof;
                },
                else => {
                    continue :state .invalid;
                },
            },
            .bee_int => {
                self.index += 1;
                switch (self.buffer[self.index]) {
                    '1'...'9' => {
                        self.index += 1;
                        continue :state .bee_int;
                    },
                    'e' => {
                        result.loc.end = self.index;
                        self.index += 1;
                    },
                    else => {
                        continue :state .invalid;
                    },
                }
            },
            .bee_string => {
                self.index += 1;
                switch (self.buffer[self.index]) {
                    'a'...'a', 'A' ...'Z' => {
                        self.index += 1;
                        continue :state .bee_string;
                    },
                    ':' => {
                        const new_start = self.index + 1;
                        const parsedInt = try std.fmt.parseInt(u64, self.buffer[result.loc.start..self.index], 64);
                        self.index += parsedInt;
                        result.loc.start = new_start;
                        result.loc.end = self.index;
                        self.index += 1;
                    },
                    else => {
                        continue :state .invalid;
                    },
                }
            },
            .invalid => {
                @panic("reached invalid state");
            },
        }
        return result;
    }
};


