const std = @import("std");
const log = std.log.scoped(.zed);
const Allocator = std.mem.Allocator;
const Module = @import("./module.zig");
const Any = @import("./any.zig").Any;

const Big = std.math.big.int.Managed;
const Lexer = @import("./lexer.zig");

pub const Error = error {
    UnterminatedString
} || std.mem.Allocator.Error;

mem: Allocator,
lexer: *Lexer,
module: *Module,
pending: ?Lexer.Token = null,
string_buf: std.ArrayList(u32),
number_buf: Big,
mult_buf: Big,
digit_buf: std.ArrayList(u8),

pub fn deinit(self: *@This()) void {
    self.string_buf.deinit(self.mem);
    self.number_buf.deinit();
    self.mult_buf.deinit();
    self.digit_buf.deinit();
}

pub fn init(mem: Allocator, lexer: *Lexer, module: *Module) Allocator.Error!@This() {
    return .{
        .mem = mem,
        .module = module,
        .lexer = lexer,
        .string_buf = .empty,
        .number_buf = try .init(mem),
        .mult_buf = try .init(mem),
        .digit_buf = .empty
    };
}

pub inline fn peek(self: *@This()) Error!Lexer.Token {
    if (self.pending) |p| return p;
    return self.lexer.peek() catch {
        unreachable;
    };
}

pub inline fn next(self: *@This()) Error!Lexer.Token {
    if (self.pending) |p| { self.pending = null; return p; }
    return self.lexer.next() catch {
        unreachable;
    };
}
