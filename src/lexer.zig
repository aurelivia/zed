const std = @import("std");

const Self = @This();
const BigInt = std.math.big.int.Managed;

pub const Token = struct {
    pub const Value = union (enum) {
        pub const Digit = struct {
            val: u8,
            src: u21
        };

        eof,
        literal: []u21,
        char: u21,
        number: []Digit,

        // Delimiters
        space, line,
        semicolon, comment,
        open_brace, close_brace,
        open_bracket, close_bracket,
        open_paren, close_paren,
        single_quote, double_quote,

        // Basic set of ASCII operators
        dot, exclam, dollar,
        percent, ampersand, star,
        plus, comma, minus,
        slash, colon, less,
        equal, greater, qmark,
        at, caret, grave,
        bar, tilde,

        // Contextual Tokens
        radix, base_header,
        base_binary, base_binary_upper,
        base_octal, base_octal_upper,
        base_hex, base_hex_upper,
        exponent, exponent_upper
    };

    val: Value,
    line: usize,
    col: usize,
    len: usize,

    pub fn deinit(self: *Token, mem: std.mem.Allocator) void {
        switch (self.value) {
            inline .literal, .number => |v| mem.free(v),
            else => {}
        }
    }

    pub fn singleton(char: u21) ?Token.Value {
        return switch (char) {
            ' ' => .space, '\n' => .line,
            ';' => .semicolon, '#' => .comment,
            '{' => .open_brace, '}' => .close_brace,
            '[' => .open_bracket, ']' => .close_bracket,
            '(' => .open_paren, ')' => .close_paren,
            '\'' => .single_quote, '\"' => .double_quote,
            '.' => .dot, '!' => .exclam, '$' => .dollar,
            '%' => .percent, '&' => .ampersand, '*' => .star,
            '+' => .plus, ',' => .comma, '-' => .minus,
            '/' => .slash, ':' => .colon, '<' => .less,
            '=' => .equal, '>' => .greater, '?' => .qmark,
            '@' => .at, '^' => .caret, '`' => .grave,
            '|' => .bar, '~' => .tilde,
            else => null
        };
    }

    pub fn toChar(self: *const Token) u21 {
        return switch (self.val) {
            .space => ' ', .line => '\n',
            .semicolon => ';', .comment => '#',
            .open_brace => '{', .close_brace => '}',
            .open_bracket => '[', .close_bracket => ']',
            .open_paren => '(', .close_paren => ')',
            .single_quote => '\'', .double_quote => '\"',
            .dot => '.', .exclam => '!', .dollar => '$',
            .percent => '%', .ampersand => '&', .star => '*',
            .plus => '+', .comma => ',', .minus => '-',
            .slash => '/', .colon => ':', .less => '<',
            .equal => '=', .greater => '>', .qmark => '?',
            .at => '@', .caret => '^', .grave => '`',
            .bar => '|', .tilde => '~',
            .radix => '.', .base_header => '0',
            .base_binary => 'b', .base_binary_upper => 'B',
            .base_octal => 'o', .base_octal_upper => 'O',
            .base_hex => 'x', .base_hex_upper => 'X',
            .exponent => 'e', .exponent_upper => 'E',
            else => unreachable
        };
    }
};

const Context = enum {
    none, done,

    begin_char, char_literal, char_code, expect_char_separator,

    begin_number, try_base, number, try_exponent, end_number
};

const LexerError = error {
    InvalidByteSequence,
    ForbiddenWhitespace,
    UnexpectedEOF,
    UnrecognisedEscape,
    BadHexEscape,
    BadUnicodeEscape,
    ExpectedCharSeparator,
    InvalidNumber,
    DigitOutOfBounds,
} || std.mem.Allocator.Error;

mem: std.mem.Allocator,
source: std.fs.File.Reader,
context: Context = .none,
line: usize = 1,
col: usize = 0,
len: usize = 0,
buffer: std.ArrayListUnmanaged(u21) = .empty,
queued: ?Token.Value = null,
pending: ?u21 = null,
errored: ?LexerError = null,

char: u21 = 0,
char_len: usize = 0,

