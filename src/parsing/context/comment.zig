const ParseContext = @import("../parse_context.zig");
const ParseError = ParseContext.ParseError;

pub fn parse(ctx: *ParseContext) ParseError!void {
    while (true) {
        const n = ctx.next();
        switch (n) {
            .eof, .semicolon, .line => return,
            else => {}
        }
    }
}
