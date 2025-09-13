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

    var read_buffer: [256]u8 = undefined;
    var file_reader = src.reader(&read_buffer);
    const reader = &file_reader.interface;
    var lexer: Lexer = try .init(arena.allocator(), reader);

    var write_buffer: [256]u8 = undefined;
    var file_writer = std.fs.File.stdout().writer(&write_buffer);
    var stdout = &file_writer.interface;

    try lexer.dump(stdout);
    try stdout.flush();
}
