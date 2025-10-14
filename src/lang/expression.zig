const std = @import("std");
const log = std.log.scoped(.zed);
const Allocator = std.mem.Allocator;
const Module = @import("./module.zig");
const Any = @import("./any.zig").Any;

pub const Expression = packed struct(Any.width * 2) {
    pub const Store = struct {
        const shift = @typeInfo(usize).int.bits;
        pub const Flat = @Type(std.builtins.Type.int{ .signedness = .unsigned, .bits = shift * 2 });
        pub const Inner = @import("olib-collections").Table(Flat);
        inner: Inner,

        pub fn deinit(self: *Store, mem: Allocator) void {
            self.inner.deinit(mem);
        }

        const idx_mask: Any.Index = b: {
            const gen_bits = @typeInfo(Inner.Key.Generation).int.bits;
            break :b std.math.maxInt(Any.Index) >> gen_bits;
        };
        const gen_mask: Any.Index = ~idx_mask;

        pub inline fn fixKey(idx: Any) Inner.Key {
            return .{ .generation = idx.index & gen_mask, .index = idx.index & idx_mask };
        }

        pub inline fn flatten(exp: Expression) Flat {
            return (@as(Flat, @intCast(exp.left)) << shift) | @as(Flat, @intCast(exp.right));
        }

        pub inline fn expand(flt: Flat) Expression {
            return .{ .left = @truncate(flt >> shift), .right = @truncate(flt) };
        }

        pub inline fn create(self: *Store, exp: Expression) Allocator.Error!void {
            return try self.inner.create(flatten(exp));
        }

        pub inline fn get(self: *Store, idx: Any) ?Expression {
            return if (self.inner.get(fixKey(idx))) |flt| expand(flt) else null;
        }

        pub inline fn set(self: *Store, idx: Any, exp: Expression) void {
            self.inner.set(fixKey(idx), flatten(exp));
        }

        pub inline fn destroy(self: *Store, idx: Any) void {
            self.inner.destroy(fixKey(idx));
        }
    };

    left: Any,
    right: Any,

    pub fn parse(ctx: *Module, parser: *Parser) Parser.Error!Any {

    }

    pub fn reduce(ctx: *Module, idx: Any) Any {

    }

    pub fn apply(ctx: *Module, idx: Any) Any {

    }
};