num_buffer: std.ArrayListUnmanaged(Token.Value.Digit) = .empty,
base: u8 = 10,
exp_upper: bool = false,
part: enum { whole, frac, exp } = .whole,

pub fn deinit(self: *Self) void {
    self.arena.deinit();
}

pub fn init(mem: std.mem.Allocator, src: std.fs.File.Reader) !Self {
    return .{ .mem = mem, .source = src };
}

// TODO: 0.15
// fn nextChar(self: *Self) !?u21 {
//     const b = self.source.peekByte() catch { return null; };
//     const l = try std.unicode.utf8ByteSequenceLength(b);
//     const c = switch (l) {
//         4 => try std.unicode.utf8Decode4(try self.source.peekArray(4)),
//         3 => try std.unicode.utf8Decode3(try self.source.peekArray(3)),
//         2 => try std.unicode.utf8Decode2(try self.source.peekArray(2)),
//         else => b
//     };
//     self.source.toss(l);
//     return c;
// }
fn nextChar(self: *Self) !u21 {
    const b = self.source.readByte() catch { return 3; }; // ASCII End-Of-Text, because we can't switch on optionals
    const l = try std.unicode.utf8ByteSequenceLength(b);
    return b: switch (l) {
        4 => {
            var bs = [4]u8{ b, 0, 0, 0 };
            for (1..4) |i| bs[i] = try self.source.readByte();
            break :b try std.unicode.utf8Decode4(bs);
        },
        3 => {
            var bs = [3]u8{ b, 0, 0 };
            for (1..3) |i| bs[i] = try self.source.readByte();
            break :b try std.unicode.utf8Decode3(bs);
        },
        2 => {
            var bs = [2]u8{ b, 0 };
            for (1..2) |i| bs[i] = try self.source.readByte();
            break :b try std.unicode.utf8Decode2(bs);
        },
        else => @as(u21, @intCast(b))
    };
}

inline fn getDigit(base: u8, dig: u21) LexerError!?Token.Value.Digit {
    const d: u8 = switch (dig) {
        '0'...'9' => @as(u8, @intCast(dig - 48)), // 0 @ 48
        'A'...'Z' => @as(u8, @intCast(dig - 55)), // A @ 65, plus 10
        'a'...'z' => @as(u8, @intCast(dig - 87)), // a @ 97, plus 10
        else => return null
    };

    if (d > base) return LexerError.DigitOutOfBounds;
    return .{ .val = d, .src = dig };
}

inline fn bufmatch(self: *Self, str: []const u21) bool {
    return std.mem.eql(u21, self.buffer.items, str);
}

fn give(self: *Self, val: Token.Value) Token {
    const t: Token = .{
        .val = val,
        .line = self.line,
        .col = self.col,
        .len = self.len
    };
    if (val == .line) {
        self.line += 1;
        self.col = 0;
    } else {
        self.col = self.col + self.len;
    }
    self.len = 0;
    return t;
}

fn wrap(self: *Self) std.mem.Allocator.Error!?Token {
    if (self.buffer.items.len == 0) return null;
    const lit: []u21 = try self.mem.alloc(u21, self.buffer.items.len);
    @memcpy(lit, self.buffer.items[0..self.buffer.items.len]);
    self.buffer.clearRetainingCapacity();
    return self.give(.{ .literal = lit });
}

fn wrapNum(self: *Self) std.mem.Allocator.Error!Token {
    const num: []Token.Value.Digit = try self.mem.alloc(Token.Value.Digit, self.num_buffer.items.len);
    @memcpy(num, self.num_buffer.items[0..self.num_buffer.items.len]);
    self.num_buffer.clearRetainingCapacity();
    return self.give(.{ .number = num });
}

fn wrappedOrElse(self: *Self, val: Token.Value) std.mem.Allocator.Error!Token {
    if (try self.wrap()) |t| {
        self.queued = val;
        return t;
    }
    return self.give(val);
}

