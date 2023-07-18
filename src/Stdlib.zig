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

fn paramBuilder(allocator: std.mem.Allocator, types: []?Data.Type) ![]Data.Param {
    var params: std.ArrayListUnmanaged(Data.Param) = .{};
    for (types) |ty| {
        try params.append(allocator, Data.Param{ .type = ty });
    }
    return params.toOwnedSlice(allocator);
}

pub fn addAll(inon: *Inon) !void {
    const Func = struct { name: []const u8, func: Data.NativeFunction };

    const allocator = inon.allocator;
    const functions: []const Func = &.{
        .{
            .name = "+",
            .func = .{
                .params = try paramBuilder(allocator, @constCast(&[_]?Data.Type{ .num, .num })),
                .run = Lib.add,
            },
        },
        .{
            .name = "*",
            .func = .{
                .params = try paramBuilder(allocator, @constCast(&[_]?Data.Type{ .num, .num })),
                .run = Lib.mul,
            },
        },
        .{
            .name = "=",
            .func = .{
                .params = try paramBuilder(allocator, @constCast(&[_]?Data.Type{ null, null })),
                .run = Lib.eql,
            },
        },
        .{
            .name = "find",
            .func = .{
                .params = try paramBuilder(allocator, @constCast(&[_]?Data.Type{ null, null })),
                .run = Lib.find,
            },
        },
        .{
            .name = "self",
            .func = .{
                .params = try paramBuilder(allocator, @constCast(&[_]?Data.Type{.str})),
                .run = Lib.self,
            },
        },
        .{
            .name = "index",
            .func = .{
                .params = try paramBuilder(allocator, @constCast(&[_]?Data.Type{ null, .num })),
                .run = Lib.index,
            },
        },
        .{
            .name = "switch",
            .func = .{
                .params = try paramBuilder(allocator, @constCast(&[_]?Data.Type{.map})),
                .run = Lib.switch_,
            },
        },
    };

    for (functions) |f| {
        try inon.context.value.map.put(inon.allocator, Data{
            .value = .{ .str = Data.String.fromOwnedSlice(
                try inon.allocator.dupe(u8, f.name),
            ) },
            .allocator = inon.allocator,
        }, Data{
            .value = .{ .native = f.func },
            .allocator = inon.allocator,
        });
    }
}
