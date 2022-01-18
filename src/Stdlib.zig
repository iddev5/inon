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
        const data1 = params[0];
        const data2 = params[1];

        const n = @floatToInt(usize, data2.get(.num));

        if (n >= data1.get(.array).items.len)
            return Data.null_data;

        return data1.get(.array).items[n].copy(inon.allocator);
    }

    fn eql(_: *Inon, params: []Data) !Data {
        const data1 = params[0];
        const data2 = params[1];
        if (std.meta.activeTag(data1.value) != std.meta.activeTag(data2.value)) {
            return Data{ .value = .{ .bool = false } };
        }
        return Data{ .value = .{ .bool = data1.eql(&data2) } };
    }
};

pub fn addAll(inon: *Inon) !void {
    const functions: []const Inon.FuncType = &.{
        .{ .name = "+", .params = &.{ .num, .num }, .run = Lib.add },
        .{ .name = "*", .params = &.{ .num, .num }, .run = Lib.mul },
        .{ .name = "find", .params = &.{ null, .str }, .run = Lib.find },
        .{ .name = "self", .params = &.{.str}, .run = Lib.self },
        .{ .name = "index", .params = &.{ .array, .num }, .run = Lib.index },
        .{ .name = "=", .params = &.{ null, null }, .run = Lib.eql },
    };

    for (functions) |f| {
        try inon.functions.put(inon.allocator, f.name, f);
    }
}
