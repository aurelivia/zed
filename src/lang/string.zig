const std = @import("std");
const log = std.log.scoped(.zed);
const Allocator = std.mem.Allocator;
const OOM = error.OutOfMemory;

const root = @import("./root.zig");
const mem = root.mem;
const buffers = @import("../buffers.zig");
const Lexer = @import("../lexer.zig");

const Any = @import("./any.zig");
const Error = @import("./error.zig");

pub const Store = @import("olib-collections").RadixTable;

pub fn parse(lex: *Lexer, double_quote: bool) OOM!Any {
    var scope: Error = .init(lex);
    const parsed = tryParse(&scope, lex, double_quote) catch |e| try Error.parse(scope, lex, e);
    if (parsed.type != .err and scope.err != null) return try Error.store(scope);
    return parsed;
}

fn tryParse(scope: *Error, lex: *Lexer, double_quote: bool) Error.ParseError!Any {
    var buf = buffers.get(u8);
    errdefer buffers.release(buf);

    while (true) {
        const next = try scope.advanceNext(lex);
        switch (next.val) {
            .eof, .line => return error.UnterminatedString,

            .single_quote, .double_quote => if ((next.val == .single_quote and !double_quote) or (next.val == .double_quote and double_quote)) {
                const idx = try root.literals.getOrPut(mem, buf.items);
                buffers.release(buf);
                return .{ .type = .string, .index = idx };
            } else try buf.append(mem, Lexer.Token.toChar(next)),

            .whitespace => |wsp| {
                const slc = try buf.addManyAsSlice(mem, wsp);
                @memset(slc, ' ');
            },

            .literal => |l| {
                const slc = try buf.addManyAsSlice(mem, l.len);
                @memcpy(slc, l);
            },

            .char => |c| {
                var b: [3]u8 = undefined;
                const len = std.unicode.utf8Encode(c, &b) catch unreachable;
                try buf.appendSlice(mem, b[0..len]);
            },

            else => |c| try buf.append(mem, Lexer.Token.Value.toChar(c)),
        }
    }
}
