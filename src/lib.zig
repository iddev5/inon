const std = @import("std");
const Allocator = std.mem.Allocator;
const parse = @import("parser.zig");
pub const Parser = parse.Parser;

pub const Inon = struct {
    parser: Parser,

    const Self = @This();

    pub fn init(src: []const u8, allocator: *Allocator, writer: *std.fs.File.Writer) Self {
        return .{
            .parser = Parser.init(src, allocator, writer),
        };
    }

    pub fn free(self: *Self) void {
        self.parser.free();
    }
};
