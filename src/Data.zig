const std = @import("std");
const Allocator = std.mem.Allocator;

const Data = @This();

name: []const u8,
value: union(DataType) {
    bool: bool,
    num: f64,
    str: String,
    array: std.ArrayList(Data),
    map: std.StringHashMap(Data),
},

pub const String = std.ArrayList(u8);
pub const Array = std.ArrayList(Data);
pub const Map = std.StringHashMap(Data);

pub const DataType = enum {
    bool,
    num,
    str,
    array,
    map,
};

pub fn initString(name: []const u8, allocator: Allocator) Data {
    return .{
        .name = name,
        .value = .{ .str = String.init(allocator) },
    };
}

pub fn initArray(name: []const u8, allocator: Allocator) Data {
    return .{
        .name = name,
        .value = .{ .array = std.ArrayList(Data).init(allocator) },
    };
}

pub fn initMap(name: []const u8, allocator: Allocator) Data {
    return .{
        .name = name,
        .value = .{ .map = std.StringHashMap(Data).init(allocator) },
    };
}

pub fn free(self: *Data) void {
    switch (self.value) {
        .str => self.value.str.deinit(),
        .array => {
            for (self.value.array.items) |item| {
                var i = item;
                i.free();
            }
            self.value.array.deinit();
        },
        .map => {
            var iter = self.value.map.valueIterator();
            while (iter.next()) |value| {
                value.*.free();
            }
            self.value.map.deinit();
        },
        else => {},
    }
}

pub fn get(self: *Data, name: []const u8) !Data {
    if (std.mem.eql(u8, self.name, name))
        return self.*;

    return switch (self.value) {
        .map => self.value.map.get(name).?,
        else => unreachable,
    };
}

// Unsafe, check for matching tags separately
pub fn eql(self: *Data, data: *Data) bool {
    return switch (self.value) {
        .bool => self.value.bool == data.value.bool,
        .num => self.value.num == data.value.num,
        .str => std.mem.eql(u8, self.value.str.items, data.value.str.items),
        .array => false, // TODO
        .map => false, // TODO
    };
}

pub fn copy(self: *const Data, allocator: Allocator) Allocator.Error!Data {
    switch (self.value) {
        .bool, .num => return self.*,
        .str => {
            var data = Data.initString("", allocator);
            for (self.value.str.items) |item| {
                try data.value.str.append(item);
            }

            return data;
        },
        .array => {
            var data = Data.initArray("", allocator);
            for (self.value.array.items) |item| {
                try data.value.array.append(try item.copy(allocator));
            }

            return data;
        },
        .map => {
            var data = Data.initMap("", allocator);
            var iter = self.value.map.iterator();
            while (iter.next()) |entry| {
                const key = entry.key_ptr.*;
                const value = entry.value_ptr.*;
                try data.value.map.put(key, try value.copy(allocator));
            }

            return data;
        },
    }
}

pub fn serialize(self: *Data, indent: usize, writer: std.fs.File.Writer) std.os.WriteError!void {
    try self.serializeInternal(indent, writer);
    try writer.print(";\n", .{});
}

fn serializeInternal(self: *Data, indent: usize, writer: std.fs.File.Writer) std.os.WriteError!void {
    if (!std.mem.eql(u8, self.name, "")) {
        _ = try writer.writeByteNTimes(' ', indent);
        try writer.print("{s} = ", .{self.name});
    }

    switch (self.value) {
        .bool => try writer.print("{}", .{self.value.bool}),
        .num => try writer.print("{}", .{self.value.num}),
        .str => try writer.print("\"{s}\"", .{self.value.str.items}),
        .array => {
            const arr = self.value.array;
            var id: usize = 0;

            _ = try writer.write("[");

            while (id < arr.items.len) : (id += 1) {
                try arr.items[id].serializeInternal(indent, writer);
                if (id != arr.items.len - 1)
                    _ = try writer.write(", ");
            }

            _ = try writer.write("]");
        },
        .map => {
            const map = self.value.map;
            var iter = map.iterator();
            var id: usize = 0;

            _ = try writer.write("{\n");

            while (iter.next()) |entry| : (id += 1) {
                try entry.value_ptr.*.serializeInternal(indent + 4, writer);
                _ = try writer.write(";\n");
            }

            _ = try writer.writeByteNTimes(' ', indent);
            _ = try writer.write("}");
        },
    }
}
