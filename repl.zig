const std = @import("std");
const Inon = @import("inon");

pub fn main() anyerror!void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const stdin = std.io.getStdIn().reader();
    const stdout = std.io.getStdOut().writer();

    var line_buffer = std.ArrayList(u8).init(allocator);
    defer line_buffer.deinit();

    var inon = Inon.init(allocator);
    defer inon.deinit();

    try Inon.Stdlib.addAll(&inon);

    repl: while (true) {
        try stdout.writeAll("> ");
        stdin.readUntilDelimiterArrayList(&line_buffer, '\n', 4096) catch |err| switch (err) {
            error.EndOfStream => break :repl,
            else => |e| return e,
        };

        const line = std.mem.trim(u8, line_buffer.items, "\t ");

        var data = inon.parse("<repl>", line) catch |err| switch (err) {
            error.ParsingFailed => val: {
                _ = try inon.renderError(stdout);
                break :val Inon.Data.null_data;
            },
            else => |e| return e,
        };
        try inon.serialize(&data, stdout);
        try stdout.writeByte('\n');
    }

    std.log.info("All your config files are belong to us.", .{});
}
