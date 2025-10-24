const std = @import("std");
const log = std.log.scoped(.zed);
const Allocator = std.mem.Allocator;
const OOM = error{OutOfMemory};

const root = @import("../root.zig");
const Lexer = @import("../lexer.zig");

const Any = @import("./any.zig").Any;

pub const ParseError = error {
    LexerError,
    DigitExceedsBase,
    UnterminatedString,
    UnterminatedExpression
} || OOM;

pub const Store = @import("collections").Table(@This(), Any.Index);

pub const oom: Any = .{ .type = .err, .index = std.math.maxInt(Any.Index) };

// err: ?std.meta.Int(.unsigned, @bitSizeOf(anyerror)),
err: ?anyerror = null,
start_line: usize = 0,
start_col: usize = 0,
end_line: usize = 0,
end_col: usize = 0,
next: ?Store.Key = null,

pub fn init(lex: *Lexer) @This() {
    const next = lex.tryPeek() catch return .{};
    return .{
        .start_line = next.line,
        .start_col = next.col,
        .end_line = next.line,
        .end_col = next.col
    };
}

pub fn advance(self: *@This(), lex: *Lexer) void {
    const cur = lex.peek() catch unreachable;
    self.end_line = cur.line;
    self.end_col = cur.col;
    lex.toss();
}

pub fn advanceNext(self: *@This(), lex: *Lexer) error{LexerError}!Lexer.Token {
    const cur = try lex.next();
    self.end_line = cur.line;
    self.end_col = cur.col;
    return cur;
}

pub inline fn store(self: @This()) OOM!Any {
    return .{ .type = .err, .index = @as(Any.Index, @bitCast(try root.errors.create(root.mem, self))) };
}

pub fn parse(scope: *@This(), lex: *Lexer, err: anyerror) OOM!Any {
    if (err == error.OutOfMemory) return error.OutOfMemory;
    if (err == error.LexerError) return try lex.getError();
    scope.err = err;
    return try store(scope.*);
}
