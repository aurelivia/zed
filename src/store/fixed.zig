const std = @import("std");

pub fn Store(comptime T: type) type { return struct {
    pub const Pivot = struct {
        value: []const T,
        index: ?usize = null,
        left: ?*Pivot = null,
        right: ?*Pivot = null,

        pub fn deinit(self: *Pivot, mem: std.mem.Allocator) void {
            if (self.left) |l| { l.deinit(mem); mem.destroy(l); }
            if (self.right) |r| { r.deinit(mem); mem.destroy(r); }
        }
    };

    mem: std.mem.Allocator,
    lits: std.ArrayList([]const T) = .empty,
    clean: std.DynamicBitSetUnmanaged = .{},
    root: ?*Pivot = null,
    // nums: std.ArrayList(),

    pub fn deinit(self: *@This()) void {
        if (self.root) |r| { r.deinit(self.mem); self.mem.destroy(r); }
        for (self.lits.items, 0..) |l, i| { if (self.clean.isSet(i)) self.mem.free(l); }
        self.clean.deinit(self.mem);
        self.lits.deinit(self.mem);
        // self.nums.deinit(self.mem);
    }

    fn append(self: *@This(), lit: []const T, managed: bool) std.mem.Allocator.Error!usize {
        const index: usize = self.lits.items.len;
        try self.lits.append(self.mem, lit);
        if (self.clean.bit_length < self.lits.capacity)
            try self.clean.resize(self.mem, self.lits.capacity, false);
        self.clean.setValue(index, managed);
        return index;
    }

    fn makePivot(self: *@This(), lit: []const T) std.mem.Allocator.Error!*Pivot {
        const clone = try self.mem.alloc(T, lit.len);
        @memcpy(clone, lit);
        const pivot = try self.mem.create(Pivot);
        pivot.* = .{
            .value = clone,
            .index = try self.append(clone, true)
        };
        return pivot;
    }

    pub fn getOrPut(self: *@This(), lit: []const T) std.mem.Allocator.Error!usize {
        if (self.root == null) {
            self.root = try self.makePivot(lit);
            return self.root.?.index.?;
        }

        var root: *Pivot = self.root.?;
        var parent: ?*Pivot = null;
        var upper: bool = false;
        var index: usize = 0;
        outer: while (true) {
            const min: usize = @min(root.value.len, lit.len);
            // Attempt to find a common prefix between root.value and lit
            const order: std.math.Order = while (index < min): (index += 1) {
                const cmp = std.math.order(root.value[index], lit[index]);
                if (cmp != .eq) break cmp;
            // Fallthroughs in the event that one is entirely contained within the other
            } else if (lit.len < root.value.len) { // lit is a prefix of root.value
                // Test: Swap Prefixes
                const prefix = root.value[0..index];
                const pivot = try self.mem.create(Pivot);
                pivot.* = .{
                    .value = prefix,
                    .index = try self.append(prefix, false),
                    .left = root
                };
                if (parent) |p| {
                    if (upper) p.right = pivot else p.left = pivot;
                } else self.root = pivot;
                return pivot.index.?;
            } else if (lit.len > root.value.len) { // root.value is a prefix of lit
                @branchHint(.likely);
                if (root.left) |l| {
                    if (root.right) |r| {
                        @branchHint(.likely);
                        const left, const parent_left = getBound(l, index, true);
                        switch (std.math.order(left.value[index], lit[index])) {
                            .gt => {
                                parent = root;
                                root = l; upper = false;
                                continue :outer;
                            },
                            .eq => {
                                index += 1;
                                parent = parent_left orelse root;
                                root = left; upper = false;
                                continue :outer;
                            },
                            else => {}
                        }
                        const right, const parent_right = getBound(r, index, false);
                        switch (std.math.order(right.value[index], lit[index])) {
                            .lt => {
                                parent = root;
                                root = r; upper = true;
                                continue :outer;
                            },
                            .eq => {
                                index += 1;
                                parent = parent_right orelse root;
                                root = right; upper = true;
                                continue :outer;
                            },
                            else => {}
                        }
                        parent = root;
                        const mid: T = (left.value[index] + right.value[index]) / 2;
                        if (std.math.order(mid, lit[index]) == .lt) {
                            root = r; upper = true;
                        } else { root = l; upper = false; }
                        continue :outer;
                    } else if (l.value.len == index or (std.math.order(l.value[index], lit[index]) == .lt)) {
                        // Test: Append on One, Greater
                        root.right = try self.makePivot(lit);
                        return root.right.?.index.?;
                    } else root.right = l; // Test: Append on One, Lesser
                }
                // Test: Append on Zero
                root.left = try self.makePivot(lit);
                return root.left.?.index.?;
            } else { // exact match
                // Test: Add to Existing
                if (root.index == null) root.index = try self.append(root.value, false);
                return root.index.?;
            };

            // root.value and lit have a common prefix
            // Test: Create Common Prefix
            const prefix = root.value[0..index];
            const pivot = try self.makePivot(lit);
            const new_root = try self.mem.create(Pivot);
            new_root.* = .{
                .value = prefix,
                .left = if (order == .lt) root else pivot,
                .right = if (order == .gt) root else pivot
            };
            if (parent) |p| {
                if (upper) p.right = new_root else p.left = new_root;
            } else self.root = new_root;
            return pivot.index.?;
        }
    }

    fn getBound(start: *Pivot, index: usize, max: bool) struct { *Pivot, ?*Pivot } {
        var parent: ?*Pivot = null;
        var node: *Pivot = start;
        while (true) {
            if (node.value.len != index) return .{ node, parent };
            parent = node;
            if (node.left) |l| {
                if (node.right) |r| {
                    node = if (max) r else l;
                } else node = l;
            } else unreachable;
        }
    }
};}

