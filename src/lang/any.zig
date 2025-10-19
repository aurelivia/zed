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
    pub const Type = enum (u4) {
        builtin = 0, // Set to zero to share space with Inf

        int = 1,

        err = 0b1111 // Set to max to share space with NaN
    };

    pub const index_bits = 48;
    pub const Index = u48;

    const max_exp: u11 = std.math.maxInt(u11);

    sign_bit: u1 = 0,
    float_exp: u11 = max_exp,
    type: Type,
    index: Index,

    pub inline fn isFloat(self: Any) bool {
        return (@as(u64, @bitCast(self)) == std.math.maxInt(u64)) or self.float_exp != max_exp or (self.type == .builtin and self.index == 0);
    }

    const norm_nan: Any = @as(Any, @bitCast(std.math.maxInt(u64)));

    comptime {
        if (@as(f64, @bitCast(norm_nan)) == std.math.snan(f64)) {
            @compileError("Normalized NaN is considered a signalling NaN.");
        }
    }

    pub inline fn fromFloat(f: f64) Any {
        if (f != f) return norm_nan;
        return @as(Any, @bitCast(f));
    }

    pub inline fn toFloat(self: Any) f64 {
        if (!self.isFloat()) {
            std.debug.print("Attempt to convert identifier to a float which does not represent a float.\n", .{});
            unreachable;
        }
        return @as(f64, @bitCast(self));
    }

    pub inline fn fromIntStrict(i: anytype) Any {
        switch (@typeInfo(@TypeOf(i))) {
            .int => |int| if (int.bits > index_bits) {
                std.debug.print("Attempt to store integer as smallint wider than available bits.\n", .{});
                unreachable;
            } else return .{ .sign_bit = int.signedness == .signed, .type = .smallint, .index = @as(Index, @bitCast(i)) },
            else => @compileError(@typeName(@TypeOf(i)) ++ " is not an integer type.")
        }
    }

    pub inline fn fromInt(i: anytype) Any {
        switch (@typeInfo(@TypeOf(i))) {
            .int => |int| if (int.bits > index_bits) {
                return fromFloat(@as(f64, @floatFromInt(i)));
            } else return fromIntStrict(i),
            else => @compileError(@typeName(@TypeOf(i)) ++ " is not an integer type.")
        }
    }

    pub inline fn toIntStrict(self: Any, comptime T: type) T {
        if (self.isFloat()) {
            std.debug.print("Attempt to use identifier representing a float in an integer context.\n", .{});
            unreachable;
        } else if (self.type != .smallint) {
            std.debug.print("Attempt to use identifier of type \"{s}\" as an integer.\n", .{ @tagName(self.type) });
            unreachable;
        }

        switch (@typeInfo(T)) {
            .int => |int| if (int.bits > index_bits) {
                return @as(T, @intFromFloat(self.toFloat()));
            } else if (self.sign_bit and int.signedness != .signed) {
                unreachable;
            } else return @as(T, @intCast(self.index)),
            else => @compileError(@typeName(T) ++ " is not an integer type.")
        }
    }

    pub inline fn toInt(self: Any, comptime T: type) T {
        if (self.isFloat()) {
            return @as(T, @intFromFloat(self.toFloat()));
        } else return self.toIntStrict(T);
    }

    pub const FloatOp = enum {
        add, sub, mul, div,
    };

    pub inline fn floatOp(self: Any, comptime op: FloatOp, rhs: f64) struct { Any, u1 } {
        const result, const overflow = switch (op) {
            .add => @addWithOverflow(self.toFloat(), rhs),
            .sub => @subWithOverflow(self.toFloat(), rhs),
            .mul => @mulWithOverflow(self.toFloat(), rhs),
            .div => .{ @divTrunc(self.toFloat(), rhs), 0 }
        };

        return .{ fromFloat(result), overflow };
    }

    pub const IntOp = enum {
        add, sub, mul, div,
        ban, bor, bno, bxo,
        shl, shr
    };

    pub inline fn intOp(self: Any, comptime op: IntOp, comptime T: type, rhs: T) struct { Any, u1 } {
        switch (@typeInfo(T)) {
            .int => |int| if (int.bits > index_bits) {
                switch (op) {
                    .add, .sub, .mul, .div => return self.floatOp(std.meta.stringToEnum(FloatOp, @tagName(op)).?, @as(f64, @floatFromInt(rhs))),
                    .shl => {
                        const result, const overflow = @shlWithOverflow(self.toInt(T), rhs);
                        return .{ fromInt(result), overflow };
                    },
                    else => {
                        const lhs: T = self.toInt(T);
                        return .{ fromInt(switch (op) {
                            .ban => lhs & rhs,
                            .bor => lhs | rhs,
                            .bno => ~lhs,
                            .bxo => lhs ^ rhs,
                            .shr => @shrExact(lhs, rhs)
                        }), 0 };
                    }
                }
            } else {
                const lhs: T = self.toIntStrict(T);
                const result, const overflow = switch (op) {
                    .add => @addWithOverflow(lhs, rhs),
                    .sub => @subWithOverflow(lhs, rhs),
                    .mul => @mulWithOverflow(lhs, rhs),
                    .div => .{ @divTrunc(lhs, rhs), 0 },
                    .ban => .{ lhs & rhs, 0 },
                    .bor => .{ lhs | rhs, 0 },
                    .bno => .{ ~lhs, 0 },
                    .bxo => .{ lhs ^ rhs, 0 },
                    .shl => @shlWithOverflow(lhs, rhs),
                    .shr => .{ @shrExact(lhs, rhs), 0 },
                };
                return .{ fromIntStrict(result), overflow };
            },
            else => @compileError(@typeName(T) ++ " is not an integer type.")
        }
    }
};
