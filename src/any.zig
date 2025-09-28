const std = @import("std");
const log = std.log.scoped(.zed);
const Allocator = std.mem.Allocator;
const Module = @import("./module.zig");

const Builtin = @import("./builtin.zig");
const Runtime = @import("./runtime.zig");
const Literal = @import("./literal.zig");
const Path = @import("./path.zig").Path;
const Expression = @import("./expression.zig").Expression;
const Lambda = @import("./lambda.zig").Lambda;
const Set = @import("./set.zig");
const List = @import("./list.zig");

pub const Any = packed struct (usize) {
    pub const Type = enum (u4) {
        builtin = 0, // Must be zero so it can be re-interpreted as an enum
        runtime = 1,
        literal = 2,
        path = 3,
        expression = 4,
        lambda = 5,
        set = 6,
        list = 7
    };

    pub const width = @typeInfo(usize).int.bits;
    pub const type_bits = @typeInfo(@typeInfo(Type).tag_type).int.bits;
    pub const index_bits = width - type_bits;
    pub const Index = @Type(std.builtin.Type.Int{ .signedness = .unsigned, .bits = index_bits });
    pub const index_mask = std.math.maxInt(Index) >> type_bits;

    type: Type,
    index: Index,

    pub fn reduce(ctx: *Module, idx: Any) Any {

    }

    pub fn compat(ctx: *Module, expected: Any, actual: Any) bool {

    }

    pub fn apply(ctx: *Module, idx: Any) Any {

    }
};
