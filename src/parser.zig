const std = @import("std");
const Allocator = std.mem.Allocator;
const lex = @import("lexer.zig");
const Lexer = lex.Lexer;
const Token = lex.Token;
const TokenType = lex.TokenType;
const Data = @import("Data.zig");

const Operation = struct {
    fn numOp(op: TokenType, a: Data, b: Data) !Data {
        const a_n = a.value.num;
        const b_n = b.value.num;
        return Data{ .name = "", .value = switch (op) {
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
            .greateql => .{ .bool = a_n >= b_n },
            .lesseql => .{ .bool = a_n <= b_n },
            .equality => .{ .bool = a_n == b_n },
            else => unreachable,
        } };
    }

    fn stringOp(op: TokenType, a: Data, b: Data) !Data {
        if (b.value == .str) {
            switch (op) {
                .concat => {
                    var ret = try a.copy(a.allocator);
                    try ret.value.str.appendSlice(b.value.str.items);
                    return ret;
                },
                .equality => {
                    const res = a.eql(&b);
                    return Data{ .name = "", .value = .{
                        .bool = res,
                    } };
                },
                else => unreachable,
            }
        } else {
            switch (op) {
                .repeat => {
                    var copy = try a.copy(a.allocator);
                    errdefer copy.free();
                    const slice = a.value.str.items;

                    var i: usize = 1;
                    while (i < @floatToInt(usize, b.value.num)) : (i += 1) {
                        try copy.value.str.appendSlice(slice);
                    }

                    return copy;
                },
                .dot => {
                    // TODO: implement char type to prevent allocator
                    // but have it as an implicit string value
                    const ch = a.value.str.items[@floatToInt(u32, b.value.num)];
                    var copy = Data.initString("", a.allocator);
                    try copy.value.str.append(ch);
                    return copy;
                },
                else => unreachable,
            }
        }

        unreachable;
    }
    
    fn arrayOp(op: TokenType, a: Data, b: Data) !Data {
        if (b.value == .array) {
            switch (op) {
                .concat => {
                    var copy = try a.copy(a.allocator);
                    try copy.value.array.ensureTotalCapacity(a.value.array.items.len + b.value.array.items.len);
                
                    var i: usize = 0;
                    while (i < b.value.array.items.len) : (i += 1)
                        try copy.value.array.append(try b.value.array.items[i].copy(a.allocator));
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
    
    fn mapOp(op: TokenType, a: Data, b: Data) !Data {
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
        op: TokenType,
        lhs: Data.Type,
        rhs: Data.Type,
        func: fn (op: TokenType, a: Data, b: Data) Allocator.Error!Data,
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
        .{ .op = .plus, .lhs = .num, .rhs = .num, .func = Operation.numOp },
        .{ .op = .minus, .lhs = .num, .rhs = .num, .func = Operation.numOp },
        .{ .op = .multiply, .lhs = .num, .rhs = .num, .func = Operation.numOp },
        .{ .op = .divide, .lhs = .num, .rhs = .num, .func = Operation.numOp },
        .{ .op = .floor, .lhs = .num, .rhs = .num, .func = Operation.numOp },
        .{ .op = .modulo, .lhs = .num, .rhs = .num, .func = Operation.numOp },

        .{ .op = .greater, .lhs = .num, .rhs = .num, .func = Operation.numOp },
        .{ .op = .less, .lhs = .num, .rhs = .num, .func = Operation.numOp },
        .{ .op = .greateql, .lhs = .num, .rhs = .num, .func = Operation.numOp },
        .{ .op = .lesseql, .lhs = .num, .rhs = .num, .func = Operation.numOp },
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

    inline fn executeBinOp(self: *Self, op: TokenType, lhs: Data, rhs: Data) !Data {
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
            lhs.free();
            rhs.free();
            
            lhs = val;
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
