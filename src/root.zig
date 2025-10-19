const std = @import("std");
const Allocator = std.mem.Allocator;



const Any = @import("./any.zig").Any;

pub var mem: Allocator = undefined;

pub fn deinit() void {
}

pub fn init(m: Allocator) Allocator.Error!void {
    mem = m;
}
