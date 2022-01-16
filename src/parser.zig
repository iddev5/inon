const std = @import("std");
const Allocator = std.mem.Allocator;
const lex = @import("lexer.zig");
const Lexer = lex.Lexer;
const Token = lex.Token;
const Data = @import("Data.zig");

const Operation = struct {
    fn boolOp(op: Token.Type, a: Data, b: Data) !Data {
        const a_b = a.value.bool;
        const b_b = b.value.bool;
        return Data{ .value = .{ .bool = switch (op) {
            .amp => a_b and b_b,
            .@"or" => a_b or b_b,
            .equality => a_b == b_b,
            else => unreachable,
        } } };
    }

    fn numOp(op: Token.Type, a: Data, b: Data) !Data {
        const a_n = a.value.num;
        const b_n = b.value.num;
        return Data{
            .value = switch (op) {
                // Arithmetic operators
                .plus => .{ .num = a_n + b_n },
                .minus => .{ .num = a_n - b_n },
                .multiply => .{ .num = a_n * b_n },
                .divide => .{ .num = a_n / b_n },
                .floor => .{ .num = @divFloor(a_n, b_n) },
                .modulo => .{ .num = @mod(a_n, b_n) },
                // Logic operators
                .greater => .{ .bool = a_n > b_n },
                .less => .{ .bool = a_n < b_n },
                .greater_eql => .{ .bool = a_n >= b_n },
                .less_eql => .{ .bool = a_n <= b_n },
                .equality => .{ .bool = a_n == b_n },
                else => unreachable,
            },
        };
    }

    fn stringOp(op: Token.Type, a: Data, b: Data) !Data {
        if (b.value == .str) {
            switch (op) {
                .concat => {
                    var ret = try a.copy(a.allocator);
                    try ret.value.str.appendSlice(a.allocator, b.value.str.items);
                    return ret;
                },
                .equality => {
                    const res = a.eql(&b);
                    return Data{ .value = .{
                        .bool = res,
                    } };
                },
                else => unreachable,
            }
        } else {
            switch (op) {
                .repeat => {
                    var copy = try a.copy(a.allocator);
                    errdefer copy.deinit();
                    const slice = a.value.str.items;

                    var i: usize = 1;
                    while (i < @floatToInt(usize, b.value.num)) : (i += 1) {
                        try copy.value.str.appendSlice(a.allocator, slice);
                    }

                    return copy;
                },
                .dot => {
                    // TODO: implement char type to prevent allocator
                    // but have it as an implicit string value
                    const ch = a.value.str.items[@floatToInt(u32, b.value.num)];
                    var copy = Data{ .value = .{ .str = .{} }, .allocator = a.allocator };
                    try copy.value.str.append(a.allocator, ch);
                    return copy;
                },
                else => unreachable,
            }
        }

        unreachable;
    }

    fn arrayOp(op: Token.Type, a: Data, b: Data) !Data {
        if (b.value == .array) {
            switch (op) {
                .concat => {
                    var copy = try a.copy(a.allocator);
                    try copy.value.array.ensureTotalCapacity(a.allocator, a.value.array.items.len + b.value.array.items.len);

                    var i: usize = 0;
                    while (i < b.value.array.items.len) : (i += 1)
                        try copy.value.array.append(a.allocator, try b.value.array.items[i].copy(a.allocator));
                    return copy;
                },
                else => unreachable,
            }
        } else if (b.value == .num) {
            switch (op) {
                .dot => {
                    const item = a.value.array.items[@floatToInt(u32, b.value.num)];
                    return try item.copy(a.allocator);
                },
                else => unreachable,
            }
        }

        unreachable;
    }

    fn mapOp(op: Token.Type, a: Data, b: Data) !Data {
        if (b.value == .str) {
            switch (op) {
                .dot => {
                    var obj = a.value.map.get(b.value.str.items).?;
                    return try obj.copy(a.allocator);
                },
                else => unreachable,
            }
        }

        unreachable;
    }
};

