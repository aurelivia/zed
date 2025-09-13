const std = @import("std");
const Lexer = @import("../lexer.zig");
const ParseContext = @import("../parse_context.zig");
const ParseError = ParseContext.ParseError;
const BigInt = std.math.big.int.Const;

const Self = @This();

negative: bool,
mantissa: BigInt,
exponent: BigInt,

pub fn deinit(self: *Self, mem: std.mem.Allocator) void {
    mem.free(self.mantissa.limbs);
    mem.free(self.exponent.limbs);
}

fn wrap(
    mem: std.mem.Allocator,
    neg: bool, base: u8, whole: []Lexer.Token.Digits,
    frac: ?[]Lexer.Token.Digits, exp: ?[]Lexer.Token.Digits, neg_exp: bool
) ParseError!Self {
    defer {
        mem.free(whole);
        if (frac) |*f| mem.free(f);
        if (exp) |*e| mem.free(e);
    }

    var base_mult: std.math.big.int.Managed = try .initSet(mem, base);
    defer base_mult.deinit();
    var shift: std.math.big.int.Managed = try .init(mem);
    defer shift.deinit();
    var mantissa: std.math.big.int.Managed = try .init(mem);
    errdefer mantissa.deinit();
    for (whole) |d| {
        try mantissa.mul(mantissa, base_mult);
        try mantissa.addScalar(mantissa, d.val);
    }
    if (frac) |f| { for (f) |d| {
        if (shift.eqlZero()) {
            try shift.set(base);
        } try shift.mul(shift, base_mult);

        try mantissa.mul(mantissa, base_mult);
        try mantissa.addScalar(mantissa, d.val);
    }}

    var exponent: std.math.big.int.Managed = try .initSet(mem, 1);
    errdefer exponent.deinit();
    if (exp) |e| { for (e) |d| {
        try exponent.mul(exponent, base_mult);
        try exponent.addScalar(exponent, d.val);
    }}
    if (neg_exp) exponent.negate();

    try exponent.sub(exponent, shift);

    return .{
        .negative = neg,
        .mantissa = mantissa.toConst(),
        .exponent = exponent.toConst()
    };
}

pub fn parse(ctx: *ParseContext, neg: bool, from_digits: ?Lexer.Token) ParseError!Self {
    if (from_digits) |digs| return try parseWhole(ctx, 10, digs);

    const n = try ctx.expectNext();
    switch (n) {
        .base_binary, .base_binary_upper => return try parseWhole(ctx, neg, 2, ctx.expectNext()),
        .base_octal, .base_octal_upper => return try parseWhole(ctx, neg, 8, ctx.expectNext()),
        .base_hex, .base_hex_upper => return try parseWhole(ctx, neg, 16, ctx.expectNext()),
        else => return ctx.err(n, ParseError.UnexpectedToken)
    }
}

fn parseWhole(ctx: *ParseContext, neg: bool, base: u8, digs: Lexer.Token) ParseError!Self {
    switch (digs) {
        .eof => return ctx.err(digs, ParseError.UnexpectedEOF),
        .line, .semicolon => return ctx.err(digs, ParseError.UnexpectedSeparator),

        .number => |buf_num| {
            const num: []Lexer.Token.Digit = try ctx.mem.alloc(Lexer.Token.Digit, buf_num.len);
            @memcpy(num, buf_num);
            const n = try ctx.peek();
            switch (n) {
                .radix => { _ = try ctx.next(); return try parseFrac(ctx, neg, base, num); },
                .exponent => { _ = try ctx.next(); return try parseExp(ctx, neg, base, num, null); },
                else => return try wrap(ctx.mem, base, neg, num, null, null, false)
            }
        },

        else => return ctx.err(digs, ParseError.UnexpectedToken)
    }
}

fn parseFrac(ctx: *ParseContext, neg: bool, base: u8, whole: []Lexer.Token.Digit) ParseError!Self {
    const n = try ctx.expectNext();
    switch (n) {
        .number => |buf_num| {
            const num: []Lexer.Token.Digit = try ctx.mem.alloc(Lexer.Token.Digit, buf_num.len);
            @memcpy(num, buf_num);
            const e = try ctx.peek();
            switch (e) {
                .exponent => { _ = try ctx.next(); return try parseExp(ctx, neg, base, whole, num); },
                else => return try wrap(ctx.mem, base, neg, whole, num, null, false)
            }
        },
        else => return ctx.err(n, ParseError.UnexpectedToken)
    }
}

fn parseExp(ctx: *ParseContext, neg: bool, base: u8, whole: []Lexer.Token.Digit, frac: ?[]Lexer.Token.Digit) ParseError!Self {
    var neg_exp: bool = false;
    var num: ?Lexer.Token = null;
    var n = try ctx.expectNext();
    switch (n) {
        .minus => neg_exp = true,
        .plus => {},
        .number => num = n,
        else => return ctx.err(n, ParseError.UnexpectedToken)
    }

    n = num orelse try ctx.expectNext();
    switch (n) {
        .number => |buf_exp| {
            const exp: []Lexer.Token.Digit = try ctx.mem.alloc(Lexer.Token.Digit, buf_exp.len);
            @memcpy(exp, buf_exp);
            return try wrap(ctx.mem, base, neg, whole, frac, exp, neg_exp);
        },
        else => return ctx.err(n, ParseError.UnexpectedToken)
    }
}
