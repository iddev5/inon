const std = @import("std");
const Allocator = std.mem.Allocator;

const Data = @This();

value: union(Type) {
    bool: bool,
    num: f64,
    str: String,
    array: Array,
    map: Map,
    nulled: void,
} = undefined,
allocator: Allocator = undefined,

pub const String = std.ArrayListUnmanaged(u8);
pub const Array = std.ArrayListUnmanaged(Data);
pub const Map = std.StringHashMapUnmanaged(Data);

pub const Type = enum(u8) {
    bool,
    num,
    str,
    array,
    map,
    nulled,
};

pub const null_data = Data{ .value = .{ .nulled = .{} } };

pub fn deinit(self: *Data) void {
    switch (self.value) {
        .str => self.value.str.deinit(self.allocator),
        .array => {
            for (self.value.array.items) |item| {
                var i = item;
                i.deinit();
            }
            self.value.array.deinit(self.allocator);
        },
        .map => {
            var iter = self.value.map.valueIterator();
            while (iter.next()) |value| {
                value.*.deinit();
            }
            self.value.map.deinit(self.allocator);
        },
        else => {},
    }
}

pub fn is(self: *const Data, t: Type) bool {
    return self.value == t;
}

pub fn get(self: *const Data, comptime t: Type) switch (t) {
    .bool => bool,
    .num => f64,
    .str => String,
    .array => Array,
    .map => Map,
    .nulled => @compileError("cannot use Data.get(.nulled)"),
} {
    return @field(self.value, @tagName(t));
}

pub fn findEx(self: *const Data, name: []const u8) Data {
    return switch (self.value) {
        .map => if (self.value.map.get(name)) |data| data else Data.null_data,
        else => unreachable,
    };
}

pub fn find(self: *const Data, name: []const u8) Data {
    if (std.mem.startsWith(u8, name, "_")) return Data.null_data;
    return self.findEx(name);
}

pub fn index(self: *const Data, in: usize) !Data {
    return switch (self.value) {
        .str => blk: {
            if (in > self.get(.str).items.len) break :blk Data.null_data;
            var data = Data{ .value = .{ .str = .{} }, .allocator = self.allocator };
            try data.value.str.append(data.allocator, self.get(.str).items[in]);
            break :blk data;
        },
        .array => blk: {
            if (in > self.get(.array).items.len) break :blk Data.null_data;
            break :blk try self.get(.array).items[in].copy(self.allocator);
        },
        else => unreachable,
    };
}

// Unsafe, check for matching tags separately
pub fn eql(self: *const Data, data: *const Data) bool {
    return switch (self.value) {
        .bool => self.value.bool == data.value.bool,
        .num => self.value.num == data.value.num,
        .str => std.mem.eql(u8, self.value.str.items, data.value.str.items),
        .array => false, // TODO
        .map => false, // TODO
        .nulled => true,
    };
}

pub fn copy(self: *const Data, allocator: Allocator) Allocator.Error!Data {
    switch (self.value) {
        .bool, .num, .nulled => return self.*,
        .str => {
            var data = Data{ .value = .{ .str = .{} }, .allocator = allocator };
            for (self.value.str.items) |item| {
                try data.value.str.append(allocator, item);
            }

            return data;
        },
        .array => {
            var data = Data{ .value = .{ .array = .{} }, .allocator = allocator };
            for (self.value.array.items) |item| {
                try data.value.array.append(allocator, try item.copy(allocator));
            }

            return data;
        },
        .map => {
            var data = Data{ .value = .{ .map = .{} }, .allocator = allocator };
            var iter = self.value.map.iterator();
            while (iter.next()) |entry| {
                const key = entry.key_ptr.*;
                const value = entry.value_ptr.*;
                try data.value.map.put(allocator, key, try value.copy(allocator));
            }

            return data;
        },
    }
}

pub fn serialize(self: *Data, indent: usize, writer: anytype) std.os.WriteError!void {
    try self.serializeInternal(0, indent, writer);
}

fn serializeInternal(self: *Data, start: usize, indent: usize, writer: anytype) std.os.WriteError!void {
    switch (self.value) {
        .bool => try writer.print("{}", .{self.value.bool}),
        .num => try writer.print("{}", .{self.value.num}),
        .nulled => try writer.writeAll("null"),
        .str => try writer.print("\"{s}\"", .{self.value.str.items}),
        .array => {
            const arr = self.value.array;
            var id: usize = 0;

            try writer.writeAll("[\n");

            while (id < arr.items.len) : (id += 1) {
                // Write value
                try writer.writeByteNTimes(' ', start + indent);
                try arr.items[id].serializeInternal(start, indent, writer);

                // If not last element then write a comma
                if (id != arr.items.len - 1)
                    try writer.writeByte(',');

                try writer.writeByte('\n');
            }

            try writer.writeByteNTimes(' ', start);
            try writer.writeByte(']');
        },
        .map => {
            const map = self.value.map;
            var iter = map.iterator();
            var id: usize = 0;

            try writer.writeAll("{\n");

            while (iter.next()) |entry| : (id += 1) {
                const key = entry.key_ptr.*;
                if (std.mem.startsWith(u8, key, "_"))
                    continue;

                // Write key
                try writer.writeByteNTimes(' ', start + indent);
                try writer.print("{s}: ", .{key});

                // Write value
                try entry.value_ptr.*.serializeInternal(start + indent, indent, writer);
                try writer.writeByte('\n');
            }

            try writer.writeByteNTimes(' ', start);
            try writer.writeByte('}');
        },
    }
}

pub fn serializeToJson(self: *Data, indent: usize, writer: anytype) !void {
    // Depth 10 should be enough?
    var jw = std.json.writeStream(writer, 10);
    jw.whitespace.indent.Space = @intCast(u8, indent);
    try serializeJsonInternal(self, &jw);
}

fn serializeJsonInternal(self: *Data, jw: anytype) std.os.WriteError!void {
    switch (self.value) {
        .num => try jw.emitNumber(self.value.num),
        .bool => try jw.emitBool(self.value.bool),
        .nulled => try jw.emitNull(),
        .str => try jw.emitString(self.value.str.items),
        .array => {
            try jw.beginArray();

            for (self.value.array.items) |*item| {
                try jw.arrayElem();
                try item.serializeJsonInternal(jw);
            }

            try jw.endArray();
        },
        .map => {
            try jw.beginObject();

            var it = self.value.map.iterator();
            while (it.next()) |entry| {
                const key = entry.key_ptr.*;
                var value = entry.value_ptr.*;

                try jw.objectField(key);
                try value.serializeJsonInternal(jw);
            }

            try jw.endObject();
        },
    }
}
