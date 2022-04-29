const std = @import("std");
const mem = std.mem;
const Allocator = mem.Allocator;
const ptk = @import("parser-toolkit");
pub const Data = @import("Data.zig");
pub const Stdlib = @import("Stdlib.zig");

const Inon = @This();

allocator: Allocator,
functions: FuncList,
context: Data,
current_context: *Data,
diagnostics: ptk.Diagnostics,

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
        .diagnostics = ptk.Diagnostics.init(allocator),
        .functions = .{},
        .context = .{ .value = .{ .map = .{} }, .allocator = allocator },
        .current_context = undefined,
    };
}

pub fn deinit(inon: *Inon) void {
    inon.diagnostics.deinit();
    inon.functions.deinit(inon.allocator);
    inon.context.deinit();
}

pub fn parse(inon: *Inon, name: []const u8, src: []const u8) !Data {
    var result = try Parser.parse(src, name, inon);
    errdefer result.free();
    return result;
}

pub fn serialize(inon: *Inon, data: *Data, writer: anytype) @TypeOf(writer).Error!void {
    _ = inon;
    try data.serialize(4, writer, .{});
}

pub fn serializeToJson(inon: *Inon, data: *Data, writer: anytype) @TypeOf(writer).Error!void {
    _ = inon;
    try data.serializeToJson(4, writer);
}

pub fn renderError(inon: *Inon, writer: anytype) !void {
    try inon.diagnostics.print(writer);
}

const matchers = ptk.matchers;

