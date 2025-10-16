const std = @import("std");
const log = std.log.scoped(.zed);
const Allocator = std.mem.Allocator;

const Module = @import("./module.zig");

const Builtin = @import("./builtin.zig");
const Literal = @import("./literal.zig");
const Path = @import("./path.zig").Path;
const Expression = @import("./expression.zig").Expression;
const Lambda = @import("./lambda.zig").Lambda;
const Set = @import("./set.zig");
const List = @import("./list.zig");

pub const Any = packed struct (u64) {
    pub const Type = enum (u3) {

    };

    pub const Index = u48;

    const max_exp: u11 = std.math.maxInt(u11);

    float_sign: u1 = 0,
    float_exp: u11 = max_exp,
    float_check_bit: u1 = 1,
    type: Type,
    index: Index,

    pub inline fn isFloat(self: Any) bool {
        return if (self.float_exp == max_exp) self.float_check_bit == 0 else true;
    }

    const norm_nan: Any = .{
        .float_sign = 0,
        .float_exp = max_exp,
        .float_check_bit = 0,
        .type = @enumFromInt(0b100),
        .index = 0
    };

    pub inline fn fromFloat(f: f64) Any {
        if (f != f) return norm_nan;
        return @as(Any, @bitCast(f));
    }

    pub inline fn toFloat(self: Any) f64 {
        std.debug.assert(self.isFloat());
        return @as(f64, @bitCast(self));
    }
};
