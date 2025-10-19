const std = @import("std");
const log = std.log.scoped(.zed);
const Allocator = std.mem.Allocator;
const OOM = error.OutOfMemory;

const Lexer = @import("../lexer.zig");
const Error = @import("./error.zig");

pub fn tryParse(scope: *Error, lex: *Lexer) Error.ParseError!void {
    while (true) {
        const next = try lex.peek();
        switch (next.val) {
            .eof => return,
            .semicolon, .line => { scope.advance(lex); return; },
            else => scope.advance(lex)
        }
    }
}
