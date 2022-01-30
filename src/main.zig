const std = @import("std");
const mem = std.mem;
const allocPrint = std.fmt.allocPrint;
const Allocator = mem.Allocator;
const ptk = @import("parser-toolkit");
pub const Data = @import("Data.zig");
pub const Stdlib = @import("Stdlib.zig");

const Inon = @This();

allocator: Allocator,
functions: FuncList,
context: Data,
current_context: *Data,
message: ?Message,

const Message = struct {
    location: ptk.Location,
    message: []const u8,

    pub fn free(self: @This(), allocator: Allocator) void {
        allocator.free(self.message);
    }
};

const Error = mem.Allocator.Error;

pub const FuncFnType = fn (inon: *Inon, params: []Data) Error!Data;
pub const FuncType = struct {
    name: []const u8,
    params: []const ?Data.Type,
    run: FuncFnType,
};
pub const FuncList = std.StringArrayHashMapUnmanaged(FuncType);

pub fn init(allocator: Allocator) Inon {
    return .{
        .allocator = allocator,
        .message = null,
        .functions = .{},
        .context = .{ .value = .{ .map = .{} }, .allocator = allocator },
        .current_context = undefined,
    };
}

pub fn deinit(inon: *Inon) void {
    if (inon.message) |message| message.free(inon.allocator);
    inon.functions.deinit(inon.allocator);
    inon.context.deinit();
}

pub fn parse(inon: *Inon, src: []const u8) !Data {
    var result = try Parser.parse(src, inon);
    errdefer result.free();
    return result;
}

pub fn serialize(inon: *Inon, data: *Data, writer: anytype) !void {
    _ = inon;
    try data.serialize(4, writer);
}

pub fn renderError(inon: *Inon, writer: anytype) !void {
    const loc = inon.message.?.location;
    const msg = inon.message.?.message;
    try writer.print(
        "{s}:{}:{} error: {s}\n",
        .{ loc.source, loc.line, loc.column, msg },
    );
}

const matchers = ptk.matchers;

