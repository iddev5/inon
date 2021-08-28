const std = @import("std");
const Inon = @import("src/lib.zig").Inon;
const ParseError = @import("src/lib.zig").Parser.ParseError;

pub fn main() anyerror!void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = &gpa.allocator;

    const stdio = std.io.getStdOut().writer();

    var inon = Inon.init(allocator);
    defer inon.free();

    var data = inon.deserializeFromMemory(
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
    ) catch |err| {
        if (inon.parser.getErrorContext()) |error_context| {
            switch (error_context.err) {
                ParseError.invalid_operator => std.debug.print("line {}: invalid operator\n", .{error_context.line}),
                ParseError.mismatched_operands => std.debug.print("line {}: mismatched operands of different types\n", .{error_context.line}),
                else => return err,
            }
        }
        return err;
    };
    defer data.free();

    try stdio.print("Deserialized: \n\n", .{});
    try data.printValue(stdio);
    try stdio.print("\n\n", .{});

    try stdio.print("Serialized: \n\n", .{});
    try inon.serialize(stdio);
}
