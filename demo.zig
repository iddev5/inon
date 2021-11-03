const std = @import("std");
const Inon = @import("src/lib.zig").Inon;
const ParseError = @import("src/lib.zig").Parser.ParseError;

pub fn main() anyerror!void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = &gpa.allocator;

    const stdout = std.io.getStdOut().writer();

    var inon = Inon.init(allocator);
    defer inon.free();

    var data = inon.deserializeFromMemory(
        \\first_name = "joe";
        \\last_name = "something";
        \\age = 50;
        \\address = {
        \\    street_no = 
        \\        if (age == 30) 
        \\            { 420 } 
        \\        else if (age == 40) 
        \\            { 40 } 
        \\        else if (age == 50) 
        \\            { 50 } 
        \\        else 
        \\            { 60 };
        \\    num = self.street_no * 2;
        \\    city = "nyc";
        \\};
        \\phone_nos = [100, 200, 300];
        \\second_no = phone_nos.1;
    ) catch |err| switch (err) {
        error.ParseError => {
            try inon.renderError(stdout);
            return;
        },
        else => |e| return e,
    };
    defer data.free();

    try stdout.print("Deserialized: \n\n", .{});
    try stdout.print("{s}\n\n", .{@TypeOf(data.value.map)});

    try stdout.print("Serialized: \n\n", .{});
    try inon.serialize(stdout);
}
