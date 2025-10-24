const std = @import("std");
const Allocator = std.mem.Allocator;
const collections = @import("collections");

pub const buffers = @import("./buffers.zig");
pub const Lexer = @import("./lexer.zig");

pub const Lang = struct {
    pub const Any = @import("./lang/any.zig").Any;
    pub const Error = @import("./lang/error.zig");
    pub const Expression = @import("./lang/expression.zig");
};

pub var mem: Allocator = undefined;

pub var errors: Lang.Error.Store = .empty;
pub var literals: collections.HashDict(Lang.Any.Index) = .empty;
pub var exprs: Lang.Expression.Store = .empty;

pub fn deinit() void {
    buffers.deinit();
    errors.deinit(mem);
    literals.deinit(mem);
    exprs.deinit(mem);
}

pub fn init(m: Allocator) Allocator.Error!void {
    mem = m;
}

pub fn getOrPutLiteral(slice: []const u8) Allocator.Error!Lang.Any.Index {
    return @bitCast(try literals.getOrPut(mem, slice));
}
