const std = @import("std");
const Allocator = std.mem.Allocator;
const meta = std.meta;

const Data = @This();

value: union(Type) {
    bool: bool,
    num: f64,
    str: String,
    array: Array,
    object: Object,
    map: Map,
    nulled: void,
} = undefined,
allocator: Allocator = undefined,

pub const String = std.ArrayListUnmanaged(u8);
pub const Array = std.ArrayListUnmanaged(Data);
pub const Object = std.StringHashMapUnmanaged(Data);
pub const Map = struct {
    internal: std.HashMapUnmanaged(Data, Data, MapContext(Data), 80) = .{},
    is_object: bool = false,
};

fn MapContext(comptime K: type) type {
    return struct {
        const Ctx = @This();
        pub fn hash(ctx: Ctx, k: K) u64 {
            _ = ctx;
            return k.hash();
        }
        pub fn eql(ctx: Ctx, a: K, b: K) bool {
            _ = ctx;
            return a.eql(&b);
        }
    };
}

pub const Type = enum(u8) {
    bool,
    num,
    str,
    array,
    object,
    map,
    nulled,
};

pub const null_data = Data{ .value = .{ .nulled = void{} } };

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
        .object => {
            var iter = self.value.object.iterator();
            while (iter.next()) |entry| {
                var key = entry.key_ptr.*;
                var value = entry.value_ptr.*;
                // TODO: this would panic in case the user is manually adding the field
                // without allocating it.
                self.allocator.free(key);
                value.deinit();
            }
            self.value.object.deinit(self.allocator);
        },
        .map => |*m| {
            var iter = m.internal.iterator();
            while (iter.next()) |entry| {
                var key = entry.key_ptr.*;
                var value = entry.value_ptr.*;
                key.deinit();
                value.deinit();
            }
            m.internal.deinit(self.allocator);
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
    .object => Object,
    .map => Map,
    .nulled => @compileError("cannot use Data.get(.nulled)"),
} {
    return @field(self.value, @tagName(t));
}

pub fn findEx(self: *const Data, name: Data) Data {
    return switch (self.value) {
        .map => {
            return if (self.value.map.internal.get(name)) |data|
                data
            else
                Data.null_data;
        },
        else => unreachable,
    };
}

pub fn findExFromString(self: *const Data, name: []const u8) Data {
    return self.findEx(Data.fromByteSlice(name));
}

pub fn find(self: *const Data, name: Data) Data {
    if (name.is(.str))
        if (std.mem.startsWith(u8, name.get(.str).items, "_"))
            return Data.null_data;
    return self.findEx(name);
}

pub fn findFromString(self: *const Data, name: []const u8) Data {
    return self.find(Data.fromByteSlice(name));
}

