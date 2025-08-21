const std = @import("std");
const Lexer = @import("self").Lexer;

var gpa: std.heap.GeneralPurposeAllocator(.{}) = .{};
pub const mem: std.mem.Allocator = gpa.allocator();

pub fn main() !void {
    var args = std.process.args();
    _ = args.skip();

    defer _ = gpa.deinit();
    var arena: std.heap.ArenaAllocator = .init(mem);
    defer arena.deinit();

    const path = args.next().?;
    const src = try std.fs.openFileAbsolute(path, .{ .mode = .read_only });
    defer src.close();

    var lexer: Lexer = try .init(arena.allocator(), src.reader());

    const stdout = std.io.getStdOut().writer();

    try lexer.dump(stdout);
}
