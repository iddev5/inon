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

    try expect(data.get("a").?.is(.nulled));
}

test "trailing comma" {
    var data = try testNormal(
        \\a: null,
        \\b: null,
    );
    defer data.deinit();

    try expect(data.get("a").?.is(.nulled));
    try expect(data.get("b").?.is(.nulled));
}

test "assign bool" {
    var data = try testNormal(
        \\a: true
        \\b: false
    );
    defer data.deinit();

    try expectEqual(true, data.get("a").?.raw(.bool).?);
    try expectEqual(false, data.get("b").?.raw(.bool).?);
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

    try expectEqual(@as(f64, 10.000), data.get("a").?.raw(.num).?);
    try expectEqual(@as(f64, -24.00), data.get("b").?.raw(.num).?);
    try expectEqual(@as(f64, 41.550), data.get("c").?.raw(.num).?);
    try expectEqual(@as(f64, 58.200), data.get("d").?.raw(.num).?);
    try expectEqual(@as(f64, 1100.0), data.get("e").?.raw(.num).?);
    try expectEqual(@as(f64, 78.1e7), data.get("f").?.raw(.num).?);
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

    try expectEqual(@as(f64, 0x10), data.get("a").?.raw(.num).?);
    try expectEqual(@as(f64, -0x21), data.get("b").?.raw(.num).?);
    try expectEqual(@as(f64, 0x32p2), data.get("c").?.raw(.num).?);
    try expectEqual(@as(f64, 0x21.12), data.get("d").?.raw(.num).?);
    try expectEqual(@as(f64, 0x47.98p32), data.get("e").?.raw(.num).?);
}

test "oct bin number" {
    var data = try testNormal(
        \\a: -0o71
        \\b: +0O23
        \\c: +0b1101
        \\d: -0B0101
    );
    defer data.deinit();

    try expectEqual(@as(f64, -0o71), data.get("a").?.raw(.num).?);
    try expectEqual(@as(f64, 0o23), data.get("b").?.raw(.num).?);
    try expectEqual(@as(f64, 0b1101), data.get("c").?.raw(.num).?);
    try expectEqual(@as(f64, -0b0101), data.get("d").?.raw(.num).?);
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

    try expectEqualStrings("hello world", data.get("a").?.raw(.str).?.items);
    try expectEqualStrings("slightly\nlonger\nstring", data.get("b").?.raw(.str).?.items);
    try expectEqualStrings("single quotes", data.get("c").?.raw(.str).?.items);
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

    try expectEqualStrings("a is 10 value", data.get("b").?.raw(.str).?.items);
    try expectEqualStrings("hello world", data.get("d").?.raw(.str).?.items);
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

    try expectEqualStrings("{something}", data.get("a").?.raw(.str).?.items);
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

    const array = data.get("a").?.raw(.array).?.items;

    try expectEqual(@as(f64, 10), array[0].raw(.num).?);
    try expectEqual(true, array[1].raw(.bool).?);
    try expectEqualStrings("test", array[2].raw(.str).?.items);
}

test "nested array" {
    var data = try testNormal(
        \\a: [10, [20, 30], 40]
    );
    defer data.deinit();

    const array = data.get("a").?.raw(.array).?.items;

    try expectEqual(@as(f64, 10), array[0].raw(.num).?);
    {
        const inner_array = array[1].raw(.array).?.items;
        try expectEqual(@as(f64, 20), inner_array[0].raw(.num).?);
        try expectEqual(@as(f64, 30), inner_array[1].raw(.num).?);
    }
    try expectEqual(@as(f64, 40), array[2].raw(.num).?);
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

    const map_a = data.get("a").?;
    const map_b = data.get("b").?;

    try expectEqualStrings("test", map_a.get("test").?.raw(.str).?.items);
    try expectEqual(@as(f64, 10), map_a.get("hello").?.raw(.num).?);

    try expectEqual(@as(f64, 10), map_b.get("a").?.raw(.num).?);
    try expectEqual(@as(f64, 20), map_b.get("b").?.raw(.num).?);
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

    const map_a = data.get("a").?;
    const map_b = data.get("b").?;

    try expect(map_a.eql(&map_b));
}
