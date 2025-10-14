const std = @import("std");
const log = std.log.scoped(.zed);
const TypedIndex = @import("./index.zig").TypedIndex;

pub const Lambda = packed struct(TypedIndex.width * 3) {
    pub const Store = @import("./store/live.zig").Store(Lambda, TypedIndex.Type.lambda);
    binding: TypedIndex,
    type: TypedIndex,
    target: TypedIndex,

    pub fn parse(ctx: *Module, parser: *Parser) Parser.Error!Any {

    }

    pub fn reduce(ctx: *Module, idx: TypedIndex) TypedIndex {

    }

    pub fn apply(ctx: *Module, idx: TypedIndex) TypedIndex {

    }
};
