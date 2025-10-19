const Lexer = @This();
const std = @import("std");
const log = std.log.scoped(.zed);
const Allocator = std.mem.Allocator;
const OOM = error.OutOfMemory;

const root = @import("./root.zig");
const mem = root.mem;
const buffers = @import("../buffers.zig");

pub const Token = @import("./token.zig");

const Any = @import("./lang/any.zig");
const Error = @import("./lang/error.zig");

pub const LexerError = error {
    ForbiddenWhitespace,
    ForbiddenChar,
    NoEscape,
    UnexpectedChar,

    Utf8InvalidStartByte,
    Utf8CodepointTooLarge,
    Utf8EncodesSurrogateHalf,
    Utf8ExpectedContinuation,
    Utf8OverlongEncoding
} || std.io.Reader.Error
  || std.mem.Allocator.Error;

source: *std.io.Reader,
buffer: std.ArrayList(u8),

context: enum {
    none, start_of_line, escape,
    number_whole, number_frac, number_rep, number_exp
} = .none,
err: ?LexerError = null,
done: bool = false,
pending: ?u32 = null,
peeked: ?Token = null,
queued: ?Token = null,
maybe_line: ?Token = null,

// Lines & Columns are 1-based, however col is incremented by character get, so starts 0
start_line: usize = 1,
start_col: usize = 0,
cur_line: usize = 1,
cur_col: usize = 0,

pub inline fn deinit(self: *Lexer) void {
    buffers.release(self.buffer);
}

pub inline fn init(src: *std.io.Reader) Lexer {
    return .{
        .source = src,
        .buffer = buffers.get(u8)
    };
}

pub inline fn getError(self: *Lexer) OOM!Any {
    return try Error.parse(.{
        .start_line = self.start_line,
        .start_col = self.start_col,
        .end_line = self.cur_line,
        .end_col = self.cur_col
    }, self.err.?);
}

fn nextChar(self: *Lexer) LexerError!u32 {
    if (self.pending) |p| {
        self.pending = null;
        return p;
    }

    self.cur_col += 1;

    const b = self.source.peekByte() catch { return 3; }; // ASCII End-Of-Text, because we can't switch on optionals
    const l = try std.unicode.utf8ByteSequenceLength(b);
    const c = switch (l) {
        4 => try std.unicode.utf8Decode4((try self.source.peekArray(4)).*),
        3 => try std.unicode.utf8Decode3((try self.source.peekArray(3)).*),
        2 => try std.unicode.utf8Decode2((try self.source.peekArray(2)).*),
        else => b
    };
    self.source.toss(l);

    return switch (c) {
        // Forbidden Whitespace
        '\t', 0x0B, 0x00A0, 0x180E, 0x2000...0x200D, 0x202F, 0x205F, 0x2060, 0x2800, 0x3000, 0x3164, 0xFEFF =>
            error.LexerError.ForbiddenWhitespace,
        0x00...0x08, 0x0C, 0x0E...0x1F, 0x7F => error.LexerError.ForbiddenChar,
        else => c
    };
}

pub inline fn peek(self: *Lexer) error{LexerError}!Token {
    return self.tryPeek() catch |e| {
        self.err = e;
        return error.LexerError;
    };
}

pub fn tryPeek(self: *Lexer) LexerError!Token {
    if (self.err) |e| return e;
    if (self.peeked) |p| return p;
    self.peeked = try self.tryNext();
    return self.peeked;
}

pub inline fn toss(self: *Lexer) void {
    if (self.peeked != null) {
        self.peeked = null;
    } else _ = self.tryNext() catch return;
}

pub inline fn next(self: *Lexer) error{LexerError}!Token {
    return self.tryNext() catch |e| {
        self.err = e;
        return error.LexerError;
    };
}

