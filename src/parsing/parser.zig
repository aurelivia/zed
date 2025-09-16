const std = @import("std");
const Tree = @import("../tree.zig").Tree;

const Lexer = @import("./lexer.zig");
const Parsed = @import("./parsed.zig");

pub const LiteralStore = @import("../store.zig").Store(u32, @import("../store.zig").AutoContext(u32));

const Parser = @This();

pub const Error = error {
    UnterminatedString
} || std.mem.Allocator.Error;

mem: std.mem.Allocator,
lexer: *Lexer,
literals: *LiteralStore,
string_buf: std.ArrayList(u32),

pub fn deinit(self: *Parser) void {
    self.string_buf.deinit(self.mem);
}

pub fn init(mem: std.mem.Allocator, lexer: *Lexer, literals: *LiteralStore) std.mem.Allocator.Error!Parser {
    return .{
        .mem = mem,
        .lexer = lexer,
        .literals = literals,
        .string_buf = .empty
    };
}

pub inline fn next(self: *Parser) Error!Lexer.Token {
    return self.lexer.next() catch {
        unreachable;
    };
}

pub inline fn expectNext(self: *Parser) Error!Lexer.Token {
    const n = try self.next();
    switch (n) {
        .eof => return self.err(n, Error.UnexpectedEOF),
        .line, .semicolon => return self.err(n, Error.UnexpectedSeparator),
        else => return n
    }
}

pub inline fn err(self: *Parser, t: Lexer.Token, e: Error) Error {
    _ = self;
    _ = t;
    switch (e) {
        else => {}
    }
    return e;
}

pub inline fn store(self: *Parser, l: []const u32) std.mem.Allocator.Error!Tree.Branch.Tagged {
    return .{ .literal, .{ .literal = try self.literals.getOrPut(l) }};
}

pub fn createTestParser(comptime src: []const u8) std.mem.Allocator.Error!*Parser {
    const parser: *Parser = try std.testing.allocator.create(Parser);
    const literals: *LiteralStore = try std.testing.allocator.create(LiteralStore);
    literals.* = .{ .mem = std.testing.allocator };
    parser.* = .{
        .mem = std.testing.allocator,
        .lexer = try Lexer.createTestLexer(src),
        .literals = literals,
        .string_buf = .empty
    };
    return parser;
}

pub fn destroyTestParser(parser: *Parser) void {
    parser.literals.deinit();
    std.testing.allocator.destroy(parser.literals);
    parser.lexer.destroyTestLexer();
    parser.deinit();
    std.testing.allocator.destroy(parser);
}

const String = @import("./context/string.zig");
test {
    _ = String;
}
