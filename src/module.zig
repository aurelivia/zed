const std = @import("std");
const log = std.log.scoped(.zed);
const Allocator = std.mem.Allocator;

const Any = @import("./any.zig").Any;
const Builtin = @import("./builtin.zig");
const Literal = @import("./literal.zig");
const Path = @import("./path.zig").Path;
const Expression = @import("./expression.zig").Expression;
const Lambda = @import("./lambda.zig").Lambda;
const Set = @import("./set.zig");
const List = @import("./list.zig");

pub const Stack = struct {
    const Named = struct { Any, Any };
    mem: Allocator,
    inner: std.ArrayList(Named),

    pub inline fn deinit(self: *Stack) void {
        self.inner.deinit(self.mem);
    }

    pub inline fn push(self: *Stack, named: Named) void {
        self.inner.append(self.mem, named);
    }

    pub inline fn pop(self: *Stack) Named {
        return self.inner.pop();
    }
};

stack: Stack,
heap: Runtime.Store,
literals: Literal.Store,
paths: Path.Store,
expressions: Expression.Store,
lambdas: Lambda.Store,
sets: Set.Store,
lists: List.Store,

pub fn deinit(self: *@This()) void {
    self.stack.deinit();
    self.heap.deinit();
    self.literals.deinit();
    self.paths.deinit();
    self.expressions.deinit();
    self.lambdas.deinit();
    self.sets.deinit();
    self.lists.deinit();
}