const ByteStore = Store(u8, AutoContext(u8));

test "Store: Empty" {
    var store: ByteStore = .{ .mem = std.testing.allocator };
    defer store.deinit();

    try std.testing.expectEqual(0, try store.getOrPut("a"));
    try std.testing.expectEqual(1, store.lits.items.len);
    try std.testing.expectEqual(store.lits.capacity, store.clean.bit_length);
    try std.testing.expect(store.clean.isSet(0));
    try std.testing.expectEqualStrings(store.lits.items[0], "a");
    try std.testing.expect(store.root != null);
    try std.testing.expectEqualDeep(ByteStore.Pivot {
        .value = "a",
        .index = 0,
        .left = null,
        .right = null
    }, store.root.?.*);
}

test "Store: Append on Zero" {
    var store: ByteStore = .{ .mem = std.testing.allocator };
    defer store.deinit();

    _ = try store.getOrPut("a");
    try std.testing.expectEqual(1, try store.getOrPut("ab"));
    try std.testing.expectEqualDeep(&[_]([]const u8){ "a", "ab" }, store.lits.items);
    try std.testing.expect(store.root.?.left != null);
    try std.testing.expectEqualDeep(ByteStore.Pivot {
        .value = "ab",
        .index = 1
    }, store.root.?.left.?.*);
}

test "Store: Append on One, Greater" {
    var store: ByteStore = .{ .mem = std.testing.allocator };
    defer store.deinit();

    _ = try store.getOrPut("a");
    _ = try store.getOrPut("ab");
    try std.testing.expectEqual(2, try store.getOrPut("ac"));
    try std.testing.expectEqualDeep(&[_]([]const u8){ "a", "ab", "ac" }, store.lits.items);
    try std.testing.expectEqualDeep(ByteStore.Pivot {
        .value = "ab",
        .index = 1
    }, store.root.?.left.?.*);
    try std.testing.expectEqualDeep(ByteStore.Pivot {
        .value = "ac",
        .index = 2
    }, store.root.?.right.?.*);
}

