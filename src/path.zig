const std = @import("std");
const log = std.log.scoped(.zed);
const Module = @import("./module.zig");
const Any = @import("./any.zig").Any;

pub const Path = packed struct(Any.width * 2) {
    pub const Store = @import("./store/live.zig").Store(Path);

    name: Any,
    next: Any,

    pub fn reduce(ctx: *Module, idx: Any) Any {

    }

    pub fn apply(ctx: *Module, idx: Any) Any {

    }
};
