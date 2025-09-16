const std = @import("std");
const Tree = @import("../../tree.zig").Tree;

const Lexer = @import("../lexer.zig");
const Parser = @import("../parser.zig");

pub fn parse(ctx: *Parser, single_quote: bool) Parser.Error!Tree.Branch.Tagged {
    const start: usize = ctx.string_buf.items.len;
    var s: usize = 0;

    while (true) {
        const next = try ctx.next();
        switch (next.val) {
            .eof, .line => return ctx.err(next, Parser.Error.UnterminatedString),

            .single_quote, .double_quote => {
                if ((next.val == .single_quote and single_quote) or (next.val == .double_quote and !single_quote)) {
                    const str = ctx.string_buf.items[start..];
                    ctx.string_buf.items.len = start;
                    return try ctx.store(str);
                } else try append(ctx, start, &s, Lexer.Token.toChar(next));
            },

            .whitespace => |wsp| {
                const slice = try ctx.string_buf.addManyAt(ctx.mem, start + s, wsp);
                @memset(slice, ' ');
                s += wsp;
            },

            .literal => |l| {
                const slice = try ctx.string_buf.addManyAt(ctx.mem, start + s, l.len);
                @memcpy(slice, l);
                s += l.len;
            },

            .char => |c| try append(ctx, start, &s, c),

            else => |c| try append(ctx, start, &s, Lexer.Token.Value.toChar(c))
        }
    }
}

fn append(ctx: *Parser, start: usize, s: *usize, char: u32) !void {
    try ctx.string_buf.insert(ctx.mem, start + s.*, char);
    s.* += 1;
}

test "Parsing: String" {
    // Omitting starting quote, as that triggers the context
    const parser: *Parser = try .createTestParser("this is a \\nl string! 12345\'");
    defer parser.destroyTestParser();

    const result = try parse(parser, true);

    try std.testing.expectEqualSlices(u32, parser.literals.lits.items[0], &Lexer.debugEncodeString("this is a \n string! 12345"));
    try std.testing.expectEqual(.literal, result[0]);
    try std.testing.expectEqual(0, result[1].literal);
}
