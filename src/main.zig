const std = @import("std");
const mem = std.mem;
const Allocator = mem.Allocator;
const ptk = @import("parser-toolkit");
pub const Data = @import("Data.zig");
pub const Stdlib = @import("Stdlib.zig");

const Inon = @This();

allocator: Allocator,
context: Data,
current_context: *Data,
diagnostics: ptk.Diagnostics,

pub fn init(allocator: Allocator) Inon {
    return .{
        .allocator = allocator,
        .diagnostics = ptk.Diagnostics.init(allocator),
        .context = .{
            .value = .{ .map = .{} },
            .allocator = allocator,
            .is_object = true,
        },
        .current_context = undefined,
    };
}

pub fn deinit(inon: *Inon) void {
    inon.diagnostics.deinit();
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
    inon.diagnostics.deinit();
    inon.diagnostics = ptk.Diagnostics.init(inon.allocator);
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
        symbol,
        fn_name,
        whitespace,
        comment,
        true,
        false,
        def,
        null,
        @":",
        @"(",
        @")",
        @"[",
        @"]",
        @"%{",
        @"{",
        @"}",
        @",",
    };

    const Pattern = ptk.Pattern(TokenType);

    const Tokenizer = ptk.Tokenizer(TokenType, &[_]Pattern{
        Pattern.create(.number, decimalMatcher),
        Pattern.create(.hex_number, hexaMatcher),
        Pattern.create(.bin_number, binMatcher),
        Pattern.create(.oct_number, octaMatcher),
        Pattern.create(.string, stringMatcher),
        Pattern.create(.true, matchers.literal("true")),
        Pattern.create(.false, matchers.literal("false")),
        Pattern.create(.def, matchers.literal("def")),
        Pattern.create(.null, matchers.literal("null")),
        Pattern.create(.whitespace, matchers.takeAnyOf(" \n\r\t")),
        Pattern.create(.comment, commentMatcher),
        Pattern.create(.@":", matchers.literal(":")),
        Pattern.create(.@"[", matchers.literal("[")),
        Pattern.create(.@"]", matchers.literal("]")),
        Pattern.create(.@"(", matchers.literal("(")),
        Pattern.create(.@")", matchers.literal(")")),
        Pattern.create(.@"%{", matchers.literal("%{")),
        Pattern.create(.@"{", matchers.literal("{")),
        Pattern.create(.@"}", matchers.literal("}")),
        Pattern.create(.@",", matchers.literal(",")),
        Pattern.create(.identifier, identifierMatcher),
        Pattern.create(.symbol, symbolMatcher),
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
    const is_symbol = ruleset.is(.symbol);
    const is_string = ruleset.is(.string);
    const is_true = ruleset.is(.true);
    const is_false = ruleset.is(.false);
    const is_def = ruleset.is(.def);
    const is_null = ruleset.is(.null);
    const is_colon = ruleset.is(.@":");
    const is_lpar = ruleset.is(.@"(");
    const is_rpar = ruleset.is(.@")");
    const is_ebrac = ruleset.is(.@"%{");
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

    fn rulesetName(comptime rule: ParserCore.Rule) []const u8 {
        return switch (rule) {
            is_number => "number",
            is_identifier => "identifier",
            is_symbol => "symbol",
            is_string => "string",
            is_lpar => "(",
            is_rpar => ")",
            is_lbrac => "{",
            is_rbrac => "}",
            is_comma => ",",
            is_lsqr => "[",
            is_rsqr => "]",
            else => "unknown",
        };
    }

    fn accept(self: *Self, comptime rule: ParserCore.Rule) !Tokenizer.Token {
        const name = rulesetName(rule);
        return self.core.accept(rule) catch |err| switch (err) {
            error.UnexpectedToken => {
                try self.emitError("expected '{s}', found '{s}'", .{
                    name,
                    @tagName((self.peek() catch unreachable).?.type),
                });
                return error.ParsingFailed;
            },
            error.EndOfStream => {
                try self.emitError("expected '{s}', found end of stream", .{name});
                return error.ParsingFailed;
            },
            error.UnexpectedCharacter => {
                try self.emitError("found unknown character", .{});
                return error.ParsingFailed;
            },
        };
    }

    fn optional(self: *Self, comptime rule: ParserCore.Rule) !void {
        if (try self.peek()) |token| {
            if (rule(token.type)) {
                // NOTE: may need to use self.accept instead to prevent error.EndOfStream
                // Not sure if that is even reachable from this path.
                _ = try self.core.accept(rule);
            }
        }
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

    const Extension = enum { extended, non_extended };

    fn acceptTopLevelExpr(self: *Self, context: *Data, extension: Extension) ParseError!void {
        const state = self.core.saveState();
        errdefer self.core.restoreState(state);

        const allocator = self.inon.allocator;
        var key: Data = Data{ .value = .{ .str = .{} }, .allocator = allocator };
        errdefer key.deinit();

        switch (extension) {
            .non_extended => try key.value.str.appendSlice(allocator, (try self.accept(is_identifier)).text),
            .extended => {
                if (try self.peek()) |token| {
                    if (is_identifier(token.type)) {
                        try key.value.str.appendSlice(allocator, (try self.core.accept(is_identifier)).text);
                    } else {
                        key = try self.acceptAtom();
                    }
                }
            },
        }

        const val = blk: {
            if (try self.peek()) |token| {
                if (is_colon(token.type)) {
                    var prev = context.getEx(key);
                    if (prev) |*prev_data|
                        prev_data.deinit();

                    break :blk try acceptAssignment(self);
                } else {
                    try self.emitError("expected ':' after identifier", .{});
                    return error.ParsingFailed;
                }
            } else {
                try self.emitError("found stray identifier", .{});
                return error.ParsingFailed;
            }
        };

        try context.value.map.put(
            self.inon.allocator,
            key,
            val,
        );
    }

    fn acceptObjectNoCtx(self: *Self, context: *Data) ParseError!Data {
        const state = self.core.saveState();
        errdefer self.core.restoreState(state);

        while ((try self.peek()) != null) {
            try self.acceptTopLevelExpr(context, .non_extended);
            try self.optional(is_comma);
        }

        return context.*;
    }

    fn acceptObject(self: *Self, extension: Extension) ParseError!Data {
        const state = self.core.saveState();
        errdefer self.core.restoreState(state);

        var data = Data.null_data;
        errdefer data.deinit();

        switch (extension) {
            .non_extended => {
                data = Data{
                    .value = .{ .map = .{} },
                    .allocator = self.inon.allocator,
                    .is_object = true,
                };
                _ = try self.core.accept(is_lbrac);
            },
            .extended => {
                data = Data{ .value = .{ .map = .{} }, .allocator = self.inon.allocator };
                _ = try self.core.accept(is_ebrac);
            },
        }

        const old_context = self.inon.current_context;
        self.inon.current_context = &data;
        defer self.inon.current_context = old_context;

        while (try self.peek()) |token| {
            if (is_rbrac(token.type))
                break;

            try self.acceptTopLevelExpr(&data, extension);
            try self.optional(is_comma);
        }

        _ = try self.accept(is_rbrac);

        if (data.get("return")) |ret_val|
            return ret_val;

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
            } else if (is_identifier(token.type) or is_symbol(token.type)) {
                const ident = is_identifier(token.type);

                // Accept an identifier or a symbol
                const tok = blk: {
                    if (ident) {
                        break :blk try self.core.accept(is_identifier);
                    } else {
                        break :blk try self.core.accept(is_symbol);
                    }
                };

                if (self.inon.context.get(tok.text)) |prob_func| {
                    if (prob_func.is(.func) or prob_func.is(.native)) {
                        if (self.fn_nested) {
                            try self.emitError("nested function calls has to be enclosed in parens", .{});
                            return error.ParsingFailed;
                        }
                        self.fn_nested = true;
                        defer self.fn_nested = false;
                        return self.acceptFunctionCall(tok);
                    }
                }

                if (ident) {
                    return self.acceptAtomIdentifier(tok);
                } else {
                    try self.emitError("undeclared symbol referenced", .{});
                    return error.ParsingFailed;
                }
            } else if (is_string(token.type)) {
                return self.acceptAtomString();
            } else if (is_lpar(token.type)) {
                _ = (try self.core.accept(is_lpar));

                // Accept an identifier or a symbol
                const tok = if (try self.peek()) |tok| blk: {
                    if (is_identifier(tok.type)) {
                        break :blk try self.core.accept(is_identifier);
                    } else if (is_symbol(tok.type)) {
                        break :blk try self.core.accept(is_symbol);
                    }

                    try self.emitError("expected 'symbol' or 'identifier' as function name, found '{s}'", .{@tagName(tok.type)});
                    return error.ParsingFailed;
                } else {
                    // NOTE: The below line should not be needed, a compiler bug?
                    return error.ParsingFailed;
                };

                const atom = self.acceptFunctionCall(tok);
                _ = try self.accept(is_rpar);
                return atom;
            } else if (is_lsqr(token.type)) {
                return self.acceptAtomList();
            } else if (is_ebrac(token.type)) {
                return self.acceptObject(.extended);
            } else if (is_lbrac(token.type)) {
                return self.acceptObject(.non_extended);
            } else if (is_true(token.type)) {
                _ = (try self.core.accept(is_true));
                return Data{ .value = .{ .bool = true } };
            } else if (is_false(token.type)) {
                _ = (try self.core.accept(is_false));
                return Data{ .value = .{ .bool = false } };
            } else if (is_def(token.type)) {
                return self.acceptFunctionDef();
            } else if (is_null(token.type)) {
                _ = (try self.core.accept(is_null));
                return Data.null_data;
            } else {
                try self.emitError("expected expression, literal or function call", .{});
                return error.ParsingFailed;
            }
        }

        try self.emitError("expected expression, found end of stream", .{});
        return error.ParsingFailed;
    }

    const AtomNumType = enum { dec, hex, bin, oct };
    fn acceptAtomNumber(self: *Self, num_type: AtomNumType, comptime type_fn: anytype) !Data {
        const state = self.core.saveState();
        errdefer self.core.restoreState(state);

        const value = try self.core.accept(type_fn);

        return Data{ .value = .{
            .num = switch (num_type) {
                .dec, .hex => std.fmt.parseFloat(f64, value.text) catch unreachable,
                .bin, .oct => @as(f64, @floatFromInt(std.fmt.parseInt(i64, value.text, 0) catch unreachable)),
            },
        } };
    }

    fn acceptAtomIdentifier(self: *Self, token: Tokenizer.Token) ParseError!Data {
        const state = self.core.saveState();
        errdefer self.core.restoreState(state);

        if (self.inon.context.getEx(token.text)) |data|
            return data.copy(self.inon.allocator);

        try self.emitError("undeclared identifier '{s}' referenced", .{token.text});
        return error.ParsingFailed;
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
            while (true) {
                try str.value.str.appendSlice(str.allocator, token[2..]);

                if (try self.peek()) |tok| {
                    if (is_string(tok.type)) {
                        raw_string = mem.startsWith(u8, tok.text, "\\");
                        if (!raw_string)
                            break;
                        token = (try self.core.accept(is_string)).text;
                        try str.value.str.append(str.allocator, '\n');
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

                        if (self.inon.context.getEx(sub_name)) |data| {
                            const writer = str.value.str.writer(str.allocator);

                            try data.serialize(0, writer, .{
                                .quote_string = false,
                                .write_newlines = false,
                            });
                        }

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
            try self.optional(is_comma);
        }

        _ = try self.accept(is_rsqr);

        return data;
    }

    fn identifierToType(self: *Self, ident: []const u8) ?Data.Type {
        _ = self;
        return std.meta.stringToEnum(Data.Type, ident);
    }

    fn acceptFunctionDef(self: *Self) ParseError!Data {
        const state = self.core.saveState();
        errdefer self.core.restoreState(state);

        _ = try self.core.accept(is_def);
        _ = try self.accept(is_lpar);

        var params: std.ArrayListUnmanaged(Data.Param) = .{};
        while (try self.peek()) |tok| {
            if (is_rpar(tok.type))
                break;

            const ident = try self.accept(is_identifier);
            _ = try self.accept(is_colon);
            const ty = try self.accept(is_identifier);

            try params.append(self.inon.allocator, .{
                .name = try self.inon.allocator.dupe(u8, ident.text),
                .type = self.identifierToType(ty.text),
            });

            if (try self.peek()) |tk| {
                if (is_rpar(tk.type))
                    break;

                _ = try self.accept(is_comma);
            }
        }

        _ = try self.accept(is_rpar);

        const code = try self.acceptAtomString();
        return Data{
            .value = .{
                .func = .{
                    .params = try params.toOwnedSlice(self.inon.allocator),
                    .code = code.value.str.items,
                },
            },
            .allocator = self.inon.allocator,
        };
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
        var func = self.inon.context.get(fn_name) orelse Data.null_data;

        if (func.is(.nulled)) {
            try self.emitError("function '{s}' has not been defined", .{fn_name});
            return error.ParsingFailed;
        }

        const params = if (func.is(.func)) func.raw(.func).?.params else func.raw(.native).?.params;

        // Collect arguments
        var i: usize = 0;
        while (i < params.len) : (i += 1) {
            if (try self.peek()) |_| {
                const arg = try self.acceptAtom();
                try args.value.array.append(args.allocator, arg);
            } else break;
        }

        // Validate argument count
        const no_of_args = args.raw(.array).?.items.len;
        if (no_of_args != params.len) {
            try self.emitError("function '{s}' takes {} args, found {}", .{ fn_name, params.len, no_of_args });
            return error.ParsingFailed;
        }

        // Validate argument type
        for (params, 0..) |param, idx| {
            const arg = args.raw(.array).?.items[idx];
            if (param.type) |ty| {
                if (!arg.is(ty)) {
                    try self.emitError(
                        "function '{s}' expects argument {} be of type '{s}' while '{s}' is given",
                        .{
                            fn_name,
                            idx,
                            @tagName(ty),
                            @tagName(arg.value),
                        },
                    );
                    return error.ParsingFailed;
                }
            }
        }

        if (func.is(.func)) {
            return try self.callFunction(&func.value.func, args.value.array.items, fn_name);
        }

        return try self.callNative(&func.value.native, args.raw(.array).?.items);
    }

    pub fn callFunction(self: *Self, func: *Data.Function, args: []Data, fn_name: []const u8) !Data {
        var ctx = try self.inon.context.copy(self.inon.allocator);

        for (args, 0..) |arg, idx| {
            const param = func.params[idx];
            try ctx.value.map.put(
                self.inon.allocator,
                Data{
                    .value = .{ .str = Data.String.fromOwnedSlice(
                        try self.inon.allocator.dupe(u8, param.name),
                    ) },
                    .allocator = self.inon.allocator,
                },
                try arg.copy(self.inon.allocator),
            );
        }

        var inon = Inon.init(self.inon.allocator);
        defer inon.deinit();

        inon.context = ctx;

        try Inon.Stdlib.addAll(&inon);

        const val = inon.parse(fn_name, func.code) catch |err| switch (err) {
            error.ParsingFailed => {
                for (inon.diagnostics.errors.items) |ierr| {
                    const di_alloc = self.inon.diagnostics.memory.allocator();

                    var new_err = ierr;
                    if (ierr.location.source) |src|
                        new_err.location.source = try di_alloc.dupe(u8, src);
                    new_err.message = try di_alloc.dupeZ(u8, ierr.message);

                    try self.inon.diagnostics.errors.append(self.inon.allocator, new_err);
                }
                return error.ParsingFailed;
            },
            else => |e| return e,
        };
        const ret = try (val.get("return") orelse Data.null_data).copy(self.inon.allocator);
        return ret;
    }

    pub fn callNative(self: *Self, func: *Data.NativeFunction, args: []Data) !Data {
        // Run the function and return the result
        return try func.run(self.inon, args);
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
    if (!(mem.startsWith(u8, str, "\"") or mem.startsWith(u8, str, "\'") or raw_string))
        return null;

    var i: usize = 1;
    while (i < str.len) : (i += 1) {
        switch (str[i]) {
            '\\' => i += 1,
            '\"', '\'' => if (!raw_string) {
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
    const first_char = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ_";
    const all_chars = first_char ++ "0123456789";
    for (str, 0..) |c, i| {
        if (std.mem.indexOfScalar(u8, if (i > 0) all_chars else first_char, c) == null) {
            return i;
        }
    }
    return str.len;
}

fn symbolMatcher(str: []const u8) ?usize {
    const chars = "!#$%&*+-./;<=>@\\^_`|~";
    for (str, 0..) |c, i| {
        if (std.mem.indexOfScalar(u8, chars, c) == null) {
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