pub const Parser = struct {
    lexer: Lexer,
    token: Token,
    global: Data,
    allocator: Allocator,
    error_context: ?ErrorContext = null,

    const BinOpDesc = struct {
        op: Token.Type,
        lhs: Data.Type,
        rhs: Data.Type,
        func: fn (op: Token.Type, a: Data, b: Data) Allocator.Error!Data,
    };

    // Supported operations:
    //    num [+][-][*][/][//][%] num -> num
    //    num [>][<][>=][<=] num -> bool
    //    str [++] str -> str
    //    str [**] num -> str
    //    str [.] num -> str
    //    arr [++] arr -> arr
    //    arr [.] num -> Data
    //    map [.] str -> Data
    const bin_op_list = &[_]BinOpDesc{
        .{ .op = .amp, .lhs = .bool, .rhs = .bool, .func = Operation.boolOp },
        .{ .op = .@"or", .lhs = .bool, .rhs = .bool, .func = Operation.boolOp },
        .{ .op = .equality, .lhs = .bool, .rhs = .bool, .func = Operation.boolOp },

        .{ .op = .plus, .lhs = .num, .rhs = .num, .func = Operation.numOp },
        .{ .op = .minus, .lhs = .num, .rhs = .num, .func = Operation.numOp },
        .{ .op = .multiply, .lhs = .num, .rhs = .num, .func = Operation.numOp },
        .{ .op = .divide, .lhs = .num, .rhs = .num, .func = Operation.numOp },
        .{ .op = .floor, .lhs = .num, .rhs = .num, .func = Operation.numOp },
        .{ .op = .modulo, .lhs = .num, .rhs = .num, .func = Operation.numOp },

        .{ .op = .greater, .lhs = .num, .rhs = .num, .func = Operation.numOp },
        .{ .op = .less, .lhs = .num, .rhs = .num, .func = Operation.numOp },
        .{ .op = .greater_eql, .lhs = .num, .rhs = .num, .func = Operation.numOp },
        .{ .op = .less_eql, .lhs = .num, .rhs = .num, .func = Operation.numOp },
        .{ .op = .equality, .lhs = .num, .rhs = .num, .func = Operation.numOp },

        .{ .op = .concat, .lhs = .str, .rhs = .str, .func = Operation.stringOp },
        .{ .op = .equality, .lhs = .str, .rhs = .str, .func = Operation.stringOp },
        .{ .op = .repeat, .lhs = .str, .rhs = .num, .func = Operation.stringOp },
        .{ .op = .dot, .lhs = .str, .rhs = .num, .func = Operation.stringOp },

        .{ .op = .concat, .lhs = .array, .rhs = .array, .func = Operation.arrayOp },
        .{ .op = .dot, .lhs = .array, .rhs = .num, .func = Operation.arrayOp },

        .{ .op = .dot, .lhs = .map, .rhs = .str, .func = Operation.mapOp },
    };

    const Self = @This();

    pub const ErrorContext = struct {
        line: usize,
        err: []const u8,
    };

    pub const Error = Allocator.Error || std.fmt.ParseFloatError || error{ParseError};

    pub fn init(src: []const u8, allocator: Allocator) Self {
        return .{
            .lexer = Lexer.init(src),
            .global = Data{ .value = .{ .map = .{} }, .allocator = allocator },
            .token = undefined,
            .allocator = allocator,
        };
    }

    pub fn free(self: *Self) void {
        self.lexer.free();
    }

    fn skipBlock(self: *Self, begin: lex.Token.Type, end: lex.Token.Type) !void {
        if (self.token.toktype != begin)
            return self.setErrorContext("Expected block");

        var count: usize = 1;
        while (count > 0) {
            _ = self.advance();
            if (self.token.toktype == begin) count += 1;
            if (self.token.toktype == end) count -= 1;
        }

        _ = self.advance();
    }

    fn parseReturnValue(self: *Self, source: *Data) Error!Data {
        if (self.token.toktype != .l_brac)
            return self.setErrorContext("Expected '{'");
        _ = self.advance();
        const ret = try self.parseExpr(source);
        if (self.token.toktype != .r_brac)
            return self.setErrorContext("Expected '}'");
        _ = self.advance();
        return ret;
    }

    fn parseAtom(self: *Self, source: *Data) Error!Data {
        const token = self.token;
        switch (token.toktype) {
            .number => {
                _ = self.advance();
                const num = try std.fmt.parseFloat(f64, token.content);
                return Data{ .value = .{ .num = num } };
            },
            .string => {
                _ = self.advance();
                var str = Data{ .value = .{ .str = .{} }, .allocator = self.allocator };

                // Handle escape sequence in strings
                var index: usize = 0;
                while (index < token.content.len) : (index += 1) {
                    try str.value.str.append(self.allocator, if (token.content[index] == '\\' and index + 1 < token.content.len) blk: {
                        index += 1;
                        break :blk switch (token.content[index]) {
                            'r' => '\r',
                            't' => '\t',
                            'n' => '\n',
                            '\"' => '\"',
                            '\'' => '\'',
                            '\\' => '\\',
                            else => token.content[index],
                        };
                    } else token.content[index]);
                }

                return str;
            },
            .raw_string => {
                _ = self.advance();
                var str = Data{ .value = .{ .str = .{} }, .allocator = self.allocator };

                try str.value.str.appendSlice(self.allocator, token.content);

                // Multi line string concat
                while (self.token.toktype == .raw_string) {
                    try str.value.str.appendSlice(self.allocator, self.token.content);
                    _ = self.advance();
                }
                _ = str.value.str.pop();

                return str;
            },
            .@"true", .@"false" => {
                _ = self.advance();
                return Data{ .value = .{ .bool = if (token.toktype == .@"true") true else false } };
            },
            .l_sqr => {
                _ = self.advance();
                var arr = Data{ .value = .{ .array = .{} }, .allocator = self.allocator };
                while (self.token.toktype != .r_sqr) {
                    try arr.value.array.append(self.allocator, try self.parseExpr(source));
                    if (self.token.toktype != .comma) {
                        _ = self.advance();
                        return arr;
                    }
                    _ = self.advance();
                }
                return arr;
            },
            .l_brac => {
                _ = self.advance();
                var obj = try self.parseObject(source);
                _ = self.advance();
                return obj;
            },
            .identifier => {
                _ = self.advance();
                var val = blk: {
                    if (std.mem.eql(u8, token.content, "self")) {
                        break :blk source.*;
                    } else {
                        var obj = self.global.value.map.get(token.content).?;
                        break :blk try obj.copy(self.allocator);
                    }
                };

                if (self.token.toktype == .dot) {
                    // What an ugly hack!
                    // Basically, lexer cannot be advanced here otherwise it breaks
                    // the whole parser. It has to be dealt somewhere else.
                    // In the meanwhile, hopefully this unpredicable mess works.
                    if (std.ascii.isAlNum(self.lexer.src[self.lexer.pos]) and val.value == .map) {
                        _ = self.advance();
                        if (self.token.toktype == .identifier) {
                            const subval = val.value.map.get(self.token.content).?;
                            _ = self.advance();
                            return subval.copy(self.allocator);
                        }
                    }
                }

                return val;
            },
            .@"if" => {
                // TODO: better errors
                while (self.token.toktype == .@"if") {
                    _ = self.advance();
                    const res = try self.parseParenExpr(source);
                    if (res.value != .bool)
                        return self.setErrorContext("Expected bool expression as condition");

                    const expr = try self.parseReturnValue(source);
                    if (res.value.bool == true) {
                        // Skip else part
                        while (self.token.toktype == .@"else") {
                            _ = self.advance();
                            if (self.token.toktype == .@"if") {
                                // Skip condition
                                _ = self.advance();
                                try self.skipBlock(.l_paren, .r_paren);
                            }

                            // Skip return block
                            try self.skipBlock(.l_brac, .r_brac);
                        }
                        return expr;
                    }

                    // Else part
                    if (self.token.toktype != .@"else")
                        return self.setErrorContext("Expected 'else' after 'if'");

                    _ = self.advance();
                    if (self.token.toktype == .@"if")
                        continue;

                    return try self.parseReturnValue(source);
                }

                unreachable;
            },
            else => {
                return try self.parseParenExpr(source);
            },
        }
    }

    // Supported operations:
    //    [-] num -> num
    //    [!] bool -> bool
    fn unOp(self: *Self, source: *Data) Error!Data {
        const token = self.token;

        if (token.toktype == .minus) {
            _ = self.advance();
            var val = try self.unOp(source);
            switch (val.value) {
                .num => val.value.num = -val.value.num,
                else => return self.setErrorContext("'negate' operator not used with num type"),
            }
            return val;
        } else if (token.toktype == .bang) {
            _ = self.advance();
            var val = try self.unOp(source);
            switch (val.value) {
                .bool => val.value.bool = !val.value.bool,
                else => return self.setErrorContext("'not' operator not used with bool type"),
            }
            return val;
        }

        return try self.parseAtom(source);
    }

    inline fn binOpPrec(self: *Self) isize {
        return switch (self.token.toktype) {
            .amp, .@"or" => 8,
            .equality => 9,
            .greater, .less, .greater_eql, .less_eql => 10,
            .plus, .concat, .minus => 12,
            .multiply, .repeat, .divide, .floor, .modulo => 13,
            .dot => 15,
            else => -1,
        };
    }

    inline fn executeBinOp(self: *Self, op: Token.Type, lhs: Data, rhs: Data) !Data {
        _ = self;
        for (bin_op_list) |bin_op| {
            if (bin_op.op == op and lhs.value == bin_op.lhs and rhs.value == bin_op.rhs) {
                return try bin_op.func(op, lhs, rhs);
            }
        }

        // TODO: error on wrong types
        unreachable;
    }

    fn binOp(self: *Self, prec: isize, lhsx: Data, source: *Data) Error!Data {
        var lhs = lhsx;
        var rhs: Data = undefined;

        while (true) {
            const tok_prec = self.binOpPrec();

            if (tok_prec < prec) {
                return lhs;
            }

            const oper = self.token.toktype;

            _ = self.advance();
            rhs = try self.parseAtom(source);

            const next_proc = self.binOpPrec();
            if (tok_prec < next_proc) {
                rhs = try self.binOp(tok_prec + 1, rhs, source);
            }

            var val = try self.executeBinOp(oper, lhs, rhs);
            lhs.deinit();
            rhs.deinit();

            lhs = val;
        }

        return lhs;
    }

    fn parseExpr(self: *Self, source: *Data) Error!Data {
        const lhs = try self.unOp(source);
        return try self.binOp(0, lhs, source);
    }

    fn parseParenExpr(self: *Self, source: *Data) Error!Data {
        if (self.token.toktype != .l_paren)
            return self.setErrorContext("Expected '('");
        _ = self.advance();
        var res = try self.parseExpr(source);
        if (self.token.toktype != .r_paren)
            return self.setErrorContext("Expected ')'");
        _ = self.advance();
        return res;
    }

    fn parseObjectNoscope(self: *Self, map: *Data.Map, source: *Data) Error!void {
        while (self.token.toktype == .identifier) {
            const key = self.token.content;

            switch (self.advance()) {
                .assignment => {
                    _ = self.advance();
                    var val = try self.parseExpr(source);

                    try map.put(self.allocator, key, val);

                    if (self.token.toktype != .semicolon)
                        return self.setErrorContext("Expected ';' at the end of statement");

                    _ = self.advance();
                },
                else => return,
            }
        }
    }

    inline fn parseObject(self: *Self, source: *Data) Error!Data {
        _ = source; // This parameter exists just for the sake of consistency
        var map = Data{ .value = .{ .map = .{} }, .allocator = self.allocator };
        try self.parseObjectNoscope(&map.value.map, &map);
        if (self.token.toktype != .r_brac)
            return map;
        return map;
    }

    pub fn parse(self: *Self) Error!void {
        if (self.advance() != .eof) {
            try self.parseObjectNoscope(&self.global.value.map, &self.global);
        }
    }

    fn advance(self: *Self) lex.Token.Type {
        self.token = self.lexer.getToken();
        return self.token.toktype;
    }

    fn setErrorContext(self: *Self, err: []const u8) Error {
        self.error_context = .{
            .line = self.lexer.line,
            .err = err,
        };

        return error.ParseError;
    }

    pub fn getErrorContext(self: *Self) ?ErrorContext {
        return self.error_context;
    }
};

test "basic test" {
    const allocator = std.testing.allocator;
    const expectEqual = std.testing.expectEqual;
    const expectEqualStrings = std.testing.expectEqualStrings;

    var parser = Parser.init(
        \\ num = 10;
        \\ str = "string";
        \\ raw_str = \\multi-lined
        \\ \\ raw_string
        \\ ;
        \\ array = ["test", 10, "element" ];
        \\ table = {
        \\     hello = "world";
        \\ };
    , allocator);
    defer parser.free();
    try parser.parse();
    defer parser.global.free();

    try expectEqual(@as(f64, 10), (try parser.global.find("num")).value.num);
    try expectEqualStrings("string", (try parser.global.find("str")).value.str.items);
    try expectEqualStrings("multi-lined\n raw_string", (try parser.global.find("raw_str")).value.str.items);
}
