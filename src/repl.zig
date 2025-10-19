const std = @import("std");
const log = std.log.scoped(.zed);

const root = @import("./root.zig");
const mem = root.mem;

const Module = @import("./module.zig");

pub const Cmd = enum {
    q, quit
};

pub fn main() !void {
    var input_buffer: [4096]u8 = undefined;
    var stdin = std.fs.File.stdin().reader(&input_buffer);
    const input = &stdin.interface;
    var output_buffer: [4096]u8 = undefined;
    var stdout = std.fs.File.stdout().writer(&output_buffer);
    const output = &stdout.interface;

    var module: Module = .init();
    defer module.deinit();

    loop: while (true) {
        try output.flush();
        var line = try input.takeDelimiterExclusive('\n');
        if (line.len == 0) continue :loop;

        if (std.mem.startsWith(u8, line, "repl")) line = line[4..];

        if (line[0] == '.') {
            const cmd_str = std.mem.sliceTo(line[1..], ' ');
            if (cmd_str.len == 0) {
                try output.writeAll("syntax error\n");
                continue :loop;
            }

            const cmd: ?Cmd = std.meta.stringToEnum(Cmd, cmd_str);
            if (cmd == null) {
                try output.print("repl.{s} is not a valid command.\n", .{ cmd_str });
                continue :loop;
            }

            switch (cmd.?) {
                .q, .quit => break :loop
            }
        }

        try output.writeAll(line);
        try output.writeByte('\n');
    }

    try output.flush();
}
