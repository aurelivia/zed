const std = @import("std");
const Token = @import("./token.zig");

const Self = @This();

pub const LexerError = error {
    ForbiddenWhitespace,
    NoEscape,
    UnexpectedChar,

    Utf8InvalidStartByte,
    Utf8CodepointTooLarge,
    Utf8EncodesSurrogateHalf,
    Utf8ExpectedContinuation,
    Utf8OverlongEncoding
} || std.io.Reader.Error
  || std.mem.Allocator.Error;

mem: std.mem.Allocator,
source: *std.io.Reader,
context: enum {
    none, start_of_line, escape,
    number_whole, number_frac, number_rep, number_exp
} = .none,
buffer: std.ArrayList(u21) = .empty,
err: ?LexerError = null,

done: bool = false,
pending: ?u21 = null,
peeked: ?Token = null,
queued: ?Token = null,
maybe_line: ?Token = null,
// Lines & Columns are 1-based, however col is incremented by character get, so starts 0
line: usize = 1,
col: usize = 0,

pub inline fn deinit(self: *Self) void {
    self.buffer.deinit(self.mem);
}

pub inline fn init(mem: std.mem.Allocator, src: *std.io.Reader) !Self {
    return .{ .mem = mem, .source = src };
}

pub fn fail(self: *Self, e: LexerError) LexerError {
    self.err = e;
    return e;
}

fn nextChar(self: *Self) LexerError!u21 {
    if (self.pending) |p| {
        self.pending = null;
        return p;
    }

    self.col += 1;

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
        '\t', 0x00A0, 0x180E, 0x2000...0x200D, 0x202F, 0x205F, 0x2060, 0x2800, 0x3000, 0x3164, 0xFEFF =>
            self.fail(LexerError.ForbiddenWhitespace),
        else => c
    };
}

pub fn peek(self: *Self) LexerError!Token {
    if (self.err) |e| return e;
    if (self.peeked) |p| return p;
    self.peeked = try self.next();
    return self.peeked;
}

pub inline fn drop(self: *Self) void {
    if (self.peeked) self.peeked = null;
}

pub inline fn skip(self: *Self) !void {
    if (self.peeked) {
        self.peeked = null;
    } else _ = try self.next();
}

pub fn next(self: *Self) LexerError!Token {
    if (self.err) |e| return e;
    if (self.done) return LexerError.EndOfStream;

    if (self.peeked) |p| {
        self.peeked = null;
        return p;
    }

    if (self.queued) |val| {
        self.queued = null;
        return val;
    }

    self.buffer.clearRetainingCapacity();

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
                    } else try self.buffer.append(self.mem, c);
                },

                // Try reserved characters/operators
                else => if (Token.singleton(c)) |s| {
                    if (try self.wrap()) |t| {
                        self.queued = self.give(s);
                        return t;
                    } else return self.give(s);
                } else { // Any other character goes on the literal buffer
                    try self.buffer.append(self.mem, c);
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
                    var char: ?u21 = null;
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
                        cc.col = self.col - t;
                        n = try self.nextChar();
                        if (Token.singleton(n)) |v| {
                            self.queued = self.give(v);
                            return cc;
                        } else if (n == '\\') {
                            self.context = .escape;
                            return cc;
                        } else return self.fail(LexerError.NoEscape);
                    } else return self.fail(LexerError.NoEscape);
                }
            },

            .number_whole, .number_frac, .number_rep, .number_exp => switch (c) {
                // We can only get here from a digit, so no confusion with dot
                '.' => if (self.context == .number_whole) {
                    self.context = .number_frac;
                    return self.give(.radix);
                } else return self.fail(LexerError.UnexpectedChar),
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
                } else return self.fail(LexerError.UnexpectedChar),
                '0'...'9', 'A'...'F' => return self.parseDigit(c),
                else => continue :context .none
            },
        }
    }
}

inline fn give(self: *Self, val: Token.Value) Token {
    var t: Token = .{ .val = val, .line = self.line, .col = self.col };
    switch (val) {
        .line => { self.line += 1; self.col = 0; },
        .char => t.col -= 1,
        .whitespace => |w| t.col = t.col - (w -| 1),
        else => {}
    }
    return t;
}

inline fn wrap(self: *Self) LexerError!?Token {
    if (self.buffer.items.len == 0) return null;
    return .{
        .val = .{ .literal = self.buffer.items },
        .line = self.line,
        .col = self.col - self.buffer.items.len
    };
}

inline fn toLower(c: u21) u21 {
    return switch (c) {
        'A'...'Z' => c ^ 0x20,
        else => c
    };
}

inline fn parseDigit(self: *Self, d: u21) Token {
    return self.give(.{ .digit = switch (d) {
        '0'...'9' => @as(u8, @intCast(d)) ^ 0b00110000,
        else => (@as(u8, @intCast(d)) ^ 0b01000000) + 9
    }});
}

pub fn formatError(self: *Self) []const u8 {
    switch (self.errored) {
        else => unreachable,
    }
}

pub fn dump(self: *Self, output: *std.Io.Writer) !void {
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
                    const len = try std.unicode.utf8Encode(l, &buf);
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
                        const len = try std.unicode.utf8Encode(c ^ 0b10010000000000, &buf);
                        try output.print("({s})", .{ buf[0..len] });
                    },
                    else => {
                        const len = try std.unicode.utf8Encode(c, &buf);
                        try output.writeAll(buf[0..len]);
                    }
                }
                try output.print("⟨{X:0>4}⟩", .{ c });
            },

            .digit => try output.print("[{}]{}", .{ token.col, token.toChar() }),

            .line => {
                try output.print("[{}]line\n{}: ", .{ token.col, token.line + 1 });
                continue :loop;
            },

            else => |v| try output.print("[{}]{s}", .{ token.col, @tagName(v) })
        }

        try output.writeAll(", ");
    }
}

fn printChar(c: u21, output: *std.io.Writer) !void {
    var buf = [4]u8{ 0, 0, 0, 0 };
    const len = try std.unicode.utf8Encode(c, &buf);
    try output.writeAll(buf[0..len]);
}

fn debugPrintChar(c: u21) void {
    var buf: [4]u8 = undefined;
    const stderr = std.debug.lockStderrWriter(&buf);
    defer std.debug.unlockStderrWriter();
    nosuspend printChar(c, stderr) catch return;
}