pub fn tryNext(self: *Lexer) LexerError!Token {
    if (self.err) |e| return e;
    if (self.done) unreachable; // Tried to read after already being given .eof

    if (self.peeked) |p| {
        self.peeked = null;
        return p;
    }

    if (self.queued) |val| {
        self.queued = null;
        return val;
    }

    self.buffer.clearRetainingCapacity();

    self.start_line = self.cur_line;
    self.start_col = self.cur_col + 1;

    while (true) {
        const c = try self.nextChar();

        context: switch (self.context) {
            .none => switch (c) {
                3 => {
                    self.done = true;
                    return self.give(.eof);
                },

                // Whitespace
                ' ' => {
                    const wrapped = try self.wrap();
                    var whitespace: usize = 1;
                    loop_whitespace: while (true) {
                        const n = try self.nextChar();
                        self.pending = n;
                        switch (n) {
                            ' ' => whitespace += 1,
                            // Ignore trailing whitespace
                            '\n', '\r' => {
                                whitespace = 0;
                                break :loop_whitespace;
                            },
                            else => break :loop_whitespace
                        }
                    }
                    var w = self.give(.{ .whitespace = whitespace });
                    w.col -|= 1;
                    if (wrapped) |t| {
                        self.queued = w;
                        return t;
                    } else if (whitespace != 0) return w;
                },

                // Newlines
                '\n', '\r' => {
                    const wrapped = try self.wrap();
                    self.maybe_line = self.give(.line);

                    const n = try self.nextChar();
                    // Check next char is not part of a dual \n\r or \r\n separator
                    if ((c == '\r' and n != '\n') or (c == '\n' and n != '\r')) {
                        self.pending = n;
                    }

                    self.context = .start_of_line;
                    if (wrapped) |t| return t;
                },

                // Escapes
                '\\' => {
                    self.context = .escape;
                    if (try self.wrap()) |t| return t;
                },

                // Numeric literals
                '0'...'9' => {
                    // If buffer is empty, this begins a number, otherwise part of literal
                    if (self.buffer.items.len == 0) {
                        self.context = .number_whole;
                        if (c == '0') {
                            const header = self.give(.base_header);
                            const digit = self.parseDigit(c);
                            const n = try self.nextChar();
                            switch (n) {
                                inline 'b', 'o', 'x' => |_n| {
                                    self.queued = self.give(switch (_n) {
                                        'b' => .base_binary,
                                        'o' => .base_octal,
                                        'x' => .base_hex,
                                        else => unreachable
                                    });
                                    return header;
                                },
                                else => { self.pending = n; return digit; }
                            }
                        } else continue :context .number_whole;
                    } else try self.buffer.append(mem, @as(u8, @truncate(c)));
                },

                // Try reserved characters/operators
                else => if (Token.singleton(c)) |s| {
                    if (try self.wrap()) |t| {
                        self.queued = self.give(s);
                        return t;
                    } else return self.give(s);
                } else { // Any other character goes on the literal buffer
                    const bytes: [3]u8 = undefined;
                    const len = try std.unicode.utf8Encode(c, bytes);
                    try self.buffer.appendSlice(mem, bytes[0..len]);
                }
            },

            .start_of_line => switch (c) {
                // Ignore leading whitespace before skip
                ' ' => {},
                // Attempt to process a skip, which is a \ + space + ... at the start of a line
                '\\' => {
                    const n = try self.nextChar();
                    self.pending = n;
                    // If we have a skip, then ignore the newline and all leading whitespace, and the skip
                    switch (n) {
                        ' ' => self.context = .none,
                        else => { self.context = .escape; return self.maybe_line.?; }
                    }
                },
                else => {
                    self.context = .none;
                    self.pending = c;
                    return self.maybe_line.?;
                }
            },

            .escape => switch (c) {
                3 => return LexerError.EndOfStream,
                'x', 'u' => {
                    unreachable;
                },
                else => {
                    self.context = .none;
                    const raw = self.give(.{ .char = c });
                    var n = try self.nextChar();
                    // Any singleton token will end escape context
                    if (Token.singleton(n)) |v| {
                        self.queued = self.give(v);
                        return raw;
                    } else if (n == '\\') {
                        self.context = .escape;
                        return raw;
                    }

                    const f: u21 = toLower(c);
                    const s: u21 = toLower(n);
                    var t: usize = 2;

                    // Otherwise try all the special escapes
                    var char: ?u32 = null;
                    if (f == 'n' and s == 'l') { // Newline (Equivalent to \lf)
                        char = '\n';
                    } else if (f == 's' and s == 'p') { // Space
                        char = ' ';
                    } else if (f == 't' and s == 'b') { // Tab (Equivalent to \ht)
                        char = '\t';
                    } else if (f == 'd' and s == 'e') { // DEL Delete
                        if (toLower(try self.nextChar()) == 'l') char = 0x7F; t = 3;
                    } else if (f == 'n' and s == 'u') { // NUL Null
                        if (toLower(try self.nextChar()) == 'l') char = 0x00; t = 3;
                    } else if (f == 's' and s == 'o') { // SOH Start-Of-Heading
                        if (toLower(try self.nextChar()) == 'h') char = 0x01; t = 3;
                    } else if (f == 's' and s == 't') { // STX Start-Of-Text
                        if (toLower(try self.nextChar()) == 'x') char = 0x02; t = 3;
                    } else if (f == 'e' and s == 't') { // ETX End-Of-Text
                        if (toLower(try self.nextChar()) == 'x') char = 0x03; t = 3;
                    } else if (f == 'e' and s == 'o') { // EOT End-Of-Transmission
                        if (toLower(try self.nextChar()) == 't') char = 0x04; t = 3;
                    } else if (f == 'e' and s == 'n') { // ENQ Enquiry
                        if (toLower(try self.nextChar()) == 'q') char = 0x05; t = 3;
                    } else if (f == 'a' and s == 'c') { // ACK Acknowledge
                        if (toLower(try self.nextChar()) == 'k') char = 0x06; t = 3;
                    } else if (f == 'b' and s == 'e') { // BEL Bell
                        if (toLower(try self.nextChar()) == 'l') char = 0x07; t = 3;
                    } else if (f == 'b' and s == 's') { // BS Backspace
                        char = 0x08;
                    } else if (f == 'h' and s == 't') { // HT Horizontal Tabulation
                        char = 0x09;
                    } else if (f == 'l' and s == 'f') { // LF Line Feed
                        char = 0x0A;
                    } else if (f == 'v' and s == 't') { // VT Vertical Tab
                        char = 0x0B;
                    } else if (f == 'f' and s == 'f') { // FF Form Feed
                        char = 0x0C;
                    } else if (f == 'c' and s == 'r') { // CR Carriage Return
                        char = 0x0D;
                    } else if (f == 's' and s == 'o') { // SO Shift Out
                        char = 0x0E;
                    } else if (f == 's' and s == 'i') { // SI Shift In
                        char = 0x0F;
                    } else if (f == 'd' and s == 'l') { // DLE Data Link Escape
                        if (toLower(try self.nextChar()) == 'e') char = 0x10; t = 3;
                    } else if (f == 'd' and s == 'c') { // DC1 through DC4, Device Control
                        t = 3;
                        switch (try self.nextChar()) {
                            '1' => char = 0x11,
                            '2' => char = 0x12,
                            '3' => char = 0x13,
                            '4' => char = 0x14,
                            else => {}
                        }
                    } else if (f == 'n' and s == 'a') { // NAK Negative Acknowledge
                        if (toLower(try self.nextChar()) == 'k') char = 0x15; t = 3;
                    } else if (f == 's' and s == 'y') { // SYN Synchronous Idle
                        if (toLower(try self.nextChar()) == 'n') char = 0x16; t = 3;
                    } else if (f == 'e' and s == 't') { // ETB End of Transmission Block
                        if (toLower(try self.nextChar()) == 'b') char = 0x17; t = 3;
                    } else if (f == 'c' and s == 'a') { // CAN Cancel
                        if (toLower(try self.nextChar()) == 'n') char = 0x18; t = 3;
                    } else if (f == 'e' and s == 'm') { // EM End of Medium
                        char = 0x19;
                    } else if (f == 's' and s == 'u') { // SUB Substitute
                        if (toLower(try self.nextChar()) == 'b') char = 0x1A; t = 3;
                    } else if (f == 'e' and s == 's') { // ESC Escape
                        if (toLower(try self.nextChar()) == 'c') char = 0x1B; t = 3;
                    } else if (f == 'f' and s == 's') { // FS File Separator
                        char = 0x1C;
                    } else if (f == 'g' and s == 's') { // GS Group Separator
                        char = 0x1D;
                    } else if (f == 'r' and s == 's') { // RS Record Separator
                        char = 0x1E;
                    } else if (f == 'u' and s == 's') { // US Unit Separator
                        char = 0x1F;
                    }

                    if (char) |ch| {
                        var cc = self.give(.{ .char = ch });
                        cc.col = self.cur_col - t;
                        n = try self.nextChar();
                        if (Token.singleton(n)) |v| {
                            self.queued = self.give(v);
                            return cc;
                        } else if (n == '\\') {
                            self.context = .escape;
                            return cc;
                        } else return error.LexerError.NoEscape;
                    } else return error.LexerError.NoEscape;
                }
            },

            .number_whole, .number_frac, .number_rep, .number_exp => switch (c) {
                // We can only get here from a digit, so no confusion with dot
                '.' => if (self.context == .number_whole) {
                    self.context = .number_frac;
                    return self.give(.radix);
                } else return error.LexerError.UnexpectedChar,
                'e' => if (self.context == .number_whole or self.context == .number_frac) {
                    self.context = .number_exp;
                    const n = try self.nextChar();
                    switch (n) {
                        '+', '-' => self.queued = self.give(if (n == '+') .plus else .minus),
                        else => self.pending = n
                    }
                    return self.give(.exponent);
                } else return self.parseDigit(c),
                'r' => if (self.context == .number_whole or self.context == .number_frac) {
                    self.context = .number_rep;
                    return self.give(.repeat);
                } else return error.LexerError.UnexpectedChar,
                '0'...'9', 'A'...'F' => return self.parseDigit(c),
                else => continue :context .none
            },
        }
    }
}