test "Store: Append on One, Lesser" {
    var store: ByteStore = .{ .mem = std.testing.allocator };
    defer store.deinit();

    _ = try store.getOrPut("a");
    _ = try store.getOrPut("ab");
    try std.testing.expectEqual(2, try store.getOrPut("aa"));
    try std.testing.expectEqualDeep(&[_]([]const u8){ "a", "ab", "aa" }, store.lits.items);
    try std.testing.expectEqualDeep(ByteStore.Pivot {
        .value = "aa",
        .index = 2
    }, store.root.?.left.?.*);
    try std.testing.expectEqualDeep(ByteStore.Pivot {
        .value = "ab",
        .index = 1
    }, store.root.?.right.?.*);
}

test "Store: Create Common Prefix" {
    var store: ByteStore = .{ .mem = std.testing.allocator };
    defer store.deinit();

    _ = try store.getOrPut("ab");
    _ = try store.getOrPut("ac");
    try std.testing.expectEqualDeep(&[_]([]const u8){ "ab", "ac" }, store.lits.items);
    try std.testing.expectEqual(2, store.lits.items.len);
    try std.testing.expectEqualStrings("a", store.root.?.value);
    try std.testing.expectEqual(null, store.root.?.index);
    try std.testing.expectEqualDeep(ByteStore.Pivot {
        .value = "ab",
        .index = 0
    }, store.root.?.left.?.*);
    try std.testing.expectEqualDeep(ByteStore.Pivot {
        .value = "ac",
        .index = 1
    }, store.root.?.right.?.*);
}

test "Store: Add to Existing" {
    var store: ByteStore = .{ .mem = std.testing.allocator };
    defer store.deinit();

    _ = try store.getOrPut("ab");
    _ = try store.getOrPut("ac");
    _ = try store.getOrPut("a");
    try std.testing.expectEqualDeep(&[_]([]const u8){ "ab", "ac", "a" }, store.lits.items);
    try std.testing.expectEqualStrings("a", store.root.?.value);
    try std.testing.expectEqual(2, store.root.?.index);
}

test "Store: Swap Prefixes" {
    var store: ByteStore = .{ .mem = std.testing.allocator };
    defer store.deinit();
    _ = try store.getOrPut("ab");
    _ = try store.getOrPut("a");
    try std.testing.expectEqualDeep(&[_]([]const u8){ "ab", "a" }, store.lits.items);
    try std.testing.expectEqualStrings("a", store.root.?.value);
    try std.testing.expectEqual(1, store.root.?.index);
    try std.testing.expectEqualDeep(ByteStore.Pivot {
        .value = "ab",
        .index = 0
    }, store.root.?.left.?.*);
}

test "Store: Fill" {
    var store: ByteStore = .{ .mem = std.testing.allocator };
    defer store.deinit();
    _ = try store.getOrPut("aa");
    _ = try store.getOrPut("ab");
    _ = try store.getOrPut("cc");
    _ = try store.getOrPut("dd");
    try std.testing.expectEqualDeep(&[_]([]const u8){ "aa", "ab", "cc", "dd" }, store.lits.items);
    try std.testing.expectEqualStrings("", store.root.?.value);
    try std.testing.expectEqual(null, store.root.?.index);
    const left = store.root.?.left.?;
    try std.testing.expectEqualStrings("a", left.value);
    try std.testing.expectEqual(null, left.index);
    try std.testing.expectEqualDeep(ByteStore.Pivot {
        .value = "aa",
        .index = 0
    }, left.left.?.*);
    try std.testing.expectEqualDeep(ByteStore.Pivot {
        .value = "ab",
        .index = 1
    }, left.right.?.*);
    const right = store.root.?.right.?;
    try std.testing.expectEqualStrings("", right.value);
    try std.testing.expectEqual(null, right.index);
    try std.testing.expectEqualDeep(ByteStore.Pivot {
        .value = "cc",
        .index = 2
    }, right.left.?.*);
    try std.testing.expectEqualDeep(ByteStore.Pivot {
        .value = "dd",
        .index = 3
    }, right.right.?.*);
}