const Parser = struct {
    const Self = @This();

    const TokenType = enum {
        number,
        hex_number,
        bin_number,
        oct_number,
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
        Pattern.create(.number, decimalMatcher),
        Pattern.create(.hex_number, hexaMatcher),
        Pattern.create(.bin_number, binMatcher),
        Pattern.create(.oct_number, octaMatcher),
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

    pub fn parse(source: []const u8, name: []const u8, inon: *Inon) ParseError!Data {
        var tokenizer = Tokenizer.init(source, name);

        var parser = Parser{
            .core = ParserCore.init(&tokenizer),
            .inon = inon,
        };

        parser.inon.current_context = &parser.inon.context;
        return parser.acceptObjectNoCtx(&inon.context);
    }

    core: ParserCore,
    inon: *Inon,
    fn_nested: bool = false,

    const ruleset = ptk.RuleSet(TokenType);

    const is_number = ruleset.is(.number);
    const is_hex_number = ruleset.is(.hex_number);
    const is_bin_number = ruleset.is(.bin_number);
    const is_oct_number = ruleset.is(.oct_number);
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

        try self.inon.diagnostics.emit(state.location, .@"error", format, args);
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

            if (try self.peek()) |tok| {
                if (is_comma(tok.type)) {
                    _ = try self.core.accept(is_comma);
                }
            }
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

            const token = (try self.peek()).?;
            if (is_comma(token.type)) {
                _ = try self.core.accept(is_comma);
            }
        }

        _ = try self.core.accept(is_rbrac);

        return data;
    }

    fn acceptAtom(self: *Self) ParseError!Data {
        const state = self.core.saveState();
        errdefer self.core.restoreState(state);

        if (try self.peek()) |token| {
            if (is_number(token.type)) {
                return self.acceptAtomNumber(.dec, is_number);
            } else if (is_hex_number(token.type)) {
                return self.acceptAtomNumber(.hex, is_hex_number);
            } else if (is_bin_number(token.type)) {
                return self.acceptAtomNumber(.bin, is_bin_number);
            } else if (is_oct_number(token.type)) {
                return self.acceptAtomNumber(.oct, is_oct_number);
            } else if (is_identifier(token.type)) {
                const tok = try self.core.accept(is_identifier);
                if (self.inon.functions.get(tok.text)) |_| {
                    if (self.fn_nested) {
                        try self.emitError("nested function calls has to be enclosed in parens", .{});
                        return error.ParsingFailed;
                    }
                    self.fn_nested = true;
                    defer self.fn_nested = false;
                    return self.acceptFunctionCall(tok);
                }
                return self.acceptAtomIdentifier(tok);
            } else if (is_string(token.type)) {
                return self.acceptAtomString();
            } else if (is_lpar(token.type)) {
                _ = (try self.core.accept(is_lpar));
                const tok = try self.core.accept(is_identifier);
                const atom = self.acceptFunctionCall(tok);
                _ = (try self.core.accept(is_rpar));
                return atom;
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

    const AtomNumType = enum { dec, hex, bin, oct };
    fn acceptAtomNumber(self: *Self, num_type: AtomNumType, comptime type_fn: anytype) !Data {
        const state = self.core.saveState();
        errdefer self.core.restoreState(state);

        const value = try self.core.accept(type_fn);

        return Data{ .value = .{
            .num = switch (num_type) {
                .dec => std.fmt.parseFloat(f64, value.text) catch unreachable,
                .hex => std.fmt.parseHexFloat(f64, value.text) catch unreachable,
                .bin, .oct => @intToFloat(f64, std.fmt.parseInt(i64, value.text, 0) catch unreachable),
            },
        } };
    }

    fn acceptAtomIdentifier(self: *Self, token: Tokenizer.Token) ParseError!Data {
        const state = self.core.saveState();
        errdefer self.core.restoreState(state);

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
                if (token[i] == '\\' and i + 1 < token.len) {
                    try str.value.str.append(str.allocator, blk: {
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
                    });
                } else if (token[i] == '{') {
                    i += 1;

                    // Bracket escape begin
                    if (token[i] == '{') {
                        try str.value.str.append(str.allocator, '{');
                        continue;
                    }

                    const in_end_pos = mem.indexOfScalar(u8, token[i..], '}');
                    if (in_end_pos) |pos| {
                        const sub_name = token[i .. pos + i];
                        if (sub_name.len == 0) {
                            try self.emitError("empty expressions not allowed in string interpolation", .{});
                            return error.ParsingFailed;
                        }

                        const data = self.inon.context.findEx(sub_name);

                        const writer = str.value.str.writer(str.allocator);
                        try data.serialize(0, writer, .{
                            .quote_string = false,
                            .write_newlines = false,
                        });

                        i += pos;
                    } else {
                        try self.emitError("unmatched '{{' in string interpolation", .{});
                        return error.ParsingFailed;
                    }
                } else if (token[i] == '}') {
                    // Bracket escape end
                    if (token[i + 1] == '}') {
                        try str.value.str.append(str.allocator, '}');
                        i += 1;
                    } else {
                        try self.emitError("stray '}}' outside of string interpolation", .{});
                        return error.ParsingFailed;
                    }
                } else {
                    try str.value.str.append(str.allocator, token[i]);
                }
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

    fn acceptFunctionCall(self: *Self, token: Tokenizer.Token) ParseError!Data {
        const state = self.core.saveState();
        errdefer self.core.restoreState(state);

        const fn_name = blk: {
            const text = token.text;
            if (mem.startsWith(u8, text, "'")) {
                break :blk text[1 .. text.len - 1];
            } else {
                break :blk text;
            }
        };

        var args = Data{ .value = .{ .array = .{} }, .allocator = self.inon.allocator };
        defer args.deinit();

        const func = if (self.inon.functions.get(fn_name)) |func| func else {
            try self.emitError("function '{s}' has not been defined", .{fn_name});
            return error.ParsingFailed;
        };
        const param_count = func.params.len;

        var i: usize = 0;
        while (i < param_count) : (i += 1) {
            if (try self.peek()) |_| {
                const arg = try self.acceptAtom();
                try args.value.array.append(args.allocator, arg);
            } else break;
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

        // Run the function and return the result
        return try func.run(self.inon, args.get(.array).items);
    }
};

// Tokenizer helpers

fn decimalMatcher(str: []const u8) ?usize {
    var i: usize = 0;
    var state: enum { num, other } = .other;

    switch (str[0]) {
        '-', '+' => {
            state = .other;
            i += 1;
        },
        '0'...'9' => {
            state = .num;
            i += 1;
        },
        else => return null,
    }

    var has_e = false;

    while (i < str.len) : (i += 1) {
        switch (str[i]) {
            '0'...'9' => {
                state = .num;
            },
            '_' => {
                if (state != .num) return null;
                state = .other;
            },
            '.' => {
                if (has_e or state != .num) return null;
                state = .other;
            },
            'e', 'E' => {
                if (state != .num) return null;

                if (mem.indexOfScalar(u8, "-+", str[i + 1]) != null) i += 1;

                state = .other;
                has_e = true;
            },
            'x', 'X', 'b', 'B', 'o', 'O' => return null,
            else => {
                if (state == .other) return null;
                break;
            },
        }
    }

    return i;
}

fn hexaMatcher(str: []const u8) ?usize {
    var i: usize = 0;
    var state: enum { num, other } = .other;

    switch (str[0]) {
        '-', '+' => {
            i += 1;
        },
        '0' => {},
        else => return null,
    }

    if (str[i] == '0') {
        if (std.ascii.toLower(str[i + 1]) == 'x') {
            i += 2;
        } else return null;
    } else return null;

    var has_e = false;

    while (i < str.len) : (i += 1) {
        switch (str[i]) {
            '0'...'9', 'a'...'f', 'A'...'F' => {
                state = .num;
            },
            '.' => {
                if (has_e or state != .num) return null;
                state = .other;
            },
            'p', 'P' => {
                if (state != .num) return null;

                if (mem.indexOfScalar(u8, "-+", str[i + 1]) != null) i += 1;

                state = .other;
                has_e = true;
            },
            else => {
                if (state == .other) return null;
                break;
            },
        }
    }

    return i;
}

fn octaBinMatcher(comptime prefix: u8, comptime radix: u8) fn (str: []const u8) ?usize {
    return struct {
        fn func(str: []const u8) ?usize {
            var i: usize = 0;
            var state: enum { num, other } = .other;

            switch (str[0]) {
                '-', '+' => {
                    i += 1;
                },
                '0' => {},
                else => return null,
            }

            if (str[i] != '0' and std.ascii.toLower(str[i + 1]) != prefix)
                return null;

            i += 2;

            const numbers = "012345678";
            while (i < str.len) : (i += 1) {
                if (mem.indexOfScalar(u8, numbers[0..radix], str[i]) != null) {
                    state = .num;
                } else if (str[i] == '_' and state != .other) {
                    state = .other;
                } else {
                    if (state == .other) return null;
                    break;
                }
            }

            return i;
        }
    }.func;
}

const binMatcher = octaBinMatcher('b', 2);
const octaMatcher = octaBinMatcher('o', 8);

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