const Parser = struct {
    const Self = @This();

    const TokenType = enum {
        number,
        string,
        identifier,
        fn_name,
        whitespace,
        comment,
        @"true",
        @"false",
        @"null",
        @"::",
        @"?:",
        @":",
        @"(",
        @")",
        @"[",
        @"]",
        @"{",
        @"}",
        @",",
        @"-",
    };

    const Pattern = ptk.Pattern(TokenType);

    const Tokenizer = ptk.Tokenizer(TokenType, &[_]Pattern{
        Pattern.create(.number, matchers.sequenceOf(.{ matchers.decimalNumber, matchers.literal("."), matchers.decimalNumber })),
        Pattern.create(.number, matchers.decimalNumber),
        Pattern.create(.string, stringMatcher),
        Pattern.create(.@"true", matchers.literal("true")),
        Pattern.create(.@"false", matchers.literal("false")),
        Pattern.create(.@"null", matchers.literal("null")),
        Pattern.create(.whitespace, matchers.takeAnyOf(" \n\r\t")),
        Pattern.create(.comment, commentMatcher),
        Pattern.create(.@"::", matchers.literal("::")),
        Pattern.create(.@"?:", matchers.literal("?:")),
        Pattern.create(.@":", matchers.literal(":")),
        Pattern.create(.@"[", matchers.literal("[")),
        Pattern.create(.@"]", matchers.literal("]")),
        Pattern.create(.@"(", matchers.literal("(")),
        Pattern.create(.@")", matchers.literal(")")),
        Pattern.create(.@"{", matchers.literal("{")),
        Pattern.create(.@"}", matchers.literal("}")),
        Pattern.create(.@",", matchers.literal(",")),
        Pattern.create(.@"-", matchers.literal("-")),
        Pattern.create(.identifier, identifierMatcher),
    });

    const ParserCore = ptk.ParserCore(Tokenizer, .{ .whitespace, .comment });

    pub fn parse(expression: []const u8, inon: *Inon) ParseError!Data {
        var tokenizer = Tokenizer.init(expression, null);

        var parser = Parser{
            .core = ParserCore.init(&tokenizer),
            .inon = inon,
        };

        parser.inon.current_context = &parser.inon.context;
        return parser.acceptObjectNoCtx(&inon.context);
    }

    core: ParserCore,
    inon: *Inon,

    const ruleset = ptk.RuleSet(TokenType);

    const is_number = ruleset.is(.number);
    const is_identifier = ruleset.is(.identifier);
    const is_string = ruleset.is(.string);
    const is_true = ruleset.is(.@"true");
    const is_false = ruleset.is(.@"false");
    const is_null = ruleset.is(.@"null");
    const is_dualcolon = ruleset.is(.@"::");
    const is_optcolon = ruleset.is(.@"?:");
    const is_colon = ruleset.is(.@":");
    const is_lpar = ruleset.is(.@"(");
    const is_rpar = ruleset.is(.@")");
    const is_lbrac = ruleset.is(.@"{");
    const is_rbrac = ruleset.is(.@"}");
    const is_comma = ruleset.is(.@",");
    const is_lsqr = ruleset.is(.@"[");
    const is_rsqr = ruleset.is(.@"]");
    const is_minus = ruleset.is(.@"-");

    const ParseError = mem.Allocator.Error || ParserCore.Error || error{ParsingFailed};

    fn peek(self: *Self) !?Tokenizer.Token {
        return self.core.peek() catch |err| switch (err) {
            error.UnexpectedCharacter => {
                try self.emitError("found unknown character", .{});
                return error.ParsingFailed;
            },
        };
    }

    fn emitError(self: *Self, comptime format: []const u8, args: anytype) !void {
        const state = self.core.saveState();
        errdefer self.core.restoreState(state);

        self.inon.message = .{
            .location = state.location,
            .message = try allocPrint(self.inon.allocator, format, args),
        };
    }

    fn acceptAssignment(self: *Self) ParseError!Data {
        const state = self.core.saveState();
        errdefer self.core.restoreState(state);

        _ = try self.core.accept(is_colon);
        return try acceptAtom(self);
    }

    fn acceptTopLevelExpr(self: *Self, context: *Data) ParseError!void {
        const state = self.core.saveState();
        errdefer self.core.restoreState(state);

        const identifier = (self.core.accept(is_identifier) catch |err| switch (err) {
            error.UnexpectedToken => {
                const tok_type = @tagName((self.peek() catch unreachable).?.type);
                try self.emitError("expected identifier, found '{s}'", .{tok_type});
                return error.ParsingFailed;
            },
            else => |e| return e,
        }).text;

        var prev_data = context.findEx(identifier);
        const prev_exists = !prev_data.is(.nulled);

        const val = blk: {
            if (try self.peek()) |token| {
                if (is_dualcolon(token.type)) {
                    _ = try self.core.accept(is_dualcolon);
                    var cond = try acceptAtom(self);
                    defer cond.deinit();

                    if (cond.is(.bool)) {
                        var expr = try acceptAssignment(self);
                        defer expr.deinit();
                        if (cond.get(.bool)) {
                            if (prev_exists)
                                prev_data.deinit();
                            break :blk try expr.copy(self.inon.allocator);
                        } else {
                            return;
                        }
                    }

                    try self.emitError("expected condition of type 'bool'", .{});
                    return error.ParsingFailed;
                } else if (is_optcolon(token.type)) {
                    _ = try self.core.accept(is_optcolon);
                    var value = try self.acceptAtom();

                    if (prev_exists) {
                        value.deinit();
                        return;
                    }

                    break :blk value;
                } else if (is_colon(token.type)) {
                    if (prev_exists)
                        prev_data.deinit();
                    break :blk try acceptAssignment(self);
                } else {
                    try self.emitError("expected '::', '?:' or ':' after identifier", .{});
                    return error.ParsingFailed;
                }
            } else {
                try self.emitError("found stray identifier", .{});
                return error.ParsingFailed;
            }
        };

        try context.value.map.put(self.inon.allocator, identifier, val);
    }

    fn acceptObjectNoCtx(self: *Self, context: *Data) ParseError!Data {
        const state = self.core.saveState();
        errdefer self.core.restoreState(state);

        while ((try self.peek()) != null) {
            try self.acceptTopLevelExpr(context);
        }

        return context.*;
    }

    fn acceptObject(self: *Self) ParseError!Data {
        const state = self.core.saveState();
        errdefer self.core.restoreState(state);

        _ = try self.core.accept(is_lbrac);
        var data = Data{ .value = .{ .map = .{} }, .allocator = self.inon.allocator };
        errdefer data.deinit();

        const old_context = self.inon.current_context;
        self.inon.current_context = &data;
        defer self.inon.current_context = old_context;

        while (!is_rbrac((try self.peek()).?.type)) {
            try self.acceptTopLevelExpr(&data);
        }

        _ = try self.core.accept(is_rbrac);

        return data;
    }

    fn acceptAtom(self: *Self) ParseError!Data {
        const state = self.core.saveState();
        errdefer self.core.restoreState(state);

        if (try self.peek()) |token| {
            if (is_number(token.type)) {
                return self.acceptAtomNumber();
            } else if (is_minus(token.type)) {
                _ = try self.core.accept(is_minus);
                var num = try self.acceptAtomNumber();
                num.value.num = -num.value.num;
                return num;
            } else if (is_identifier(token.type)) {
                return self.acceptAtomIdentifier();
            } else if (is_string(token.type)) {
                return self.acceptAtomString();
            } else if (is_lpar(token.type)) {
                return self.acceptFunctionCall();
            } else if (is_lsqr(token.type)) {
                return self.acceptAtomList();
            } else if (is_lbrac(token.type)) {
                return self.acceptObject();
            } else if (is_true(token.type)) {
                _ = (try self.core.accept(is_true));
                return Data{ .value = .{ .bool = true } };
            } else if (is_false(token.type)) {
                _ = (try self.core.accept(is_false));
                return Data{ .value = .{ .bool = false } };
            } else if (is_null(token.type)) {
                _ = (try self.core.accept(is_null));
                return Data{ .value = .{ .nulled = .{} } };
            } else {
                try self.emitError("expected expression, literal or function call", .{});
                return error.ParsingFailed;
            }
        }

        unreachable;
    }

    fn acceptAtomNumber(self: *Self) !Data {
        const state = self.core.saveState();
        errdefer self.core.restoreState(state);

        const value = try self.core.accept(is_number);

        return Data{ .value = .{
            .num = std.fmt.parseFloat(f64, value.text) catch unreachable,
        } };
    }

    fn acceptAtomIdentifier(self: *Self) ParseError!Data {
        const state = self.core.saveState();
        errdefer self.core.restoreState(state);

        const token = try self.core.accept(is_identifier);
        const data = self.inon.context.findEx(token.text);
        if (data.is(.nulled)) {
            try self.emitError("undeclared identifier '{s}' referenced", .{token.text});
            return error.ParsingFailed;
        }

        return data.copy(self.inon.allocator);
    }

    fn acceptAtomString(self: *Self) ParseError!Data {
        const state = self.core.saveState();
        errdefer self.core.restoreState(state);

        var token = (try self.core.accept(is_string)).text;
        var str = Data{
            .value = .{ .str = .{} },
            .allocator = self.inon.allocator,
        };
        errdefer str.deinit();

        var raw_string: bool = if (mem.startsWith(u8, token, "\\")) true else false;
        if (raw_string) {
            while (raw_string) {
                try str.value.str.appendSlice(str.allocator, token[2..]);
                try str.value.str.append(str.allocator, '\n');

                if (try self.peek()) |tok| {
                    if (is_string(tok.type)) {
                        token = (try self.core.accept(is_string)).text;
                        raw_string = mem.startsWith(u8, token, "\\");
                    } else break;
                } else break;
            }
        } else {
            var i: usize = 1;
            while (i < token.len - 1) : (i += 1) {
                const next_is_es = token[i] == '\\' and i + 1 < token.len;
                try str.value.str.append(str.allocator, if (next_is_es) blk: {
                    i += 1;
                    break :blk switch (token[i]) {
                        'r' => '\r',
                        't' => '\t',
                        'n' => '\n',
                        '\"' => '\"',
                        '\'' => '\'',
                        '\\' => '\\',
                        else => token[i],
                    };
                } else token[i]);
            }
        }

        return str;
    }

    fn acceptAtomList(self: *Self) ParseError!Data {
        const state = self.core.saveState();
        errdefer self.core.restoreState(state);

        _ = try self.core.accept(is_lsqr);

        var data = Data{ .value = .{ .array = .{} }, .allocator = self.inon.allocator };
        errdefer data.deinit();

        while (try self.peek()) |tok| {
            if (is_rsqr(tok.type)) {
                break;
            }

            try data.value.array.append(data.allocator, try self.acceptAtom());

            const token = (try self.peek()).?;
            if (!is_rsqr(token.type)) {
                if (is_comma(token.type)) {
                    _ = try self.core.accept(is_comma);
                } else {
                    try self.emitError("expected ',' or ']' with list", .{});
                    return error.ParsingFailed;
                }
            }
        }

        _ = try self.core.accept(is_rsqr);

        return data;
    }

    fn acceptFunctionCall(self: *Self) ParseError!Data {
        const state = self.core.saveState();
        errdefer self.core.restoreState(state);

        _ = try self.core.accept(is_lpar);

        const fn_name = blk: {
            const text = (try self.core.accept(is_identifier)).text;
            if (mem.startsWith(u8, text, "'")) {
                break :blk text[1 .. text.len - 1];
            } else {
                break :blk text;
            }
        };

        var args = Data{ .value = .{ .array = .{} }, .allocator = self.inon.allocator };
        defer args.deinit();

        const func = if (self.inon.functions.get(fn_name)) |func| func else unreachable;
        const param_count = func.params.len;

        while (try self.peek()) |tok| {
            if (is_rpar(tok.type)) {
                break;
            }

            const arg = try self.acceptAtom();
            try args.value.array.append(args.allocator, arg);
        }

        // Validate argument count
        const no_of_args = args.get(.array).items.len;
        if (no_of_args != param_count) {
            try self.emitError("function '{s}' takes {} args, found {}", .{ fn_name, param_count, no_of_args });
            return error.ParsingFailed;
        }

        // Validate argument type
        for (func.params) |param, index| {
            if (param) |par| {
                const arg = args.get(.array).items[index];
                if (!arg.is(par)) {
                    try self.emitError(
                        "function '{s}' expects argument {} be of type '{s}' while '{s}' is given",
                        .{
                            fn_name,
                            index,
                            @tagName(par),
                            @tagName(arg.value),
                        },
                    );
                    return error.ParsingFailed;
                }
            }
        }

        _ = try self.core.accept(is_rpar);

        // Run the function and return the result
        return try func.run(self.inon, args.get(.array).items);
    }
};

// Tokenizer helpers

fn stringMatcher(str: []const u8) ?usize {
    const raw_string = mem.startsWith(u8, str, "\\");
    if (!(mem.startsWith(u8, str, "\"") or raw_string))
        return null;

    var i: usize = 1;
    while (i < str.len) : (i += 1) {
        switch (str[i]) {
            '\\' => i += 1,
            '\"' => if (!raw_string) {
                i += 1;
                break;
            },
            '\n' => if (raw_string) break,
            else => {},
        }
    }

    return i;
}

fn identifierMatcher(str: []const u8) ?usize {
    const first_char = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ" ++ "!#$%&'*+-./;<=>@\\^_`|~";
    const all_chars = first_char ++ "0123456789";
    for (str) |c, i| {
        if (std.mem.indexOfScalar(u8, if (i > 0) all_chars else first_char, c) == null) {
            return i;
        }
    }
    return str.len;
}

fn commentMatcher(str: []const u8) ?usize {
    if (!(mem.startsWith(u8, str, "#")))
        return null;

    var i: usize = 0;
    while (i < str.len) : (i += 1) {
        if (str[i] == '\n') break;
    }

    return i;
}
