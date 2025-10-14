const std = @import("std");
const log = std.log.scoped(.zed);
const Allocator = std.mem.Allocator;
const Module = @import("./module.zig");
const Any = @import("./any.zig").Any;

pub const Literal = packed struct (usize) {
    pub const Store = struct {};

    pub fn parse(ctx: *Module, parser: *Parser) Parser.Error!Any {

    }

    pub fn reduce(ctx: *Module, idx: Any) Any {

    }

    pub fn compat(ctx: *Module, expected: Any, actual: Any) bool {

    }

    pub fn apply(ctx: *Module, idx: Any) Any {

    }
};

