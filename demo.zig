const std = @import("std");
const Inon = @import("inon");

pub fn main() anyerror!void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const stdout = std.io.getStdOut().writer();

    var inon = Inon.init(allocator);
    defer inon.deinit();

    try Inon.Stdlib.addAll(&inon);

    var data = inon.parse("<demo>",
        \\first_name: "joe"
        \\last_name: "some {first_name} thing"
        \\age: 50
        \\address: {
        \\    street_no: switch %{
        \\        (= age 30): 420
        \\        (= age 40): 40
        \\        (= age 50): 50
        \\        else: 70
        \\    }
        \\    num: * (self "street_no") 2
        \\    city: "nyc"
        \\}
        \\phone_nos: [100, 200, 300]
        \\second_no: index phone_nos 1
    ) catch |err| switch (err) {
        error.ParsingFailed => return try inon.renderError(stdout),
        else => |e| return e,
    };

    try stdout.print("Deserialized: \n\n", .{});
    try stdout.print("{}\n\n", .{@TypeOf(data.value.map)});

    try stdout.print("Serialized: \n\n", .{});
    try inon.serialize(&data, stdout);
    try stdout.writeAll("\n\n");

    try stdout.print("Json: \n\n", .{});
    try inon.serializeToJson(&data, stdout);
    try stdout.writeAll("\n\n");

    std.log.info("All your config files are belong to us.", .{});
}