fn give(self: *Lexer, val: Token.Value) Token {
    var t: Token = .{ .val = val, .line = self.cur_line, .col = self.cur_col };
    switch (val) {
        .line => { self.cur_line += 1; self.cur_col = 0; },
        .char => t.col -= 1,
        .whitespace => |w| t.col = t.col - (w -| 1),
        else => {}
    }
    return t;
}

fn wrap(self: *Lexer) LexerError!?Token {
    if (self.buffer.items.len == 0) return null;
    return .{
        .val = .{ .literal = self.buffer.items },
        .line = self.cur_line,
        .col = self.cur_col - (std.unicode.utf8CountCodepoints(self.buffer.items) catch unreachable)
    };
}

fn toLower(c: u21) u21 {
    return switch (c) {
        'A'...'Z' => c ^ 0x20,
        else => c
    };
}

fn parseDigit(self: *Lexer, d: u21) Token {
    return self.give(.{ .digit = switch (d) {
        '0'...'9' => @as(u8, @intCast(d)) ^ 0b00110000,
        else => (@as(u8, @intCast(d)) ^ 0b01000000) + 9
    }});
}

pub fn dump(self: *Lexer, output: *std.Io.Writer) !void {
    try output.writeAll("1: ");
    var buf = [4]u8{ 0, 0, 0, 0 };
    loop: while (true) {
        const token = try self.next();
        switch (token.val) {
            .eof => {
                try output.writeAll("EOF");
                break :loop;
            },

            .whitespace => |w| {
                try output.print("[{}]whitespace({})", .{ token.col, w });
            },

            .literal => |lit| {
                try output.print("[{}]\"", .{ token.col });
                for (lit) |l| {
                    const len = try std.unicode.utf8Encode(@intCast(l), &buf);
                    try output.writeAll(buf[0..len]);
                }
                try output.print("\"({})", .{ lit.len });
            },

            .char => |c| {
                try output.print("[{}]\\", .{ token.col });
                switch (c) {
                    ' ' => try output.writeAll("(␠)"),
                    0x7F => try output.writeAll("(␡)"),
                    0x00...0x1F => {
                        const len = try std.unicode.utf8Encode(@intCast(c ^ 0b10010000000000), &buf);
                        try output.print("({s})", .{ buf[0..len] });
                    },
                    else => {
                        const len = try std.unicode.utf8Encode(@intCast(c), &buf);
                        try output.writeAll(buf[0..len]);
                    }
                }
                try output.print("⟨{X:0>4}⟩", .{ c });
            },

            .digit => try output.print("[{}]{c}", .{ token.col, @as(u8, @intCast(token.toChar())) }),

            .line => {
                try output.print("[{}]line\n{}: ", .{ token.col, token.line + 1 });
                continue :loop;
            },

            else => |v| try output.print("[{}]{s}", .{ token.col, @tagName(v) })
        }

        try output.writeAll(", ");
    }
}

