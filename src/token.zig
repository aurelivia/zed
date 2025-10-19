const std = @import("std");

const Self = @This();

pub const Value = union (enum) {
    eof,
    whitespace: usize,
    /// NOTE: THIS SLICE IS VOLATILE, AND IS INVALIDATED WHEN Lexer.next() IS CALLED.
    /// THE SLICE MUST BE COPIED TO BE PRESERVED.
    literal: []u8,
    char: u21,
    digit: u8,

    // Delimiters
    line,
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
    at, caret, bar, tilde,
    backslash,

    // Contextual Selfs
    radix, base_header,
    base_binary, base_octal, base_hex,
    exponent, repeat,

    pub fn toChar(self: Value) u8 {
        return switch (self) {
            .digit => |d| switch (d) {
                0...9 => @as(u8, @intCast(d | 0b00110000)),
                else => @as(u8, @intCast((d -| 9) | 0b01000000))
            },
            .line => '\n',
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
            .at => '@', .caret => '^', .bar => '|', .tilde => '~',
            .backslash => '\\', .radix => '.', .base_header => '0',
            .base_binary => 'b', .base_octal => 'o', .base_hex => 'x',
            .exponent => 'e', .repeat => 'r',
            else => unreachable
        };
    }

    pub fn isOperator(self: Value) bool {
        return switch (self) {
            .exclam, .dollar,
            .percent, .ampersand, .star,
            .plus, .minus, .slash, .colon,
            .less, .equal, .greater, .qmark,
            .at, .caret, .bar, .tilde => true,
            else => false
        };
    }
};

val: Value,
line: usize,
col: usize,

pub fn deinit(self: *Self, mem: std.mem.Allocator) void {
    switch (self.value) {
        inline .literal, .number => |v| mem.free(v),
        else => {}
    }
}

pub fn singleton(char: u21) ?Self.Value {
    return switch (char) {
        ' ' => .{ .whitespace = 1 }, '\n' => .line,
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
        '@' => .at, '^' => .caret, '|' => .bar, '~' => .tilde,
        else => null
    };
}

pub inline fn toChar(self: Self) u8 {
    return Value.toChar(self.val);
}

pub inline fn isOperator(self: Self) bool {
    return Value.isOperator(self.val);
}
