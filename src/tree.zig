const std = @import("std");
const Number = @import("./number.zig");

pub const Tree = extern struct {
    pub const Branch = extern union {
        pub const Tagged = struct { Kind, Branch };

        pub const Kind = enum (u8) {
            tree = 0,
            literal = 1,
            char = 2,
            unit_set = 3,
            unit_list = 4
        };

        tree: *Tree,
        literal: usize,
        char: u32,
        unit_set: void,
        unit_list: void,
    };

    pub const Meta = extern struct {
        pub const Op = enum (u8) {
            apply = 0,
            bind = 1,
            define = 2,
            join = 3,
            cons = 4,
            let = 5
        };

        op: Op,
        left: Branch.Kind,
        right: Branch.Kind
    };

    meta: Meta,
    left: Branch,
    right: Branch
};

test "Tree Packing" {
    const ptr_size = @sizeOf(*usize);
    try std.testing.expect(@sizeOf(Tree.Branch) <= ptr_size);
    try std.testing.expect(@sizeOf(Tree.Meta) <= ptr_size);
    try std.testing.expect(@sizeOf(Tree) <= ptr_size * 3);
}
