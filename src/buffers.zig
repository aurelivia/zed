const std = @import("std");
const log = std.log.scoped(.zed);
const Allocator = std.mem.Allocator;

const root = @import("./root.zig");

const Buffer = std.ArrayList(u8);

var mut: std.Thread.Mutex = .{};
var pool: std.ArrayList(?Buffer) = .empty;

pub fn deinit() void {
    mut.lock();
    defer mut.unlock();
    for (pool.items) |maybe_buf| {
        if (maybe_buf) |*buf| @constCast(buf).deinit(root.mem);
    }
    pool.deinit(root.mem);
}

pub fn get(comptime Elem: type) std.ArrayList(Elem) {
    mut.lock();
    defer mut.unlock();
    var min: ?usize = null;
    for (pool.items, 0..) |maybe_buf, i| {
        if (maybe_buf) |buf| {
            if (min) |m| {
                if (buf.capacity < pool.items[m].?.capacity) min = i;
            } else min = i;
        }
    }

    const buf: Buffer = if (min) |m| b: {
        const buf = pool.items[m];
        pool.items[m] = null;
        break :b buf.?;
    } else .empty;

    return .{
        .items = @as(std.ArrayList(Elem).Slice, @ptrCast(buf.items)),
        .capacity = @divExact(buf.capacity, @sizeOf(Elem))
    };
}

pub fn release(buf: anytype) void {
    const Elem = @typeInfo(@TypeOf(buf).Slice).pointer.child;

    var bytes: Buffer = .{
        .items = @as(Buffer.Slice, @ptrCast(buf.items)),
        .capacity = buf.capacity * @sizeOf(Elem)
    };

    mut.lock();
    defer mut.unlock();
    bytes.clearRetainingCapacity();
    for (pool.items, 0..) |maybe_buf, i| {
        if (maybe_buf == null) { pool.items[i] = bytes; return; }
    } else pool.append(root.mem, bytes) catch bytes.deinit(root.mem);
}
