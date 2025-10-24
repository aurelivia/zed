const std = @import("std");
const log = std.log.scoped(.zed);
const Allocator = std.mem.Allocator;
const OOM = error{OutOfMemory};
const term = @import("terminal");

const root = @import("../root.zig");
const buffers = @import("../buffers.zig");
const Lexer = @import("../lexer.zig");

const Any = @import("./any.zig").Any;
const Error = @import("./error.zig");

pub fn parse(lex: *Lexer, double_quote: bool) OOM!Any {
    var scope: Error = .init(lex);
    const parsed = tryParse(&scope, lex, double_quote) catch |e| return Error.parse(&scope, lex, e);
    if (scope.err != null or scope.next != null) return Error.store(scope);
    return parsed;
}

fn tryParse(scope: *Error, lex: *Lexer, double_quote: bool) Error.ParseError!Any {
    var buf = buffers.get(u8);
    errdefer buffers.release(buf);

    while (true) {
        const next = try lex.peek();
        switch (next.val) {
            .eof, .line => return error.UnterminatedString,
            else => scope.advance(lex)
        }
        switch (next.val) {
            .single_quote, .double_quote => if ((next.val == .single_quote and !double_quote) or (next.val == .double_quote and double_quote)) {
                const idx = try root.getOrPutLiteral(buf.items);
                buffers.release(buf);
                return .{ .type = .string, .index = @truncate(idx) };
            } else try buf.append(root.mem, Lexer.Token.toChar(next)),

            .whitespace => |wsp| {
                const slc = try buf.addManyAsSlice(root.mem, wsp);
                @memset(slc, ' ');
            },

            .literal => |l| {
                const slc = try buf.addManyAsSlice(root.mem, l.len);
                @memcpy(slc, l);
            },

            .char => |c| {
                var b: [3]u8 = undefined;
                const len = std.unicode.utf8Encode(c, &b) catch unreachable;
                try buf.appendSlice(root.mem, b[0..len]);
            },

            else => |c| try buf.append(root.mem, Lexer.Token.Value.toChar(c)),
        }
    }
}

pub fn print(writer: *std.Io.Writer, idx: Any) std.Io.Writer.Error!void {
    std.debug.assert(idx.type == .string);
    var reader = root.literals.getReader(idx.index, &[0]u8{});
    defer reader.release();
    while (reader.next()) |byte| try writer.writeByte(byte);
}

pub fn dump(interface: *term.Interface, idx: Any, indent: usize, quotes: bool) std.Io.Writer.Error!void {
    std.debug.assert(idx.type == .literal or idx.type == .string);
    var reader = root.literals.iter(@bitCast(idx.index));
    // defer reader.release();
    try interface.splatByte(' ', indent + 1);
    if (quotes) try interface.putByte('\'');
    while (reader.next()) |byte| {
        const override: ?[]const u8 = switch (byte) {
            '\n' => "\\nl",  '\t' => "\\tb",  0x7F => "\\del", 0x00 => "\\nul",
            0x01 => "\\soh", 0x02 => "\\stx", 0x03 => "\\etx", 0x04 => "\\eot",
            0x05 => "\\enq", 0x06 => "\\ack", 0x07 => "\\bel", 0x08 => "\\bs",
            // 0x09 => "\\ht", 0x0A => "\\lf", 0x0B => "\\vt", 0x0C => "\\ff",
            0x0D => "\\cr",  0x0E => "\\so",  0x0F => "\\si",  0x10 => "\\dle",
            0x11 => "\\dc1", 0x12 => "\\dc2", 0x13 => "\\dc3", 0x14 => "\\dc4",
            0x15 => "\\nak", 0x16 => "\\syn", 0x17 => "\\etb", 0x18 => "\\can",
            0x19 => "\\em",  0x1A => "\\sub", 0x1B => "\\esc", 0x1C => "\\fs",
            0x1D => "\\gs",  0x1E => "\\rs",  0x1F => "\\us",
            else => null
        };

        if (override) |o| {
            try interface.putBytes(o);
            if (reader.peek()) |_| try interface.putByte(' ');
        } else try interface.putByte(byte);
    }
    if (quotes) try interface.putByte('\'');
}
