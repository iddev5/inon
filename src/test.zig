const std = @import("std");
const testing = std.testing;
const Inon = @import("inon");

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

fn testError(code: []const u8, error_str: []const u8) !void {
    var inon = Inon.init(std.testing.allocator);
    defer inon.deinit();
    _ = inon.parse("<test>", code) catch |err| switch (err) {
        error.ParsingFailed => {
            const diag_err = inon.diagnostics.errors.items[0];
            const error_msg = diag_err.message;
            return try testing.expect(std.mem.containsAtLeast(u8, error_msg, 1, error_str));
        },
        else => |e| return e,
    };
    unreachable;
}

test "null value" {
    var data = try testNormal(
        \\a: null
    );
    defer data.deinit();

    try expect(data.findFromString("a").is(.nulled));
}

test "trailing comma" {
    var data = try testNormal(
        \\a: null,
        \\b: null,
    );
    defer data.deinit();

    try expect(data.findFromString("a").is(.nulled));
    try expect(data.findFromString("b").is(.nulled));
}

test "assign bool" {
    var data = try testNormal(
        \\a: true
        \\b: false
    );
    defer data.deinit();

    try expectEqual(true, data.findFromString("a").get(.bool));
    try expectEqual(false, data.findFromString("b").get(.bool));
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

    try expectEqual(@as(f64, 10.000), data.findFromString("a").get(.num));
    try expectEqual(@as(f64, -24.00), data.findFromString("b").get(.num));
    try expectEqual(@as(f64, 41.550), data.findFromString("c").get(.num));
    try expectEqual(@as(f64, 58.200), data.findFromString("d").get(.num));
    try expectEqual(@as(f64, 1100.0), data.findFromString("e").get(.num));
    try expectEqual(@as(f64, 78.1e7), data.findFromString("f").get(.num));
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

    try expectEqual(@as(f64, 0x10), data.findFromString("a").get(.num));
    try expectEqual(@as(f64, -0x21), data.findFromString("b").get(.num));
    try expectEqual(@as(f64, 0x32p2), data.findFromString("c").get(.num));
    try expectEqual(@as(f64, 0x21.12), data.findFromString("d").get(.num));
    try expectEqual(@as(f64, 0x47.98p32), data.findFromString("e").get(.num));
}

test "oct bin number" {
    var data = try testNormal(
        \\a: -0o71
        \\b: +0O23
        \\c: +0b1101
        \\d: -0B0101
    );
    defer data.deinit();

    try expectEqual(@as(f64, -0o71), data.findFromString("a").get(.num));
    try expectEqual(@as(f64, 0o23), data.findFromString("b").get(.num));
    try expectEqual(@as(f64, 0b1101), data.findFromString("c").get(.num));
    try expectEqual(@as(f64, -0b0101), data.findFromString("d").get(.num));
}

test "assign string" {
    var data = try testNormal(
        \\a: "hello world"
        \\b:
        \\ \\slightly
        \\ \\longer
        \\ \\string
        \\c: 'single quotes'
    );
    defer data.deinit();

    try expectEqualStrings("hello world", data.findFromString("a").get(.str).items);
    try expectEqualStrings("slightly\nlonger\nstring", data.findFromString("b").get(.str).items);
    try expectEqualStrings("single quotes", data.findFromString("c").get(.str).items);
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

    try expectEqualStrings("a is 10 value", data.findFromString("b").get(.str).items);
    try expectEqualStrings("hello world", data.findFromString("d").get(.str).items);
}

test "raw string followed by string" {
    try testError(
        \\a: \\Hello
        \\"World"
    , "expected 'identifier', found 'string'");
}

test "empty interpolation" {
    try testError(
        \\a: "{}"
    , "empty expressions not allowed in string interpolation");
}

test "interpolation escape" {
    var data = try testNormal(
        \\a: "{{something}}"
    );
    defer data.deinit();

    try expectEqualStrings("{something}", data.findFromString("a").get(.str).items);
}

test "unmatched interpolation" {
    try testError(
        \\a: "{"
    , "unmatched '{' in string interpolation");

    try testError(
        \\a: "}"
    , "stray '}' outside of string interpolation");
}

test "assign array" {
    var data = try testNormal(
        \\a: [10, true, "test"]
    );
    defer data.deinit();

    const array = data.findFromString("a").get(.array).items;

    try expectEqual(@as(f64, 10), array[0].get(.num));
    try expectEqual(true, array[1].get(.bool));
    try expectEqualStrings("test", array[2].get(.str).items);
}

test "nested array" {
    var data = try testNormal(
        \\a: [10, [20, 30], 40]
    );
    defer data.deinit();

    const array = data.findFromString("a").get(.array).items;

    try expectEqual(@as(f64, 10), array[0].get(.num));
    {
        const inner_array = array[1].get(.array).items;
        try expectEqual(@as(f64, 20), inner_array[0].get(.num));
        try expectEqual(@as(f64, 30), inner_array[1].get(.num));
    }
    try expectEqual(@as(f64, 40), array[2].get(.num));
}

test "assign map" {
    var data = try testNormal(
        \\a: {
        \\  test: "test"
        \\  hello: 10
        \\}
        \\b: { a: 10, b: 20 }
    );
    defer data.deinit();

    const map_a = data.findFromString("a");
    const map_b = data.findFromString("b");

    try expectEqualStrings("test", map_a.findFromString("test").get(.str).items);
    try expectEqual(@as(f64, 10), map_a.findFromString("hello").get(.num));

    try expectEqual(@as(f64, 10), map_b.findFromString("a").get(.num));
    try expectEqual(@as(f64, 20), map_b.findFromString("b").get(.num));
}

test "map extended equal" {
    var data = try testNormal(
        \\a: %{
        \\  10: "test"
        \\  true: 10
        \\}
        \\b: %{
        \\  10: "test"
        \\  true: 10
        \\}
    );
    defer data.deinit();

    const map_a = data.findFromString("a");
    const map_b = data.findFromString("b");

    try expect(map_a.eql(&map_b));
}
