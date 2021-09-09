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
        \\first_name = "joe";
        \\last_name = "something";
        \\age = 50;
        \\address = {
        \\    street_no = 
        \\        if (global.age == 30) 
        \\            { 420 } 
        \\        else if (global.age == 40) 
        \\            { 40 } 
        \\        else if (global.age == 50) 
        \\            { 50 } 
        \\        else 
        \\            { 60 };
        \\    city = "nyc";
        \\};
        \\phone_nos = [100, 200, 300];
        \\second_no = phone_nos.1;
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
    try stdio.print("{s}\n\n", .{@TypeOf(data.value.map)});

    try stdio.print("Serialized: \n\n", .{});
    try inon.serialize(stdio);
}
