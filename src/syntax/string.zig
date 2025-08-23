const std = @import("std");
const Lexer = @import("../lexer.zig");
const ParseContext = @import("../parse_context.zig");
const ParseError = ParseContext.ParseError;
const Any = @import("../syntax.zig").Any;

const Self = @This();

pub const Value = union (enum) {
    literal: []const u21,
    expr: Any,

    pub fn deinit(self: Value, mem: std.mem.Allocator) void {
        switch (self) {
            .literal => |l| mem.free(l),
            .expr => |e| e.deinit(mem)
        }
    }
};

val: Value,
next: ?*Self = null,

pub fn deinit(self: *Self, mem: std.mem.Allocator) void {
    self.val.deinit(mem);
    if (self.next) |*next| next.deinit(mem);
}

fn append(ctx: *ParseContext, start: usize, s: *usize, char: u21) !void {
    try ctx.string_buf.ensureTotalCapacity(start + s.*);
    ctx.string_buf.items[start + s.*] = char;
    s.* += 1;
}

pub fn parse(ctx: *ParseContext, single_quote: bool) ParseError!Self {
    const start: usize = ctx.string_buf.items.len;
    var s: usize = start;

    defer {
        ctx.string_buf.items.len = start;
    }

    while (true) {
        const n = ctx.next();
        switch (n) {
            .eof => return ParseError.UnexpectedEOF,

            .single_quote, .double_quote => {
                if ((n == .single_quote and single_quote) or (n == .double_quote and !single_quote)) {
                    const val: []u21 = try ctx.mem.alloc(u21, start + s);
                    @memcpy(val, ctx.string_buf.items[start..s]);
                    return .{
                        .val = .{ .literal = val },
                        .next = null
                    };
                } else try append(ctx, start, &s, Lexer.Token.toChar(n));
            },

            .literal => |l| {
                try ctx.string_buf.ensureTotalCapacity(start + s + l.len);
                @memcpy(ctx.string_buf.items[(start + s)..(start + s + l.len)], l);
                s += l.len;
            },

            .char => |c| try append(ctx, start, &s, c),

            .number => |num| {
                try ctx.string_buf.ensureTotalCapacity(start + s + num.len);
                for (num, 0..) |d, i| ctx.string_buf.items[start + s + i] = d.src;
                s += num.len;
            },

            .dollar => {
                const val: []u21 = try ctx.mem.alloc(u21, start + s);
                @memcpy(val, ctx.string_buf.items[start..s]);
                ctx.string_buf.items.len = start;
                return .{
                    .val = val,
                    .next = try parseExpr(&ctx, single_quote)
                };
            },

            else => |c| try append(ctx, start, &s, Lexer.Token.toChar(c))
        }
    }
}

pub fn parseExpr(ctx: *ParseContext, single_quote: bool) !Self {


}
