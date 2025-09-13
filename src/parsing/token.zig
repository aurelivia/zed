const std = @import("std");

const Self = @This();

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

pub fn deinit(self: *Self, mem: std.mem.Allocator) void {
    switch (self.value) {
        inline .literal, .number => |v| mem.free(v),
        else => {}
    }
}

pub fn singleton(char: u21) ?Self.Value {
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

pub fn toChar(self: *const Self) u21 {
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