pub fn next(self: *Self) !Token {
    if (self.errored) |e| return e;

    if (self.queued) |val| {
        self.queued = null;
        defer { self.len += 1; }
        return self.give(val);
    }

    while (true) {
        const c = if (self.pending) |p| p else self.nextChar() catch {
            self.errored = LexerError.InvalidByteSequence;
            return LexerError.InvalidByteSequence;
        };

        defer {
            if (self.pending != null) {
                self.pending = null;
            } else self.len += 1;
        }

        context: switch (self.context) {
            .done => {
                unreachable;
            },

            .none => switch (c) {
                3 => {
                    self.context = .done;
                    return self.give(.eof);
                },
                // Forbidden Whitespace
                '\t', 0x00A0, 0x180E, 0x2000...0x200D, 0x202F, 0x205F, 0x2060, 0x2800, 0x3000, 0x3164, 0xFEFF => {
                    self.errored = LexerError.ForbiddenWhitespace;
                    return LexerError.ForbiddenWhitespace;
                },
                // Ignored Whitespace
                '\r' => if (try self.wrap()) |t| return t,
                // Chars
                '\\' => {
                    self.context = .begin_char;
                    if (try self.wrap()) |t| return t;
                },
                // Numeric literals
                '0'...'9' => {
                    // If buffer is empty, this begins a number, otherwise part of literal
                    if (self.buffer.items.len == 0) {
                        continue :context .begin_number;
                    } else try self.buffer.append(self.mem, c);
                },
                // Reserved characters & operators
                else => if (Token.singleton(c)) |s| {
                    return try self.wrappedOrElse(s);
                // Anything else
                } else try self.buffer.append(self.mem, c)
            },

            .begin_char => switch (c) {
                3 => return LexerError.UnexpectedEOF,
                'x', 'u' => {
                    self.char_len = switch (c) { 'x' => 2, else => 4 };
                    self.context = .char_code;
                },
                'a'...'t', 'v', 'w', 'y', 'z' => {
                    std.debug.assert(self.buffer.items.len == 0);
                    self.context = .char_literal;
                    continue :context .char_literal;
                },
                else => {
                    self.char = c;
                    self.context = .expect_char_separator;
                }
            },

            .char_literal => switch (c) {
                3, ' ', ';', '\n', '\\' => {
                    if (self.buffer.items.len == 0) {

                    }

                    self.context = switch (c) {
                        3 => .done,
                        '\\' => .begin_char,
                        else => .none
                    };

                    const char: u21 = if (self.buffer.items.len == 1) self.buffer.items[0]
                        else if (self.bufmatch(&.{ 's', 'p' })) ' '
                        else if (self.bufmatch(&.{ 't', 'b' })) '\t'
                        else if (self.bufmatch(&.{ 'c', 'r' })) '\r'
                        else if (self.bufmatch(&.{ 'n', 'l' })) '\n'
                        else {
                            self.errored = LexerError.UnrecognisedEscape;
                            return LexerError.UnrecognisedEscape;
                        };

                    self.buffer.clearRetainingCapacity();
                    if (c == 3) self.queued = .eof;
                    return self.give(.{ .char = char });
                },
                'a'...'z' => try self.buffer.append(self.mem, c),
                else => {
                    self.errored = LexerError.UnrecognisedEscape;
                    return LexerError.UnrecognisedEscape;
                }
            },

            .char_code => if (self.len == self.char_len) {
                self.context = .expect_char_separator;
            } else {
                const d: u21 = switch (c) {
                    '0'...'9' => c - 48, // 0 @ 48
                    'A'...'F' => c - 55, // A @ 65, plus 10
                    'a'...'f' => c - 87, // a @ 97, plus 10
                    else => {
                        const e = switch (self.char_len) {
                            2 => LexerError.BadHexEscape,
                            4 => LexerError.BadUnicodeEscape,
                            else => unreachable
                        };
                        self.errored = e;
                        return e;
                    }
                };

                self.char *= 16;
                self.char += d;
            },

            .expect_char_separator => switch (c) {
                3, ' ', ';', '\n', '\\' => {
                    self.context = switch (c) {
                        3 => .done,
                        '\\' => .begin_char,
                        else => .none
                    };

                    if (c == 3) self.queued = .eof;
                    const t: Token = self.give(.{ .char = self.char });
                    self.char = 0;
                    return t;
                },
                else => {
                    self.errored = LexerError.ExpectedCharSeparator;
                    return LexerError.ExpectedCharSeparator;
                }
            },

            .begin_number => {
                self.part = .whole;
                switch (c) {
                    '0' => self.context = .try_base,
                    else => {
                        self.context = .number;
                        continue :context .number;
                    }
                }
            },

            .try_base => switch (c) {
                'b', 'B', 'o', 'O', 'x', 'X' => {
                    self.queued = switch (c) {
                        'b' => .base_binary, 'B' => .base_binary_upper,
                        'o' => .base_octal, 'O' => .base_octal_upper,
                        'x' => .base_hex, 'X' => .base_hex_upper,
                        else => unreachable
                    };
                    self.base = switch (c) {
                        'b', 'B' => 2,
                        'o', 'O' => 8,
                        'x', 'X' => 16,
                        else => unreachable
                    };
                    self.context = .number;
                    return self.give(.base_header);
                },
                else => {
                    self.base = 10;
                    try self.num_buffer.append(self.mem, .{ .val = 0, .src = '0' });
                    self.context = .number;
                    continue :context .number;
                }
            },

            .number => switch (c) {
                '.' => if (self.part == .whole) {
                    self.part = .frac;
                    self.queued = .radix;
                    return try self.wrapNum();
                } else continue :context .end_number,
                'e' => if (self.part != .exp) {
                    self.exp_upper = false;
                    self.context = .try_exponent;
                    return try self.wrapNum();
                } else continue :context .end_number,
                'E' => if (self.part != .exp) {
                    self.exp_upper = true;
                    self.context = .try_exponent;
                    return try self.wrapNum();
                } else continue :context .end_number,
                else => if (try getDigit(self.base, c)) |d| {
                    try self.num_buffer.append(self.mem, d);
                } else continue :context .end_number
            },

            .try_exponent => switch (c) {
                '-', '+' => {
                    self.part = .exp;
                    self.context = .number;
                    self.queued = Token.singleton(c).?;
                    return self.give(if (self.exp_upper) .exponent_upper else .exponent);
                },
                else => if (try getDigit(self.base, c)) |d| {
                    self.part = .exp;
                    self.context = .number;
                    try self.num_buffer.append(self.mem, d);
                    return self.give(if (self.exp_upper) .exponent_upper else .exponent);
                } else {
                    self.context = .none;
                    continue :context .none;
                }
            },

            .end_number => {
                self.context = .none;
                self.pending = c;
                return try self.wrapNum();
            },
        }
    }
}

