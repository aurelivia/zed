const std = @import("std");
const log = std.log.scoped(.zed);
const OOM = error.OutOfMemory;

const root = @import("./root.zig");
const mem = root.mem;

const Lexer = @import("../lexer.zig");

const Any = @import("./any.zig").Any;
const Error = @import("./error.zig");

pub fn parse(lex: *Lexer, negative: bool) OOM!Any {
    var scope: Error = .init(lex);
    const parsed = tryParse(&scope, lex, negative) catch |e| try Error.parse(scope, e);
    if (parsed.type != .err and scope.err != null) return try Error.store(scope);
    return parsed;
}

pub fn tryParse(scope: *Error, lex: *Lexer, negative: bool) Error.ParseError!Any {
pub fn parse(lex: *Lexer, negative: bool) !Any {
    var mode: enum { whole, fraction, exponent } = .whole;

    var is_int: bool = true;
    var int: u48 = 0;
    var float: f64 = 0.0;
    var base_int: u48 = 10;
    var base_float: f64 = 10.0;
    var offset: f64 = 10.0;
    var exp: f64 = 1.0;
    var neg_exp: bool = false;

    while (true) {
        const next = try lex.peek();
        switch (next.val) {
            .base_header => lex.toss(), // Ignored
            .base_binary => { lex.toss(); base_int = 2; base_float = 2.0; offset = 2.0; },
            .base_octal  => { lex.toss(); base_int = 8; base_float = 8.0; offset = 8.0; },
            .base_hex    => { lex.toss(); base_int = 16; base_float = 16.0; offset = 16.0; },

            .digit => |d| {
                lex.toss();
                if (d > base_int) {
                    scope.err = error.DigitExceedsBase;
                    continue;
                }

                if (is_int) {
                    const cur = int;
                    int, const over_mul = @mulWithOverflow(int, base_int);
                    int, const over_add = @addWithOverflow(int, d);
                    if (over_mul or over_add) {
                        is_int = false;
                        float = @floatFromInt(cur);
                    } else continue;
                }

                const fd: f64 = @floatFromInt(d);
                switch (mode) {
                    .whole => float = @mulAdd(f64, float, base_float, fd),
                    .fraction => {
                        float += (fd / offset);
                        offset *= base_float;
                    },
                    .exponent => exp = @mulAdd(f64, exp, base_float, fd),
                }
            },

            .radix => {
                lex.toss();
                mode = .fraction;
                if (is_int) {
                    is_int = false;
                    float = @floatFromInt(int);
                }
            },

            .exponent => {
                lex.toss();
                const maybe_sign = lex.peek() catch return try lex.getError();
                switch (maybe_sign.val) {
                    .minus => { lex.toss(); neg_exp = true; },
                    .plus => lex.toss(),
                    else => {}
                }

                mode = .exponent;
                if (is_int) {
                    is_int = false;
                    float = @floatFromInt(int);
                }
            },

            else => if (is_int) {
                if (negative) {
                    const neg = std.math.negateCast(int) catch {
                        float = 0.0 - @as(f64, @floatFromInt(int));
                        return Any.fromFloat(float);
                    };
                    return Any.fromIntStrict(neg);
                }
                return Any.fromIntStrict(int);
            } else {
                if (neg_exp) exp = 0.0 - exp;
                float = std.math.pow(f64, float, exp);
                if (negative) float = 0.0 - float;
                return Any.fromFloat(float);
            }
        }
    }
}
