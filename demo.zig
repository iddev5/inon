const std = @import("std");
const Inon = @import("src/lib.zig").Inon;
const ParseError = @import("src/lib.zig").Parser.ParseError;

pub fn main() anyerror!void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = &gpa.allocator;

    var writer = std.io.getStdOut().writer();

    var inon = Inon.init(
    \\no = 12345;
    \\hi = "hello" ++ " world!";
    \\test = [10, 20, "test"];
    \\map = {
    \\ x = 20;
    \\ y = "inon " ++ global.hi;
    \\ z = {
    \\  x = [10, 123, "hello"];
    \\ };
    \\};
    , allocator, &writer);
    defer inon.free();

    inon.parser.parse() catch |err| {
        if (inon.parser.getErrorContext()) |error_context| {
            switch (error_context.err) {
                ParseError.invalid_operator => std.debug.print("line {}: invalid operator\n", .{error_context.line}),
                ParseError.mismatched_operands => std.debug.print("line {}: mismatched operands of different types\n", .{error_context.line}),
                else => return err,
            }
        } else return err;
    };

    const stdio = std.io.getStdOut().writer();
    try inon.parser.global.printValue(stdio);
    
    try writer.print("\n\n==================\n\n", .{});
    
    try inon.parser.global.serialize(0, stdio);
}