pub fn debugDump(self: *Lexer) void {
    var buf: [4096]u8 = undefined;
    const stderr = std.debug.lockStderrWriter(&buf);
    defer std.debug.unlockStderrWriter();
    self.dump(stderr) catch return;
}

pub fn printChar(c: u32, output: *std.io.Writer) !void {
    var buf = [4]u8{ 0, 0, 0, 0 };
    const len = try std.unicode.utf8Encode(@intCast(c), &buf);
    try output.writeAll(buf[0..len]);
}

pub fn debugPrintChar(c: u32) void {
    var buf: [4]u8 = undefined;
    const stderr = std.debug.lockStderrWriter(&buf);
    defer std.debug.unlockStderrWriter();
    nosuspend printChar(c, stderr) catch return;
}

pub fn debugPrintString(str: []const u32) void {
    var buf: [4]u8 = undefined;
    const stderr = std.debug.lockStderrWriter(&buf);
    defer std.debug.unlockStderrWriter();
    for (str) |c| printChar(c, stderr) catch return;
}

pub fn debugEncodeString(comptime str: []const u8) [std.unicode.utf8CountCodepoints(str) catch unreachable]u32 {
    var encoded: [std.unicode.utf8CountCodepoints(str) catch unreachable]u32 = undefined;
    var view = std.unicode.Utf8View.initComptime(str).iterator();
    var i: usize = 0;
    while (view.nextCodepoint()) |c| { encoded[i] = @intCast(c); i += 1; }
    return encoded;
}

pub fn createTestLexer(comptime src: []const u8) std.mem.Allocator.Error!*Lexer {
    const reader: *std.io.Reader = try std.testing.allocator.create(std.io.Reader);
    reader.* = std.io.Reader.fixed(src);
    const lexer: *Lexer = try std.testing.allocator.create(Lexer);
    lexer.* = try .init(std.testing.allocator, reader);
    return lexer;
}

pub fn destroyTestLexer(lexer: *Lexer) void {
    std.testing.allocator.destroy(lexer.source);
    lexer.deinit();
    std.testing.allocator.destroy(lexer);
}
