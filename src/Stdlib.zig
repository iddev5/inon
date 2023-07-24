const std = @import("std");
const Inon = @import("main.zig");
const Data = @import("Data.zig");

const Lib = struct {
    fn add(inon: *Inon, params: []Data) !Data {
        _ = inon;
        const data1 = params[0];
        const data2 = params[1];
        return Data{ .value = .{ .num = data1.raw(.num).? + data2.raw(.num).? } };
    }

    fn sub(inon: *Inon, params: []Data) !Data {
        _ = inon;
        const data1 = params[0];
        const data2 = params[1];
        return Data{ .value = .{ .num = data1.raw(.num).? - data2.raw(.num).? } };
    }

    fn mul(inon: *Inon, params: []Data) !Data {
        _ = inon;
        const data1 = params[0];
        const data2 = params[1];
        return Data{ .value = .{ .num = data1.raw(.num).? * data2.raw(.num).? } };
    }

    fn get(inon: *Inon, params: []Data) !Data {
        const data1 = params[0];
        const data2 = params[1];
        return try data1.getEx(data2).copy(inon.allocator);
    }

    fn self(inon: *Inon, params: []Data) !Data {
        const data1 = params[0];
        return try inon.current_context.getEx(data1.raw(.str).?.items).copy(inon.allocator);
    }

    fn index(inon: *Inon, params: []Data) !Data {
        _ = inon;
        const data1 = params[0];
        const data2 = params[1];

        const n = @as(usize, @intFromFloat(data2.raw(.num).?));

        return try data1.index(n);
    }

    fn eql(_: *Inon, params: []Data) !Data {
        const data1 = params[0];
        const data2 = params[1];
        return Data{ .value = .{ .bool = data1.eql(&data2) } };
    }

    fn switch_(inon: *Inon, params: []Data) !Data {
        const map = params[0];
        var iter = map.raw(.map).?.iterator();
        while (iter.next()) |pair| {
            const key = pair.key_ptr.*;
            if (key.is(.bool) and key.raw(.bool).? == true) {
                return pair.value_ptr.*.copy(inon.allocator);
            }
        }
        return map.get("else");
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
            .name = "-",
            .func = .{
                .params = try paramBuilder(allocator, @constCast(&[_]?Data.Type{ .num, .num })),
                .run = Lib.sub,
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
            .name = "get",
            .func = .{
                .params = try paramBuilder(allocator, @constCast(&[_]?Data.Type{ null, null })),
                .run = Lib.get,
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
