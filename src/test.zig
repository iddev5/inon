const std = @import("std");
const testing = std.testing;
const Inon = @import("main.zig");

const expect = testing.expect;
const expectEqual = testing.expectEqual;
const expectEqualStrings = testing.expectEqualStrings;

fn testNormal(code: []const u8) !Inon.Data {
    var inon = Inon.init(std.testing.allocator);
    defer inon.deinit();
    var data = inon.parse("<test>", code) catch |err| switch (err) {
        error.ParsingFailed => @panic("Cannot error"),
        else => |e| return e,
    };
    return data.copy(std.testing.allocator);
}

test "null value" {
    var data = try testNormal(
        \\a: null
    );
    defer data.deinit();

    try expect(data.find("a").is(.nulled));
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

test "string interpolation" {
    var data = try testNormal(
        \\a: 10
        \\b: "a is {a} value"
        \\
        \\c: "hello"
        \\d: "{c} world"
    );
    defer data.deinit();

    try expectEqualStrings("a is 10 value", data.find("b").get(.str).items);
    try expectEqualStrings("hello world", data.find("d").get(.str).items);
}

test "assign array" {
    var data = try testNormal(
        \\a: [10, true, "test"]
    );
    defer data.deinit();

    const array = data.find("a").get(.array).items;

    try expectEqual(@as(f64, 10), array[0].get(.num));
    try expectEqual(true, array[1].get(.bool));
    try expectEqualStrings("test", array[2].get(.str).items);
}

test "nested array" {
    var data = try testNormal(
        \\a: [10, [20, 30], 40]
    );
    defer data.deinit();

    const array = data.find("a").get(.array).items;

    try expectEqual(@as(f64, 10), array[0].get(.num));
    {
        const inner_array = array[1].get(.array).items;
        try expectEqual(@as(f64, 20), inner_array[0].get(.num));
        try expectEqual(@as(f64, 30), inner_array[1].get(.num));
    }
    try expectEqual(@as(f64, 40), array[2].get(.num));
}
