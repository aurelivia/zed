const std = @import("std");
const log = std.log.scoped(.zed);
const terminal = @import("terminal");

const root = @import("inner");
const Lexer = root.Lexer;
const buffers = root.buffers;

const Any = root.Lang.Any;
const Expression = root.Lang.Expression;

pub const Cmd = enum {
    q, quit,
    lexdump
};

var gpa: std.heap.GeneralPurposeAllocator(.{}) = .{};
const mem: std.mem.Allocator = gpa.allocator();

pub fn main() !void {
    defer _ = gpa.deinit();

    try root.init(mem);
    defer root.deinit();

    var term: terminal.REPL = try .init(.{
        .mem = mem,
        .prefix = prefix,
        .eval = eval
    });
    defer term.deinit();

    try term.run();
}

fn prefix(interface: *terminal.Interface) std.Io.Writer.Error!void {
    try interface.putChar('>');
    try interface.putChar(' ');
}

fn eval(interface: *terminal.Interface, input: terminal.REPL.Context.Input) terminal.REPL.Context.Error!bool {
    const bytes, _ = input;
    if (bytes.len == 0) return false;
    var start: usize = 0;
    if (std.mem.startsWith(u8, bytes, "repl")) start = 4;

    if (bytes[start] == '.') {
        const cmd_str = std.mem.sliceTo(bytes[(start + 1)..], ' ');

        const cmd: ?Cmd = std.meta.stringToEnum(Cmd, cmd_str);
        if (cmd == null) {
            try interface.print("repl.{s} is not a valid command.\n", .{ cmd_str });
            return false;
        }

        switch (cmd.?) {
            .q, .quit => return true,
            .lexdump => {
                // var reader = std.Io.Reader.fixed(line.items[9..]);
                // var lex: Lexer = .init(&reader);
                // defer lex.deinit();
                // try lex.dump(output);
                // try output.writeByte('\n');
                return false;
            }
        }
    }

    var reader = std.Io.Reader.fixed(bytes[start..]);
    var lex: Lexer = .init(&reader);
    defer lex.deinit();

    const result: Any = try Expression.parse(&lex, null);
    try result.dump(interface, 0);

    return false;
}
