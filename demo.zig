const std = @import("std");
const Inon = @import("src/main.zig");

pub fn main() anyerror!void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const stdout = std.io.getStdOut().writer();

    var inon = Inon.init(allocator);
    defer inon.deinit();

    var data = inon.parse(
        \\first_name: "joe"
        \\last_name: "something"
        \\age: 50
        // \\address = {
        // \\    street_no =
        // \\        if (age == 30)
        // \\            { 420 }
        // \\        else if (age == 40)
        // \\            { 40 }
        // \\        else if (age == 50)
        // \\            { 50 }
        // \\        else
        // \\            { 60 };
        // \\    num = self.street_no * 2;
        // \\    city = "nyc";
        // \\};
        \\phone_nos: [100, 200, 300]
        // \\second_no = phone_nos.1;
    ) catch |err| switch (err) {
        error.ParsingFailed => return try inon.renderError(stdout),
        else => |e| return e,
    };

    try stdout.print("Deserialized: \n\n", .{});
    try stdout.print("{s}\n\n", .{@TypeOf(data.value.map)});

    try stdout.print("Serialized: \n\n", .{});
    try data.serialize(0, stdout);

    std.log.info("All your config files are belong to us.", .{});
}
