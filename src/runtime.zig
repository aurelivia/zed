const std = @import("std");
const log = std.log.scoped(.zed);
const Allocator = std.mem.Allocator;
const Any = @import("./index.zig").Any;

const ptr_width = @import("builtin").target.ptrBitWidth();
const Width = @Type(std.builtin.Type.int{ .signedness = .unsigned, .bits = ptr_width + 4 });
pub const TaggedPtr = packed struct(Width) {
    float: u1,
    signed: u1,
    bytes: u14,
    ptr: *anyopaque
};

pub const Store = struct {
    const Inner = @import("./store/live.zig").Store(TaggedPtr);
    inner: Inner,

    pub fn deinit(self: *Store, mem: Allocator) void {

    }

    inline fn wrap(mem: Allocator, val: anytype) Allocator.Error!TaggedPtr {

    }

    inline fn unwrap(comptime T: type, tag: TaggedPtr) T {

    }

    pub inline fn create(self: *Store, mem: Allocator, val: anytype) Allocator.Error!Any {

    }

    pub inline fn get(self: *Store, comptime T: type, idx: Any) !T {

    }

    pub fn set(self: *Store, idx: Any, val: anytype) void {
        
    }

    pub fn destroy(self: *Store, mem: Allocator, idx; Any) void {

    }
};

