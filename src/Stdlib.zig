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
        return try data1.findEx(data2.get(.str).items).copy(inon.allocator);
    }

    fn self(inon: *Inon, params: []Data) !Data {
        const data1 = params[0];
        return try inon.current_context.findEx(data1.get(.str).items).copy(inon.allocator);
    }

    fn index(inon: *Inon, params: []Data) !Data {
        _ = inon;
        const data1 = params[0];
        const data2 = params[1];

        const n = @floatToInt(usize, data2.get(.num));

        return try data1.index(n);
    }

    fn eql(_: *Inon, params: []Data) !Data {
        const data1 = params[0];
        const data2 = params[1];
        return Data{ .value = .{ .bool = data1.eql(&data2) } };
    }

    fn _if(_: *Inon, params: []Data) !Data {
        const data1 = params[0];
        const data2 = params[1];

        if (!data1.is(.bool))
            return Data.null_data;

        return if (data1.get(.bool)) data2 else Data.null_data;
    }

    fn ifnull(_: *Inon, params: []Data) !Data {
        const data1 = params[0];
        const data2 = params[1];

        return if (data1.is(.nulled)) data2 else data1;
    }
};

pub fn addAll(inon: *Inon) !void {
    const functions: []const Inon.FuncType = &.{
        .{ .name = "+", .params = &.{ .num, .num }, .run = Lib.add },
        .{ .name = "*", .params = &.{ .num, .num }, .run = Lib.mul },
        .{ .name = "find", .params = &.{ null, .str }, .run = Lib.find },
        .{ .name = "self", .params = &.{.str}, .run = Lib.self },
        .{ .name = "index", .params = &.{ null, .num }, .run = Lib.index },
        .{ .name = "=", .params = &.{ null, null }, .run = Lib.eql },
        .{ .name = "if", .params = &.{ .bool, null }, .run = Lib._if },
        .{ .name = "ifnull", .params = &.{ null, null }, .run = Lib.ifnull },
    };

    for (functions) |f| {
        try inon.functions.put(inon.allocator, f.name, f);
    }
}
