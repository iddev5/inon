const std = @import("std");
const Allocator = std.mem.Allocator;
const parse = @import("parser.zig");
pub const Parser = parse.Parser;
const Data = @import("Data.zig");

pub const Inon = struct {
    allocator: Allocator,
    parser: Parser = undefined,

    const Self = @This();

    pub fn init(allocator: Allocator) Self {
        return .{
            .allocator = allocator,
        };
    }

    pub fn renderError(self: *Self, writer: std.fs.File.Writer) !void {
        if (self.parser.getErrorContext()) |error_context| {
            try writer.print("line {}: {s}\n", .{ error_context.line, error_context.err });
        }
    }

    pub fn deserialize(self: *Self, reader: std.fs.File.Reader) !Data {
        const src = reader.readAllAlloc(self.allocator, std.math.maxInt(usize));
        return self.deserializeFromMemory(src);
    }

    pub fn deserializeFromMemory(self: *Self, src: []const u8) !Data {
        self.parser = Parser.init(src, self.allocator);
        defer self.parser.free();
        try self.parser.parse();
        return self.parser.global;
    }

    pub fn serialize(self: *Self, writer: std.fs.File.Writer) !void {
        // Not the best serializer but ok
        var iter = self.parser.global.value.map.iterator();
        while (iter.next()) |entry| {
            try entry.value_ptr.*.serialize(0, writer);
        }
    }

    pub fn free(self: *Self) void {
        _ = self;
    }
};
