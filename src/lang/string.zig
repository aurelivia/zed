const std = @import("std");
const log = std.log.scoped(.zed);
const Allocator = std.mem.Allocator;
const OOM = error{OutOfMemory};

const root = @import("../root.zig");
const buffers = @import("../buffers.zig");
const Lexer = @import("../lexer.zig");

const Any = @import("./any.zig").Any;
const Error = @import("./error.zig");

pub fn parse(lex: *Lexer, double_quote: bool) OOM!Any {
    var scope: Error = .init(lex);
    const parsed = tryParse(&scope, lex, double_quote) catch |e| return Error.parse(&scope, lex, e);
    if (scope.err != null or scope.next != null) return Error.store(scope);
    return parsed;
}

fn tryParse(scope: *Error, lex: *Lexer, double_quote: bool) Error.ParseError!Any {
    var buf = buffers.get(u8);
    errdefer buffers.release(buf);

    while (true) {
        const next = try lex.peek();
        switch (next.val) {
            .eof, .line => return error.UnterminatedString,
            else => scope.advance(lex)
        }
        switch (next.val) {
            .single_quote, .double_quote => if ((next.val == .single_quote and !double_quote) or (next.val == .double_quote and double_quote)) {
                const idx = try root.getOrPutLiteral(buf.items);
                buffers.release(buf);
                return .{ .type = .string, .index = @truncate(idx) };
            } else try buf.append(root.mem, Lexer.Token.toChar(next)),

            .whitespace => |wsp| {
                const slc = try buf.addManyAsSlice(root.mem, wsp);
                @memset(slc, ' ');
            },

            .literal => |l| {
                const slc = try buf.addManyAsSlice(root.mem, l.len);
                @memcpy(slc, l);
            },

            .char => |c| {
                var b: [3]u8 = undefined;
                const len = std.unicode.utf8Encode(c, &b) catch unreachable;
                try buf.appendSlice(root.mem, b[0..len]);
            },

            else => |c| try buf.append(root.mem, Lexer.Token.Value.toChar(c)),
        }
    }
}
