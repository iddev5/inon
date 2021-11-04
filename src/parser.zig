const std = @import("std");
const Allocator = std.mem.Allocator;
const lex = @import("lexer.zig");
const Lexer = lex.Lexer;
const Token = lex.Token;
const Data = @import("Data.zig");

pub const Parser = struct {
    lexer: Lexer,
    token: Token,
    global: Data,
    allocator: Allocator,
    error_context: ?ErrorContext = null,

    const Self = @This();

    pub const ErrorContext = struct {
        line: usize,
        err: []const u8,
    };

    pub const Error = Allocator.Error || std.fmt.ParseFloatError || error{ParseError};

    pub fn init(src: []const u8, allocator: Allocator) Self {
        return .{
            .lexer = Lexer.init(src),
            .global = Data.initMap("global", allocator),
            .token = undefined,
            .allocator = allocator,
        };
    }

    pub fn free(self: *Self) void {
        self.lexer.free();
    }

    fn skipBlock(self: *Self, begin: lex.TokenType, end: lex.TokenType) !void {
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
        if (self.token.toktype != .lbra)
            return self.setErrorContext("Expected '{'");
        _ = self.advance();
        const ret = try self.parseExpr(source);
        if (self.token.toktype != .rbra)
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
                return Data{ .name = "", .value = .{ .num = num } };
            },
            .string => {
                _ = self.advance();
                var str = Data.initString("", self.allocator);

                // Handle escape sequence in strings
                var index: usize = 0;
                while (index < token.content.len) : (index += 1) {
                    try str.value.str.append(if (token.content[index] == '\\' and index + 1 < token.content.len) blk: {
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
                var str = Data.initString("", self.allocator);

                try str.value.str.appendSlice(token.content);

                // Multi line string concat
                while (self.token.toktype == .raw_string) {
                    try str.value.str.appendSlice(self.token.content);
                    _ = self.advance();
                }
                _ = str.value.str.pop();

                return str;
            },
            .tru, .fals => {
                _ = self.advance();
                return Data{ .name = "", .value = .{ .bool = if (token.toktype == .tru) true else false } };
            },
            .lsqr => {
                _ = self.advance();
                var arr = Data.initArray("", self.allocator);
                while (self.token.toktype != .rsqr) {
                    try arr.value.array.append(try self.parseExpr(source));
                    if (self.token.toktype != .comma) {
                        _ = self.advance();
                        return arr;
                    }
                    _ = self.advance();
                }
                return arr;
            },
            .lbra => {
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
            .iff => {
                // TODO: better errors
                while (self.token.toktype == .iff) {
                    _ = self.advance();
                    const res = try self.parseParenExpr(source);
                    if (res.value != .bool)
                        return self.setErrorContext("Expected bool expression as condition");

                    const expr = try self.parseReturnValue(source);
                    if (res.value.bool == true) {
                        // Skip else part
                        while (self.token.toktype == .els) {
                            _ = self.advance();
                            if (self.token.toktype == .iff) {
                                // Skip condition
                                _ = self.advance();
                                try self.skipBlock(.lpar, .rpar);
                            }

                            // Skip return block
                            try self.skipBlock(.lbra, .rbra);
                        }
                        return expr;
                    }

                    // Else part
                    if (self.token.toktype != .els)
                        return self.setErrorContext("Expected 'else' after 'if'");

                    _ = self.advance();
                    if (self.token.toktype == .iff)
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
            .amp, .orop => 8,
            .equality => 9,
            .greater, .less, .greateql, .lesseql => 10,
            .plus, .concat, .minus => 12,
            .multiply, .repeat, .divide, .floor, .modulo => 13,
            .dot => 15,
            else => -1,
        };
    }

    // Supported operations:
    //    num [+][-][*][/][//][%] num -> num
    //    num [>][<][>=][<=] num -> bool
    //    str [++] str -> str
    //    str [**] num -> str
    //    str [.] num -> str
    //    arr [++] arr -> arr
    //    arr [.] num -> Data
    //    map [.] str -> Data
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

            switch (lhs.value) {
                .bool => {
                    if (rhs.value == .bool) {
                        switch (oper) {
                            .amp => lhs.value.bool = lhs.value.bool and rhs.value.bool,
                            .orop => lhs.value.bool = lhs.value.bool or rhs.value.bool,
                            .equality => lhs.value.bool = lhs.eql(&rhs),
                            else => return self.setErrorContext("Invalid operand used with logical operator"),
                        }
                    } else return self.setErrorContext("Mismatched operand types, expected bool and bool");
                },
                .num => {
                    if (rhs.value == .num) {
                        switch (oper) {
                            .plus => lhs.value.num = lhs.value.num + rhs.value.num,
                            .minus => lhs.value.num = lhs.value.num - rhs.value.num,
                            .multiply => lhs.value.num = lhs.value.num * rhs.value.num,
                            .divide => lhs.value.num = lhs.value.num / rhs.value.num,
                            .floor => lhs.value.num = @divFloor(lhs.value.num, rhs.value.num),
                            .modulo => lhs.value.num = @mod(lhs.value.num, rhs.value.num),
                            else => {
                                var booldata = Data{ .name = "", .value = .{ .bool = false } };
                                switch (oper) {
                                    .greater => booldata.value.bool = lhs.value.num > rhs.value.num,
                                    .less => booldata.value.bool = lhs.value.num < rhs.value.num,
                                    .greateql => booldata.value.bool = lhs.value.num >= rhs.value.num,
                                    .lesseql => booldata.value.bool = lhs.value.num <= rhs.value.num,
                                    .equality => booldata.value.bool = lhs.eql(&rhs),
                                    else => return self.setErrorContext("Invalid operand used with arithmetic operator"),
                                }
                                lhs = booldata;
                            },
                        }
                    } else return self.setErrorContext("Mismatched operand types, expected num and num");
                },
                .str => {
                    if (rhs.value == .str) {
                        switch (oper) {
                            .concat => try lhs.value.str.appendSlice(rhs.value.str.items),
                            .equality => {
                                const res = lhs.eql(&rhs);
                                lhs.free();
                                lhs = Data{ .name = "", .value = .{
                                    .bool = res,
                                } };
                            },
                            else => return self.setErrorContext("Invalid operator used for string operations"),
                        }
                    } else if (rhs.value == .num) {
                        switch (oper) {
                            .repeat => {
                                var i: usize = 1;
                                const slice = try self.allocator.alloc(u8, lhs.value.str.items.len);
                                defer self.allocator.free(slice);
                                std.mem.copy(u8, slice, lhs.value.str.items);
                                while (i < @floatToInt(usize, rhs.value.num)) : (i += 1) {
                                    try lhs.value.str.appendSlice(slice);
                                }
                            },
                            .dot => {
                                const ch = lhs.value.str.items[@floatToInt(u32, rhs.value.num)];
                                lhs.value.str.shrinkAndFree(0);
                                try lhs.value.str.append(ch);
                            },
                            else => return self.setErrorContext("Invalid operator used for string operations"),
                        }
                    } else return self.setErrorContext("Mismatched operand types, expected str and str or num");
                },
                .array => {
                    if (rhs.value == .array) {
                        switch (oper) {
                            .concat => {
                                var i: usize = 0;
                                try lhs.value.array.ensureTotalCapacity(lhs.value.array.items.len + rhs.value.array.items.len);
                                while (i < rhs.value.array.items.len) : (i += 1)
                                    try lhs.value.array.append(rhs.value.array.items[i]);
                            },
                            else => return self.setErrorContext("Invalid operand used for array operations"),
                        }
                    } else if (rhs.value == .num) {
                        switch (oper) {
                            .dot => {
                                const item = lhs.value.array.items[@floatToInt(u32, rhs.value.num)];
                                lhs.free();
                                lhs = try item.copy(self.allocator);
                            },
                            else => return self.setErrorContext("Invalid operand used for array operations"),
                        }
                    } else return self.setErrorContext("Mismatched operand types, expected array and num");
                },
                .map => {
                    if (rhs.value == .str) {
                        switch (oper) {
                            .dot => {
                                var obj = self.global.value.map.get(rhs.value.str.items).?;
                                lhs = try obj.copy(self.allocator);
                            },
                            else => return self.setErrorContext("Invalid operand used for map operations"),
                        }
                    } else return self.setErrorContext("Mismatched operand types, expected map and str");
                },
            }

            rhs.free();
        }

        return lhs;
    }

    fn parseExpr(self: *Self, source: *Data) Error!Data {
        const lhs = try self.unOp(source);
        return try self.binOp(0, lhs, source);
    }

    fn parseParenExpr(self: *Self, source: *Data) Error!Data {
        if (self.token.toktype != .lpar)
            return self.setErrorContext("Expected '('");
        _ = self.advance();
        var res = try self.parseExpr(source);
        if (self.token.toktype != .rpar)
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
                    val.name = key;

                    try map.put(key, val);

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
        var map = Data.initMap("", self.allocator);
        try self.parseObjectNoscope(&map.value.map, &map);
        if (self.token.toktype != .rbra)
            return map;
        return map;
    }

    pub fn parse(self: *Self) Error!void {
        if (self.advance() != .eof) {
            try self.parseObjectNoscope(&self.global.value.map, &self.global);
        }
    }

    fn advance(self: *Self) lex.TokenType {
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

    try expectEqual(@as(f64, 10), (try parser.global.get("num")).value.num);
    try expectEqualStrings("string", (try parser.global.get("str")).value.str.items);
    try expectEqualStrings("multi-lined\n raw_string", (try parser.global.get("raw_str")).value.str.items);
}
