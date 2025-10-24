const std = @import("std");
const log = std.log.scoped(.zed);
const Allocator = std.mem.Allocator;
const OOM = error{OutOfMemory};

const root = @import("../root.zig");
const buffers = @import("../buffers.zig");
const Lexer = @import("../lexer.zig");

const Any = @import("./any.zig").Any;
const Comment = @import("./comment.zig");
const Error = @import("./error.zig");
const String = @import("./string.zig");
const Number = @import("./number.zig");

pub const Store = @import("collections").Table(@This(), Any.Index);

left: Any,
right: Any,

pub fn parse(lex: *Lexer, terminator: ?Lexer.Token.Value) OOM!Any {
    var scope: Error = .init(lex);
    const parsed = tryParse(&scope, lex, terminator) catch |e| return Error.parse(&scope, lex, e);
    if (scope.err != null or scope.next != null) return try Error.store(scope);
    return parsed;
}

fn tryParse(scope: *Error, lex: *Lexer, terminator: ?Lexer.Token.Value) Error.ParseError!Any {
    var ops = buffers.get(u8);
    defer buffers.release(ops);

    var prev: ?Any = null;

    while (true) {
        const next = try lex.peek();
        switch (next.val) {
            .whitespace => { lex.toss(); prev = try wrap(scope, lex, &ops, prev, null); },
            .comment => try Comment.tryParse(scope, lex),
            .eof, .line, .semicolon => if (terminator == null) {
                return (try wrap(scope, lex, &ops, prev, null)).?;
            } else if (next.val == .line) lex.toss() else return error.UnterminatedExpression,

            // --- Enclosing

            .close_brace, .close_bracket, .close_paren => if (terminator == null or terminator.?.eql(next.val)) {
                return (try wrap(scope, lex, &ops, prev, null)).?;
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

            .literal => |l| { lex.toss(); prev = try wrap(scope, lex, &ops, prev, .{
                .type = .literal, .index = try root.getOrPutLiteral(l)
            }); },
            .char => |c| { lex.toss(); prev = try wrap(scope, lex, &ops, prev, Any.fromIntStrict(c)); },
            .single_quote, .double_quote => { lex.toss(); prev = try wrap(scope, lex, &ops, prev, try String.parse(lex, next.val.eql(.double_quote))); },

            // --- Not Operators

            .dot => {},
            .comma => {},

            // --- Operators

            else => |op| {
                std.debug.assert(Lexer.Token.Value.isOperator(op));
                lex.toss();

                // Handle negative numbers
                if (op.eql(.minus)) {
                    const maybe_digit = try lex.peek();
                    switch (maybe_digit.val) {
                        .digit, .base_header => {
                            prev = try wrap(scope, lex, &ops, prev, null);
                            if (maybe_digit.val == .base_header) lex.toss();
                            prev = try wrap(scope, lex, &ops, prev, try Number.parse(lex, true));
                        },
                        else => {}
                    }
                } else if (ops.items.len == 0 and (try lex.peek()).isOperator() == false) {
                    switch (op) {
                        .colon => {

                        },
                        .equal => {

                        },
                        else => {}
                    }
                }

                try ops.append(root.mem, Lexer.Token.Value.toChar(op));
            }
        }
    }
}

pub fn wrap(scope: *Error, lex: *Lexer, ops: *std.ArrayList(u8), left: ?Any, right: ?Any) OOM!?Any {
    scope.end_line = lex.cur_line;
    scope.end_col = lex.cur_col;

    if (right) |r| if (r.type == .err) {
        if (scope.next) |next| {
            var errs = root.errors.sliceMut();
            defer errs.release();
            var n: Error.Store.Key = next;
            while (true) {
                var nerr = errs.get(n).?;
                if (nerr.next) |nn| {
                    n = nn;
                } else {
                    nerr.next = @bitCast(r.index);
                    errs.set(n, nerr);
                    break;
                }
            }
        } else scope.next = @bitCast(r.index);

        return r;
    };

    if (left) |l| if (l.type == .err) return l;

    const wrapped: ?Any = if (ops.items.len != 0) b: {
        const op: Any = .{ .type = .literal, .index = try root.getOrPutLiteral(ops.items) };
        ops.clearRetainingCapacity();
        if (left) |l| {
            break :b .{
                .type = .expr ,
                .index = @as(Any.Index, @bitCast(try root.exprs.create(root.mem, .{
                    .left = op,
                    .right = l
                })))
            };
        } else break :b op;
    } else left;

    if (right) |r| {
        if (wrapped) |l| {
            return .{
                .type = .expr,
                .index = @as(Any.Index, @bitCast(try root.exprs.create(root.mem, .{
                    .left = l, .right = r
                })))
            };
        } else return r;
    } else return wrapped;
}
