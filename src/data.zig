const std = @import("std");
const Allocator = std.mem.Allocator;

pub const String = std.ArrayList(u8);

pub const DataType = enum { num, str, arr, map };

pub const ArrayType = std.ArrayList(Data);
pub const MapType = std.StringHashMap(Data);

pub const Data = struct {
    name: []const u8,
    value: union(DataType) {
        num: f64,
        str: String,
        arr: std.ArrayList(Data),
        map: std.StringHashMap(Data),
    },

    const Self = @This();

    pub fn initString(name: []const u8, allocator: *Allocator) Self {
        return .{
            .name = name,
            .value = .{ .str = String.init(allocator) },
        };
    }

    pub fn initArray(name: []const u8, allocator: *Allocator) Self {
        return .{
            .name = name,
            .value = .{ .arr = std.ArrayList(Data).init(allocator) },
        };
    }

    pub fn initMap(name: []const u8, allocator: *Allocator) Self {
        return .{
            .name = name,
            .value = .{ .map = std.StringHashMap(Data).init(allocator) },
        };
    }

    pub fn free(self: *Self) void {
        switch (self.value) {
            .str => self.value.str.deinit(),
            .arr => self.value.arr.deinit(),
            .map => self.value.map.deinit(),
            else => {},
        }
    }

    pub fn printValue(self: *Self, writer: std.fs.File.Writer) !void {
        switch (self.value) {
            .num => try writer.print("{}", .{self.value.num}),
            .str => try writer.print("{s}", .{self.value.str.items}),
            .arr => {
                const arr = self.value.arr;
                var id: usize = 0;

                _ = try writer.write("[");

                while (id < arr.items.len) : (id += 1) {
                    arr.items[id].printValue(writer) catch unreachable;
                    if (id != arr.items.len - 1)
                        _ = try writer.write(", ");
                }

                _ = try writer.write("]");
            },
            .map => {
                const map = self.value.map;
                var iter = map.iterator();
                var id: usize = 0;

                _ = try writer.write("{");

                while (iter.next()) |entry| : (id += 1) {
                    try writer.print("{s} : ", .{entry.key_ptr.*});
                    entry.value_ptr.printValue(writer) catch unreachable;
                    if (id != map.count() - 1) {
                        _ = try writer.write(", ");
                    }
                }

                _ = try writer.write("}");
            },
        }
    }

    pub fn findData(self: *Self, name: []const u8) !Self {
        if (std.mem.eql(u8, self.name, name))
            return self.*;

        return switch (self.value) {
            .map => self.value.map.get(name).?,
            else => unreachable, //error.DataNotFound,
        };
    }

    pub fn makeCopy(self: *const Self, allocator: *Allocator) Allocator.Error!Self {
        switch (self.value) {
            .num => return self.*,
            .str => {
                var data = Data.initString("", allocator);
                for (self.value.str.items) |item| {
                    try data.value.str.append(item);
                }

                return data;
            },
            .arr => {
                var data = Data.initArray("", allocator);
                for (self.value.arr.items) |item| {
                    try data.value.arr.append(try item.makeCopy(allocator));
                }

                return data;
            },
            .map => {
                var data = Data.initMap("", allocator);
                var iter = self.value.map.iterator();
                while (iter.next()) |entry| {
                    const key = entry.key_ptr.*;
                    const value = entry.value_ptr.*;
                    try data.value.map.put(key, try value.makeCopy(allocator));
                }

                return data;
            },
        }
    }
};
