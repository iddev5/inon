const std = @import("std");
const Inon = @import("main.zig");

const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;

fn testNormal(code: []const u8) !Inon.Data {
    var inon = Inon.init(std.testing.allocator);
    defer inon.deinit();
    var data = inon.parse("<test>", code) catch |err| switch (err) {
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
        \\d: +58.2
        \\e: 11e2
        \\f: 78.1e7
    );
    defer data.deinit();

    try expectEqual(@as(f64, 10.000), data.find("a").get(.num));
    try expectEqual(@as(f64, -24.00), data.find("b").get(.num));
    try expectEqual(@as(f64, 41.550), data.find("c").get(.num));
    try expectEqual(@as(f64, 58.200), data.find("d").get(.num));
    try expectEqual(@as(f64, 1100.0), data.find("e").get(.num));
    try expectEqual(@as(f64, 78.1e7), data.find("f").get(.num));
}

test "hex number" {
    var data = try testNormal(
        \\a: +0x10
        \\b: -0X21
        \\c: 0x32p2
        \\d: 0x21.12
        \\e: 0x47.98p32
    );
    defer data.deinit();

    try expectEqual(@as(f64, 0x10), data.find("a").get(.num));
    try expectEqual(@as(f64, -0x21), data.find("b").get(.num));
    try expectEqual(@as(f64, 0x32p2), data.find("c").get(.num));
    try expectEqual(@as(f64, 0x21.12), data.find("d").get(.num));
    try expectEqual(@as(f64, 0x47.98p32), data.find("e").get(.num));
}

test "oct bin number" {
    var data = try testNormal(
        \\a: -0o71
        \\b: +0O23
        \\c: +0b1101
        \\d: -0B0101
    );
    defer data.deinit();

    try expectEqual(@as(f64, -0o71), data.find("a").get(.num));
    try expectEqual(@as(f64, 0o23), data.find("b").get(.num));
    try expectEqual(@as(f64, 0b1101), data.find("c").get(.num));
    try expectEqual(@as(f64, -0b0101), data.find("d").get(.num));
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