fn fromByteSlice(slice: []const u8) Data {
    var data = Data{ .value = .{ .str = .{} }, .allocator = undefined };
    data.value.str = String.fromOwnedSlice(@constCast(slice));

    return data;
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

const autoHash = std.hash.autoHash;
pub fn hash(self: *const Data) u64 {
    var hasher = std.hash.Wyhash.init(0);
    switch (self.value) {
        .bool => |b| autoHash(&hasher, b),
        .num => |n| autoHash(&hasher, @as(u64, @intFromFloat(n))),
        .str => |str| hasher.update(str.items),
        .nulled => {},
        // TODO: extend below
        .array => |a| autoHash(&hasher, a.items.len),
        .object => |o| autoHash(&hasher, o.size),
        .map => |m| autoHash(&hasher, m.internal.size),
    }
    return hasher.final();
}

pub fn eql(self: *const Data, data: *const Data) bool {
    if (meta.activeTag(self.value) != meta.activeTag(data.value))
        return false;

    return switch (self.value) {
        .bool => self.value.bool == data.value.bool,
        .num => self.value.num == data.value.num,
        .str => std.mem.eql(u8, self.value.str.items, data.value.str.items),
        .array => blk: {
            const len = self.value.array.items.len;
            if (len != data.value.array.items.len)
                break :blk false;

            var i: usize = 0;
            while (i < len) : (i += 1) {
                if (!self.value.array.items[i].eql(&data.value.array.items[i]))
                    break :blk false;
            }

            break :blk true;
        },
        .object => blk: {
            if (self.value.object.size != data.value.object.size)
                break :blk false;

            var iter = self.value.object.iterator();
            while (iter.next()) |entry| {
                const key = entry.key_ptr.*;
                _ = key;
                const value = entry.value_ptr.*;
                _ = value;

                break :blk false;
            }

            break :blk true;
        },
        // TODO: proper map support
        .map => |m| blk: {
            if (m.internal.size != data.value.map.internal.size)
                break :blk false;

            var iter = m.internal.iterator();
            while (iter.next()) |entry| {
                const key = entry.key_ptr.*;
                const value = entry.value_ptr.*;

                if (!value.eql(&data.findEx(key)))
                    break :blk false;
            }

            break :blk true;
        },
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
        .object => {
            var data = Data{ .value = .{ .object = .{} }, .allocator = allocator };
            var iter = self.value.object.iterator();
            while (iter.next()) |entry| {
                const key = entry.key_ptr.*;
                const value = entry.value_ptr.*;
                try data.value.object.put(
                    allocator,
                    try allocator.dupe(u8, key),
                    try value.copy(allocator),
                );
            }

            return data;
        },
        .map => |m| {
            var data = Data{ .value = .{ .map = .{} }, .allocator = allocator };
            var iter = m.internal.iterator();
            while (iter.next()) |entry| {
                const key = entry.key_ptr.*;
                const value = entry.value_ptr.*;
                try data.value.map.internal.put(
                    allocator,
                    try key.copy(allocator),
                    try value.copy(allocator),
                );
            }

            return data;
        },
    }
}

pub const SerializeOptions = struct {
    quote_string: bool = true,
    write_newlines: bool = true,
};

pub fn serialize(self: *const Data, indent: usize, writer: anytype, options: SerializeOptions) @TypeOf(writer).Error!void {
    try self.serializeInternal(0, indent, writer, options);
}

fn serializeInternal(self: *const Data, start: usize, indent: usize, writer: anytype, options: SerializeOptions) @TypeOf(writer).Error!void {
    switch (self.value) {
        .bool => try writer.print("{}", .{self.value.bool}),
        .num => if (self.value.num > 100000) {
            try writer.print("{e}", .{self.value.num});
        } else {
            try writer.print("{d}", .{self.value.num});
        },
        .nulled => try writer.writeAll("null"),
        .str => if (options.quote_string) {
            try writer.print("\"{s}\"", .{self.value.str.items});
        } else {
            try writer.writeAll(self.value.str.items);
        },
        .array => {
            const arr = self.value.array;
            var id: usize = 0;

            try writer.writeByte('[');

            while (id < arr.items.len) : (id += 1) {
                if (options.write_newlines)
                    try writer.writeByte('\n');

                // Write value
                try writer.writeByteNTimes(' ', start + indent);
                try arr.items[id].serializeInternal(start + indent, indent, writer, options);

                // If not last element then write a comma
                if (id != arr.items.len - 1)
                    try writer.writeAll(", ");
            }

            if (id > 0) {
                if (options.write_newlines)
                    try writer.writeByte('\n');
                try writer.writeByteNTimes(' ', start);
            }
            try writer.writeByte(']');
        },
        .object => {
            const object = self.value.object;
            var iter = object.iterator();
            var id: usize = 0;

            try writer.writeByte('{');

            while (iter.next()) |entry| : (id += 1) {
                if (options.write_newlines)
                    try writer.writeByte('\n');

                const key = entry.key_ptr.*;
                if (std.mem.startsWith(u8, key, "_"))
                    continue;

                // Write key
                try writer.writeByteNTimes(' ', start + indent);
                try writer.print("{s}: ", .{key});

                // Write value
                try entry.value_ptr.*.serializeInternal(start + indent, indent, writer, options);

                // Write newline if allowed, otherwise write a comma
                if (!options.write_newlines and id != object.size - 1) {
                    try writer.writeAll(", ");
                }
            }

            if (id > 0) {
                if (options.write_newlines)
                    try writer.writeByte('\n');
                try writer.writeByteNTimes(' ', start);
            }
            try writer.writeByte('}');
        },
        .map => {
            const object = self.value.map;
            var iter = object.internal.iterator();
            var id: usize = 0;

            try writer.writeByte('{');

            while (iter.next()) |entry| : (id += 1) {
                if (options.write_newlines)
                    try writer.writeByte('\n');

                // Write key
                try writer.writeByteNTimes(' ', start + indent);
                try entry.key_ptr.*.serializeInternal(start + indent, indent, writer, options);
                try writer.writeAll(": ");

                // Write value
                try entry.value_ptr.*.serializeInternal(start + indent, indent, writer, options);

                // Write newline if allowed, otherwise write a comma
                if (!options.write_newlines and id != object.internal.size - 1) {
                    try writer.writeAll(", ");
                }
            }

            if (id > 0) {
                if (options.write_newlines)
                    try writer.writeByte('\n');
                try writer.writeByteNTimes(' ', start);
            }
            try writer.writeByte('}');
        },
    }
}

pub fn serializeToJson(self: *Data, indent: usize, writer: anytype) @TypeOf(writer).Error!void {
    // Depth 10 should be enough?
    var jw = std.json.writeStream(writer, 10);
    jw.whitespace.indent.space = @as(u8, @intCast(indent));
    try serializeJsonInternal(self, &jw);
}

fn serializeJsonInternal(self: *Data, jw: anytype) @TypeOf(jw.stream).Error!void {
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
        .object => {
            try jw.beginObject();

            var it = self.value.object.iterator();
            while (it.next()) |entry| {
                const key = entry.key_ptr.*;
                var value = entry.value_ptr.*;

                try jw.objectField(key);
                try value.serializeJsonInternal(jw);
            }

            try jw.endObject();
        },
        .map => {
            try jw.beginObject();

            var it = self.value.map.internal.iterator();
            while (it.next()) |entry| {
                var key = entry.key_ptr.*;
                var value = entry.value_ptr.*;

                // TODO: support other key types
                if (key.is(.str)) {
                    try jw.objectField(key.get(.str).items);
                }
                try value.serializeJsonInternal(jw);
            }

            try jw.endObject();
        },
    }
}
