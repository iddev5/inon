const std = @import("std");
const Inon = @import("main.zig");

const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;

fn testNormal(code: []const u8) !Inon.Data {
    var inon = Inon.init(std.testing.allocator);
    defer inon.deinit();
    var data = inon.parse(code) catch |err| switch (err) {
        error.ParsingFailed => @panic("Cannot error"),
        else => |e| return e,
    };
    return data.copy(std.testing.allocator);
}

test "assign bool" {
    var data = try testNormal(
        \\a: true
        \\b: false
    );
    defer data.deinit();

    try expectEqual(true, data.find("a").get(.bool));
    try expectEqual(false, data.find("b").get(.bool));
}

test "assign number" {
    var data = try testNormal(
        \\a: 10
        \\b: -24
        \\c: 41.55
    );
    defer data.deinit();

    try expectEqual(@as(f64, 10.00), data.find("a").get(.num));
    try expectEqual(@as(f64, -24.0), data.find("b").get(.num));
    try expectEqual(@as(f64, 41.55), data.find("c").get(.num));
}

test "assign string" {
    var data = try testNormal(
        \\a: "hello world"
        \\b:
        \\ \\slightly
        \\ \\longer
        \\ \\string
    );
    defer data.deinit();

    try expectEqualStrings("hello world", data.find("a").get(.str).items);
    try expectEqualStrings("slightly\nlonger\nstring\n", data.find("b").get(.str).items);
}
