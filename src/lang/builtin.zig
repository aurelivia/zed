const std = @import("std");
const log = std.log.scoped(.zed);
const Module = @import("./module.zig");
const Any = @import("./index.zig").Any;

pub const Builtin = enum (usize) {
    unevaluated = 0,
    nil = 1,

    pub fn parse(ctx: *Module, parser: *Parser) Parser.Error!Any {

    }

    pub fn reduce(ctx: *Module, idx: Any) Any {

    }

    pub fn compat(ctx: *Module, expected: Any, actual: Any) bool {

    }

    pub fn apply(ctx: *Module, idx: Any) Any {

    }
};

