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

pub const TokenError = error{
    InvalidCharacter,
    UnexpectedEndOfInput,
};

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
                    result.loc.start = self.index + 1;
                    continue :state .bee_int;
                },
                '0'...'9' => {
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
                0, '\n' => {
                    result.tag = .eof;
                },
                else => {
                    if (self.index == self.buffer.len) {
                        result.tag = .eof;
                        return result;
                    }
                    continue :state .invalid;
                },
            },
            .bee_int => {
                self.index += 1;
                switch (self.buffer[self.index]) {
                    '0'...'9' => {
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
                    '0'...'9' => {
                        continue :state .bee_string;
                    },
                    ':' => {
                        const new_start = self.index + 1;
                        const parsedInt = try std.fmt.parseInt(u64, self.buffer[result.loc.start..self.index], 10);
                        if (new_start + parsedInt > self.buffer.len) {
                            return TokenError.UnexpectedEndOfInput;
                        }
                        self.index += parsedInt + 1;
                        result.loc.start = new_start;
                        result.loc.end = self.index;
                    },
                    else => {
                        continue :state .invalid;
                    },
                }
            },
            .invalid => {
                if (self.buffer.len == self.index) return TokenError.UnexpectedEndOfInput;
                return TokenError.InvalidCharacter;
            },
        }
        return result;
    }
};
