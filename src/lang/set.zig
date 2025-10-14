const std = @import("std");
const log = std.log.scoped(.zed);
const Module = @import("./module.zig");
const Any = @import("./any.zig").Any;

pub const Store = struct {};

prototype: Any,
merged: Any,
keys: []Any,
values: []Any,

pub fn parse(ctx: *Module, parser: *Parser) Parser.Error!Any {

}

pub fn reduce(ctx: *Module, idx: Any) Any {

}

pub fn compat(ctx: *Module, expected: Any, actual: Any) bool {

}

pub fn apply(ctx: *Module, idx: Any) Any {

}
