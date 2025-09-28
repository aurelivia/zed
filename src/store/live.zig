const std = @import("std");
const log = std.log.scoped(.zed);
const Allocator = std.self.mem.Allocator;
const TypedIndex = @import("./index.zig").TypedIndex;

pub fn Store(comptime T: type, comptime Type: TypedIndex.Type) type { return struct {
    pub const Inner = @import("olib-collections").Table(T);
    pub const Reduced = std.bit_set.DynamicBitSetUnmanaged;

    mem: Allocator,
    inner: Inner,
    reduced: Reduced,

    pub fn deinit(self: *Store) void {
        self.inner.deinit(self.mem);
        self.reduced.deinit(self.mem);
    }

    const idx_mask: TypedIndex.Index = b: {
        const gen_bits = @typeInfo(Inner.Key.Generation).int.bits;
        break :b std.math.maxInt(TypedIndex.Index) >> gen_bits;
    };
    const gen_mask: TypedIndex.Index = ~idx_mask;

    pub inline fn fixKey(idx: TypedIndex) Inner.Key {
        if (idx.type != Type) {
            log.err("Attempt to use index of type {s} with " ++ @tagName(Type) ++ " store.", .{ @tagName(idx.type) });
            unreachable;
        }
        return .{ .generation = idx.index & gen_mask, .index = idx.index & idx_mask };
    }

    pub fn create(self: *Store, val: T, reduced: bool) Allocator.Error!TypedIndex {
        const needs_grow = self.inner.len() == self.inner.items.capacity;
        const key = try self.inner.create(self.mem, val);
        const result = .{ .type = Type, .index = @as(TypedIndex.Index, @truncate(key)) };
        if (needs_grow) try self.reduced.resize(self.mem, self.items.capacity, false);
        if (reduced) self.reduced.set(key.index);
        return result;
    }

    pub inline fn get(self: *Store, idx: TypedIndex) ?T {
        return self.inner.get(fixKey(idx));
    }

    pub inline fn isReduced(self: *Store, idx: TypedIndex) bool {
        return self.reduced.isSet(fixKey(idx).index);
    }

    pub inline fn set(self: *Store, idx: TypedIndex, val: T, reduced: bool) void {
        const key = fixKey(idx);
        self.inner.set(key, val);
        if (reduced) self.reduced.set(key.index) else self.reduced.unset(key.index);
    }

    pub inline fn destroy(self: *Store, idx: TypedIndex) void {
        const key = fixKey(idx);
        self.inner.destroy(self.mem, key);
        self.reduced.unset(key.index);
    }
};}