pub fn formatError(self: *Self) []const u8 {
    switch (self.errored) {
        else => unreachable,
    }
}

pub fn dump(self: *Self, output: anytype) !void {
    try output.writeAll("1: ");
    var buf = [4]u8{ 0, 0, 0, 0 };
    loop: while (true) {
        const token = try self.next();
        switch (token.val) {
            .eof => {
                try output.writeAll("EOF");
                break :loop;
            },

            .literal => |lit| {
                try output.print("({})\"", .{ token.col });
                for (lit) |l| {
                    const len = try std.unicode.utf8Encode(l, &buf);
                    try output.writeAll(buf[0..len]);
                }
                try output.print("\"[{}]", .{ token.len });
            },
            .char => |c| {
                try output.print("({})\\", .{ token.col });
                try output.writeAll(switch (c) {
                    ' ' => "sp",
                    '\t' => "tb",
                    '\r' => "cr",
                    '\n' => "nl",
                    else => b: {
                        const len = try std.unicode.utf8Encode(c, &buf);
                        break :b buf[0..len];
                    }
                });
            },
            .number => |num| {
                try output.print("({})", .{ token.col });
                for (num) |n| {
                    const len = try std.unicode.utf8Encode(n.src, &buf);
                    try output.writeAll(buf[0..len]);
                }
                try output.print("[{}]", .{ token.len });
            },
            .line => {
                try output.print("({})line\n{}: ", .{ token.col, token.line + 1 });
                continue :loop;
            },
            else => |v| try output.print("({}){s}", .{ token.col, @tagName(v) })
        }

        try output.writeAll(", ");
    }
}
