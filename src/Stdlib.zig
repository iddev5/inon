const std = @import("std");
const Inon = @import("main.zig");
const Data = @import("Data.zig");

const Lib = struct {
    fn add(inon: *Inon, params: []Data) !Data {
        _ = inon;
        const data1 = params[0];
        const data2 = params[1];
        return Data{ .value = .{ .num = data1.get(.num) + data2.get(.num) } };
    }

    fn mul(inon: *Inon, params: []Data) !Data {
        _ = inon;
        const data1 = params[0];
        const data2 = params[1];
        return Data{ .value = .{ .num = data1.get(.num) * data2.get(.num) } };
    }

    fn find(inon: *Inon, params: []Data) !Data {
        const data1 = params[0];
        const data2 = params[1];
        return try data1.findEx(data2).copy(inon.allocator);
    }

    fn self(inon: *Inon, params: []Data) !Data {
        const data1 = params[0];
        return try inon.current_context.findExFromString(data1.get(.str).items).copy(inon.allocator);
    }

    fn index(inon: *Inon, params: []Data) !Data {
        _ = inon;
        const data1 = params[0];
        const data2 = params[1];

        const n = @as(usize, @intFromFloat(data2.get(.num)));

        return try data1.index(n);
    }

    fn eql(_: *Inon, params: []Data) !Data {
        const data1 = params[0];
        const data2 = params[1];
        return Data{ .value = .{ .bool = data1.eql(&data2) } };
    }

    fn switch_(inon: *Inon, params: []Data) !Data {
        const map = params[0];
        var iter = map.get(.map).iterator();
        while (iter.next()) |pair| {
            const key = pair.key_ptr.*;
            if (key.is(.bool) and key.get(.bool) == true) {
                return pair.value_ptr.*.copy(inon.allocator);
            }
        }
        return map.findFromString("else");
    }
};

pub fn addAll(inon: *Inon) !void {
    const functions: []const Inon.FuncType = &.{
        .{ .name = "+", .params = &.{ .num, .num }, .run = Lib.add },
        .{ .name = "*", .params = &.{ .num, .num }, .run = Lib.mul },
        .{ .name = "find", .params = &.{ null, null }, .run = Lib.find },
        .{ .name = "self", .params = &.{.str}, .run = Lib.self },
        .{ .name = "index", .params = &.{ null, .num }, .run = Lib.index },
        .{ .name = "=", .params = &.{ null, null }, .run = Lib.eql },
        .{ .name = "switch", .params = &.{.map}, .run = Lib.switch_ },
    };

    for (functions) |f| {
        try inon.functions.put(inon.allocator, f.name, f);
    }
}
