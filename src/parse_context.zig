const std = @import("std");
const Lexer = @import("./lexer.zig");
const Tokens = @import("./tokens.zig");
const syntax = @import("./syntax.zig");

const Self = @This();

pub const ParseError = error {

} || std.mem.Allocator.Error;

pub const ParseFns = struct {
    comment: fn (*Self) ParseError!void,
    number: fn (*Self, bool) ParseError!syntax.Number,
    string: fn (*Self, bool) ParseError!syntax.String,
};

parse_fns: ParseFns,
mem: std.mem.Allocator,
lexer: *Lexer,
string_buf: std.ArrayListUnmanaged(u21) = .empty,

pub fn deinit(self: *Self, mem: std.mem.Allocator) void {
    self.string_buf.deinit(mem);
}

pub inline fn next(self: *Self) ParseError!Lexer.Token {
    return self.lexer.next() catch {
        unreachable;
    };
}

pub inline fn expectNext(self: *Self) ParseError!Lexer.Token {
    const n = try self.next();
    switch (n) {
        .eof => return self.err(n, ParseError.UnexpectedEOF),
        .line, .semicolon => return self.err(n, ParseError.UnexpectedSeparator),
        else => return n
    }
}

pub inline fn err(self: *Self, t: Lexer.Token, e: ParseError) ParseError {
    _ = self;
    switch (e) {
        else => {}
    }
    return e;
}
