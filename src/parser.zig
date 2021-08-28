const std = @import("std");
const Allocator = std.mem.Allocator;
const lex = @import("lexer.zig");
const Lexer = lex.Lexer;
const Token = lex.Token;
const data = @import("data.zig");
const Data = data.Data;

pub const Parser = struct {
    lexer: Lexer,
    token: Token,
    global: Data,
    allocator: *Allocator,
    error_context: ?ErrorContext = null,

    const Self = @This();

    pub const ErrorContext = struct {
        line: usize,
        err: ParseError,
    };

    pub const ParseError = error{
        invalid_operator,
        mismatched_operands,
    };

    pub const Error = Allocator.Error || std.fmt.ParseFloatError || ParseError;

    pub fn init(src: []const u8, allocator: *Allocator) Self {
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

    fn parseAtom(self: *Self, source: *Data) Error!Data {
        const token = self.token;
        _ = self.advance();
        switch (token.toktype) {
            .number => {
                const num = try std.fmt.parseFloat(f64, token.content);
                return Data{ .name = "", .value = .{ .num = num } };
            },
            .string => {
                var str = Data.initString("", self.allocator);
                try str.value.str.appendSlice(token.content);
                return str;
            },
            .lsqr => {
                var arr = Data.initArray("", self.allocator);
                while (self.token.toktype != .rsqr) {
                    try arr.value.arr.append(try self.parseExpr(source));
                    if (self.token.toktype != .comma) {
                        _ = self.advance();
                        return arr;
                    }
                    _ = self.advance();
                }
                return arr;
            },
            .lbra => {
                var obj = try self.parseObject(source);
                return obj;
            },
            .identifier => {
                var val = blk: {
                    if (std.mem.eql(u8, token.content, "global")) {
                        break :blk self.global;
                    } else {
                        var obj = source.value.map.get(token.content).?;
                        break :blk try obj.makeCopy(self.allocator);
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
                            return subval.makeCopy(self.allocator);
                        }
                    }
                }

                return val;
            },
            else => {
                return try self.parseParenExpr(source);
            },
        }
    }

    inline fn binOpPrec(self: *Self) isize {
        return switch (self.token.toktype) {
            .plus, .concat, .minus => 12,
            .multiply, .repeat, .divide, .floor, .modulo => 13,
            .dot => 15,
            else => -1,
        };
    }

    // Supported operations:
    //    num [+][-][*][/][//][%] num -> num
    //    str [++] str -> str
    //    str [**] num -> str
    //    arr [++] arr -> arr
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
                .num => {
                    lhs.value.num = if (rhs.value == .num)
                        switch (oper) {
                            .plus => lhs.value.num + rhs.value.num,
                            .minus => lhs.value.num - rhs.value.num,
                            .multiply => lhs.value.num * rhs.value.num,
                            .divide => lhs.value.num / rhs.value.num,
                            .floor => @divFloor(lhs.value.num, rhs.value.num),
                            .modulo => @mod(lhs.value.num, rhs.value.num),
                            else => return self.setErrorContext(ParseError.invalid_operator),
                        }
                    else
                        return self.setErrorContext(ParseError.mismatched_operands);
                },
                .str => {
                    if (rhs.value == .str) {
                        switch (oper) {
                            .concat => try lhs.value.str.appendSlice(rhs.value.str.items),
                            else => return self.setErrorContext(ParseError.invalid_operator),
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
                            else => return self.setErrorContext(ParseError.invalid_operator),
                        }
                    } else return self.setErrorContext(ParseError.mismatched_operands);
                },
                .arr => {
                    if (rhs.value == .arr) {
                        switch (oper) {
                            .concat => {
                                var i: usize = 0;
                                try lhs.value.arr.ensureTotalCapacity(lhs.value.arr.items.len + rhs.value.arr.items.len);
                                while (i < rhs.value.arr.items.len) : (i += 1)
                                    try lhs.value.arr.append(rhs.value.arr.items[i]);
                            },
                            else => return self.setErrorContext(ParseError.invalid_operator),
                        }
                    } else return self.setErrorContext(ParseError.mismatched_operands);
                },
                .map => {
                    if (rhs.value == .str) {
                        switch (oper) {
                            .dot => {
                                var obj = self.global.value.map.get(rhs.value.str.items).?;
                                lhs = try obj.makeCopy(self.allocator);
                            },
                            else => return self.setErrorContext(ParseError.invalid_operator),
                        }
                    } else return self.setErrorContext(ParseError.mismatched_operands);
                },
            }

            rhs.free();
        }

        return lhs;
    }

    fn parseExpr(self: *Self, source: *Data) Error!Data {
        const lhs = try self.parseAtom(source);
        return try self.binOp(0, lhs, source);
    }

    fn parseParenExpr(self: *Self, source: *Data) Error!Data {
        if (self.token.toktype != .lpar)
            return ParseError.invalid_operator;
        _ = self.advance();
        var res = try self.parseExpr(source);
        if (self.token.toktype != .rpar)
            return ParseError.invalid_operator;
        return res;
    }

    fn parseObjectNoscope(self: *Self, map: *data.MapType, source: *Data) Error!void {
        while (self.token.toktype == .identifier) {
            const key = self.token.content;

            switch (self.advance()) {
                .assignment => {
                    _ = self.advance();
                    var val = try self.parseExpr(source);
                    val.name = key;

                    try map.put(key, val);

                    if (self.token.toktype != .semicolon) {
                        return;
                    }
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

    fn setErrorContext(self: *Self, err: ParseError) Error {
        self.error_context = .{
            .line = self.lexer.line,
            .err = err,
        };

        return err;
    }

    pub fn getErrorContext(self: *Self) ?ErrorContext {
        return self.error_context;
    }
};
