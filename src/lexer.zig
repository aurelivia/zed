const std = @import("std");

const Self = @This();
const BigInt = std.math.big.int.Managed;

pub const Token = struct {
    pub const Value = union (enum) {
        pub const Number = struct {
            whole_part: BigInt,
            frac_part: BigInt,
            exponent: BigInt,

            pub fn deinit(self: *Number, mem: std.mem.Allocator) void {
                _ = mem;
                self.whole_part.deinit();
                self.frac_part.deinit();
                self.exponent.deinit();
            }

            pub fn init(mem: std.mem.Allocator) !Number {
                return .{
                    .whole_part = try .init(mem),
                    .frac_part = try .init(mem),
                    .exponent = try .init(mem)
                };
            }

            pub fn dump(self: *const Number, mem: std.mem.Allocator, output: anytype) !void {
                var buf: []u8 = try self.whole_part.toString(mem, 10, .upper);
                try output.writeAll(buf);
                mem.free(buf);
                try output.writeByte('.');
                buf = try self.frac_part.toString(mem, 10, .upper);
                try output.writeAll(buf);
                mem.free(buf);
                try output.writeByte('e');
                buf = try self.exponent.toString(mem, 10, .upper);
                try output.writeAll(buf);
                mem.free(buf);
            }
        };

        literal: []u21,
        char: u21,
        number: Number,

        // Delimiters
        space, line, semicolon,
        open_comment,
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
    };

    val: Value,
    line: usize,
    col: usize,
    len: usize,

    pub fn deinit(self: *Token, mem: std.mem.Allocator) void {
        switch (self.value) {
            .literal => |l| mem.free(l),
            .number => |n| n.deinit(),
            else => {}
        }
    }

    pub fn singleton(char: u21) ?Token.Value {
        return switch (char) {
            ' ' => .space, '\n' => .line, ';' => .semicolon,
            '#' => .open_comment,
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
};

const Context = enum {
    none,

    comment, comment_escape,

    begin_char, char_literal, char_code,
    expect_char_separator,

    maybe_minus, begin_number, end_number,
    try_base, expect_leading_zero, leading_zero,
    expect_whole, whole_part, exponent_else_whole,
    expect_frac, frac_part, exponent_else_frac,
    expect_exponent, exponent
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
buffer: std.ArrayListUnmanaged(u21),
queued: ?Token.Value = null,
pending: ?u21 = null,
errored: ?LexerError = null,

char: u21 = 0,
char_len: usize = 0,
base: u8 = 10,
base_mult: BigInt,
negative: bool = false,
neg_exp: bool = false,
number: ?Token.Value.Number = null,

pub fn deinit(self: *Self) void {
    self.arena.deinit();
}

pub fn init(mem: std.mem.Allocator, src: std.fs.File.Reader) !Self {
    return .{
        .mem = mem,
        .source = src,
        .buffer = std.ArrayListUnmanaged(u21).empty,
        .base_mult = try .initCapacity(mem, 8),
    };
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

inline fn getDigit(base: u8, dig: u21) LexerError!?u8 {
    const d: u8 = switch (dig) {
        '0'...'9' => @as(u8, @intCast(dig - 48)), // 0 @ 48
        'A'...'Z' => @as(u8, @intCast(dig - 55)), // A @ 65, plus 10
        'a'...'z' => @as(u8, @intCast(dig - 87)), // a @ 97, plus 10
        else => return null
    };

    if (d > base) return LexerError.DigitOutOfBounds;
    return d;
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

fn wrappedOrElse(self: *Self, val: Token.Value) std.mem.Allocator.Error!Token {
    if (try self.wrap()) |t| {
        self.queued = val;
        return t;
    }
    return self.give(val);
}

pub fn next(self: *Self) !?Token {
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
            .none => switch (c) {
                3 => return null,
                // Comment
                '#' => self.context = .comment,
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
                // Special case for minus, to capture negative numbers
                '-' => self.context = .maybe_minus,
                // Numeric literals
                '0'...'9' => {
                    self.context = .begin_number;
                    if (try self.wrap()) |t| {
                        return t;
                    } else continue :context .begin_number;
                },
                // Reserved characters & operators
                else => if (Token.singleton(c)) |s| {
                    return try self.wrappedOrElse(s);
                // Anything else
                } else {
                    try self.buffer.append(self.mem, c);
                }
            },

            .comment => switch (c) {
                3, ';' => {
                    self.context = .none;
                    self.col = self.col + self.len;
                    self.len = 0;
                },
                '\n' => {
                    self.context = .none;
                    return self.give(.line);
                },
                '\\' => self.context = .comment_escape,
                else => {}
            },
            .comment_escape => self.context = .comment,

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
                    self.context = if (c == '\\') .begin_char else .none;
                    const char: u21 = if (self.buffer.items.len == 1) self.buffer.items[0]
                        else if (self.bufmatch(&.{ 's', 'p' })) ' '
                        else if (self.bufmatch(&.{ 't', 'b' })) '\t'
                        else if (self.bufmatch(&.{ 'c', 'r' })) '\r'
                        else if (self.bufmatch(&.{ 'n', 'l' })) '\n'
                        else return LexerError.UnrecognisedEscape;

                    self.buffer.clearRetainingCapacity();
                    return self.give(.{ .char = char });
                },
                'a'...'z' => try self.buffer.append(self.mem, c),
                else => return LexerError.UnrecognisedEscape
            },

            .char_code => if (self.len == self.char_len) {
                self.context = .expect_char_separator;
            } else {
                const d: u21 = switch (c) {
                    '0'...'9' => c - 48, // 0 @ 48
                    'A'...'F' => c - 55, // A @ 65, plus 10
                    'a'...'f' => c - 87, // a @ 97, plus 10
                    else => return switch (self.char_len) {
                        2 => LexerError.BadHexEscape,
                        4 => LexerError.BadUnicodeEscape,
                        else => unreachable
                    }
                };

                self.char *= 16;
                self.char += d;
            },

            .expect_char_separator => switch (c) {
                3, ' ', ';', '\n', '\\' => {
                    self.context = if (c == '\\') .begin_char else .none;
                    const t: Token = self.give(.{ .char = self.char });
                    self.char = 0;
                    return t;
                },
                else => return LexerError.ExpectedCharSeparator
            },

            .maybe_minus => switch (c) {
                '0'...'9' => {
                    self.negative = true;
                    continue :context .begin_number;
                },
                else => {
                    self.pending = c;
                    self.context = .none;
                    return try self.wrappedOrElse(.minus);
                }
            },

            .begin_number => {
                self.number = try .init(self.mem);
                switch (c) {
                    '0' => self.context = .try_base,
                    else => {
                        self.base = 10;
                        try self.base_mult.set(10);
                        self.context = .whole_part;
                        continue :context .whole_part;
                    }
                }
            },

            .end_number => {
                self.pending = c;
                self.context = .none;
                if (self.negative) self.number.?.whole_part.negate();
                self.negative = false;
                if (self.number.?.exponent.eqlZero()) try self.number.?.exponent.set(1);
                if (self.neg_exp) self.number.?.exponent.negate();
                self.neg_exp = false;
                defer self.number = null;
                return self.give(.{ .number = self.number.? });
            },

            .try_base => {
                const b: u8 = switch (c) {
                    'b', 'B' => 2,
                    'o', 'O' => 8,
                    'x', 'X' => 16,
                    else => 10
                };
                self.base = b;
                try self.base_mult.set(b);
                if (b != 10) {
                    self.context = .expect_leading_zero;
                } else continue :context .expect_leading_zero;
            },

            .expect_leading_zero => if (c == '0') {
                self.context = .leading_zero;
            } else if (try getDigit(self.base, c)) |_| {
                self.context = .whole_part;
                continue :context .whole_part;
            } else return LexerError.InvalidNumber,

            .leading_zero => switch (c) {
                '0', '_' => {},
                else => {
                    self.context = .whole_part;
                    continue :context .whole_part;
                }
            },

            .expect_whole => if (try getDigit(self.base, c)) |_| {
                self.context = .whole_part;
                continue :context .whole_part;
            } else return LexerError.InvalidNumber,

            .whole_part => switch (c) {
                '_' => {},
                '.' => self.context = .frac_part,
                'e', 'E' => self.context = .exponent_else_whole,
                else => if (try getDigit(self.base, c)) |d| {
                    try self.number.?.whole_part.mul(&self.number.?.whole_part, &self.base_mult);
                    try self.number.?.whole_part.addScalar(&self.number.?.whole_part, d);
                } else continue :context .end_number
            },

            .exponent_else_whole => switch (c) {
                '-' => { self.neg_exp = true; self.context = .expect_exponent; },
                '+' => self.context = .expect_exponent,
                else => continue :context .whole_part
            },

            .expect_frac => if (try getDigit(self.base, c)) |_| {
                self.context = .frac_part;
                continue :context .frac_part;
            } else return LexerError.InvalidNumber,

            .frac_part => switch (c) {
                '_' => {},
                'e', 'E' => self.context = .exponent_else_frac,
                else => if (try getDigit(self.base, c)) |d| {
                    try self.number.?.frac_part.mul(&self.number.?.frac_part, &self.base_mult);
                    try self.number.?.frac_part.addScalar(&self.number.?.frac_part, d);
                } else continue :context .end_number
            },

            .exponent_else_frac => switch (c) {
                '-' => { self.neg_exp = true; self.context = .expect_exponent; },
                '+' => self.context = .expect_exponent,
                else => continue :context .frac_part
            },

            .expect_exponent => if (try getDigit(self.base, c)) |_| {
                self.context = .exponent;
                continue :context .exponent;
            } else return LexerError.InvalidNumber,

            .exponent => if (try getDigit(self.base, c)) |d| {
                try self.number.?.exponent.mul(&self.number.?.exponent, &self.base_mult);
                try self.number.?.exponent.addScalar(&self.number.?.exponent, d);
            } else if (c != '_') continue :context .end_number,
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
    loop: while (try self.next()) |token| {
        switch (token.val) {
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
            .number => |n| {
                try output.print("({})", .{ token.col });
                try n.dump(self.mem, output);
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

    try output.writeAll("EOF\n");
}
