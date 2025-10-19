const std = @import("std");
const log = std.log.scoped(.zed);
const Allocator = std.mem.Allocator;
const OOM = error.OutOfMemory;

const root = @import("./root.zig");
const mem = root.mem;
const buffers = @import("../buffers.zig");
const Lexer = @import("../lexer.zig");

const Any = @import("./any.zig");
const Comment = @import("./comment.zig");
const Error = @import("./error.zig");
const String = @import("./string.zig");
const Number = @import("./number.zig");
const Path = @import("./path.zig");

pub const Store = @import("olib-collections").Table(@This(), Any.Index);

left: Any,
right: Any,

pub fn parse(lex: *Lexer, terminator: ?Lexer.Token) OOM!Any {
    var scope: Error = .init(lex);
    const parsed = tryParse(&scope, lex, terminator) catch |e| return try Error.parse(scope, lex, e);
    if (scope.err != null or scope.next != null) return try Error.store(scope);
    return parsed;
}

fn tryParse(scope: *Error, lex: *Lexer, terminator: ?Lexer.Token) Error.ParseError!Any {
    var ops = buffers.get(u8);
    defer buffers.release(ops);

    var prev: ?Any = null;

    while (true) {
        const next = try lex.peek();
        switch (next.val) {
            .whitespace => { lex.toss(); prev = try wrap(scope, lex, &ops, prev, null); },
            .comment => try Comment.tryParse(lex),
            .eof, .line, .semicolon => if (terminator == null) {
                return try wrap(scope, lex, &ops, prev, null);
            } else if (next.val == .line) lex.toss() else return error.UnterminatedExpression,

            // --- Enclosing

            .close_brace, .close_bracket, .close_paren => if (terminator == null or terminator == next.val) {
                return try wrap(scope, lex, &ops, prev, null);
            } else return error.UnterminatedExpression,

            .open_paren => prev = try wrap(scope, lex, &ops, prev, try parse(lex, .close_paren)),
            .open_brace => {},
            .open_bracket => {},

            // --- Digits

            .base_header => lex.toss(), // Ignored, base will trigger context
            .digit, .base_binary, .base_octal, .base_hex => prev = try wrap(scope, lex, &ops, prev, try Number.parse(lex, false)),
            // Should never be found before one of the above numerics
            .radix, .exponent, .repeat => unreachable,

            // --- Literals

            .literal => |l| { lex.toss(); prev = try wrap(scope, lex, &ops, prev, .{ .type = .literal, .idx = try root.literals.getOrPut(mem, l) }); },
            .char => |c| { lex.toss(); prev = try wrap(scope, lex, &ops, prev, Any.fromIntStrict(c)); },
            .single_quote, .double_quote => { lex.toss(); prev = try wrap(scope, lex, &ops, prev, try String.parse(lex, next.val == .double_quote)); },

            // --- Not Operators

            .dot => {},
            .comma => {},

            // --- Operators

            else => |op| {
                std.debug.assert(Lexer.Token.Value.isOperator(op));
                lex.toss();

                // Handle negative numbers
                if (op == .minus) {
                    const maybe_digit = try lex.peek();
                    switch (maybe_digit) {
                        .digit, .base_header => {
                            prev = try wrap(scope, lex, &ops, prev, null);
                            if (maybe_digit.val == .base_header) lex.toss();
                            prev = try wrap(scope, lex, &ops, prev, try Number.parse(lex, true));
                        },
                        else => {}
                    }
                } else if (ops.len == 0 and (try lex.peek()).isOperator() == false) {
                    switch (op) {
                        .colon => {

                        },
                        .equal => {

                        },
                        else => {}
                    }
                }

                try ops.appendSlice(mem, Lexer.Token.Value.toBytes(op));
            }
        }
    }
}

pub fn wrap(scope: *Error, lex: *Lexer, ops: *std.ArrayList(u8), left: ?Any, right: ?Any) OOM!?Any {
    scope.end_line = lex.cur_line;
    scope.end_col = lex.cur_col;

    if (right) |r| if (r.type == .err) {
        if (scope.next != null) |next| {
            const errs = root.errors.sliceMut();
            defer errs.release();
            var n: Any.Index = next;
            while (true) {
                const nerr = errs.get(n).?;
                if (nerr.next) |nn| {
                    n = nn;
                } else {
                    nerr.next = r.index;
                    errs.set(n, nerr);
                    break;
                }
            }
        } else scope.next = r.index;

        return r;
    };

    if (left) |l| if (l.type == .err) return l;

    const wrapped: ?Any = if (ops.len) b: {
        const op = try root.literals.getOrPut(mem, ops.items);
        ops.clearRetainingCapacity();
        if (left) |l| {
            break :b .{ .type = .expr , .index = try root.exprs.create(mem, .{
                .left = .{ .type = .literal, .index = op },
                .right = l
            }) };
        } else break :b op;
    } else left;

    if (right) |r| {
        if (wrapped) |l| {
            return .{ .type = .expr, .index = try root.exprs.create(mem, .{
                .left = l, .right = r
            }) };
        } else return r;
    } else return wrapped;
}
