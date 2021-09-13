const std = @import("std");

pub const TokenType = enum {
    string,
    raw_string,
    identifier,
    number,
    tru,
    fals,
    iff,
    els,

    assignment,
    equality,
    plus,
    concat,
    minus,
    multiply,
    repeat,
    divide,
    floor,
    modulo,
    greater,
    less,
    greateql,
    lesseql,
    bang,
    amp,
    orop,

    semicolon,
    lpar,
    rpar,
    lbra,
    rbra,
    lsqr,
    rsqr,
    comma,
    dot,

    unused,
    eof,
};

pub const Token = struct {
    toktype: TokenType,
    content: []const u8,
};

pub const Lexer = struct {
    src: []const u8,
    pos: u32 = 0,
    line: usize = 1,

    const Self = @This();

    pub fn init(src: []const u8) Self {
        return .{
            .src = src,
        };
    }

    pub fn free(self: *Self) void {
        _ = self;
    }

    inline fn peek(self: *Self) u8 {
        if (self.isEof()) return 0;
        return self.src[self.pos];
    }

    inline fn next(self: *Self) u8 {
        self.pos += 1;
        return self.src[self.pos - 1];
    }

    inline fn skipWhitespace(self: *Self) void {
        while (true) {
            switch (self.peek()) {
                '\n' => {
                    self.line += 1;
                    self.pos += 1;
                },
                '#' => {
                    while (self.peek() != '\n')
                        self.pos += 1;
                    self.line += 1;
                },
                ' ', '\r', '\t' => _ = self.next(),
                else => return,
            }
        }
    }

    inline fn isEof(self: *Self) bool {
        return self.pos == self.src.len;
    }

    inline fn matches(self: *Self, c: u8) bool {
        if (self.peek() != c)
            return false;
        self.pos += 1;
        return true;
    }

    pub fn getToken(self: *Self) Token {
        self.skipWhitespace();

        if (self.isEof())
            return self.makeToken(.eof, 0);

        var c = self.next();

        return switch (c) {
            ';' => self.makeToken(.semicolon, 0),
            '=' => self.makeToken(if (self.matches('=')) .equality else .assignment, 0),
            '+' => self.makeToken(if (self.matches('+')) .concat else .plus, 0),
            '-' => self.makeToken(.minus, 0),
            '*' => self.makeToken(if (self.matches('*')) .repeat else .multiply, 0),
            '/' => self.makeToken(if (self.matches('/')) .floor else .divide, 0),
            '%' => self.makeToken(.modulo, 0),
            '(' => self.makeToken(.lpar, 0),
            ')' => self.makeToken(.rpar, 0),
            '{' => self.makeToken(.lbra, 0),
            '}' => self.makeToken(.rbra, 0),
            '[' => self.makeToken(.lsqr, 0),
            ']' => self.makeToken(.rsqr, 0),
            ',' => self.makeToken(.comma, 0),
            '.' => self.makeToken(.dot, 0),
            '!' => self.makeToken(.bang, 0),
            '>' => self.makeToken(if (self.matches('=')) .greateql else .greater, 0),
            '<' => self.makeToken(if (self.matches('=')) .lesseql else .less, 0),
            '&' => self.makeToken(if (self.matches('&')) .amp else .unused, 0),
            '|' => self.makeToken(if (self.matches('|')) .orop else .unused, 0),
            '\"' => self.string(),
            '\\' => self.rawString(),
            else => {
                if (std.ascii.isDigit(c)) return self.number();
                if (std.ascii.isAlpha(c) or c == '_') {
                    const ident = self.identifier();
                    if (std.mem.eql(u8, ident.content, "true")) {
                        return self.makeToken(.tru, 0);
                    } else if (std.mem.eql(u8, ident.content, "false")) {
                        return self.makeToken(.fals, 0);
                    } else if (std.mem.eql(u8, ident.content, "if")) {
                        return self.makeToken(.iff, 0);
                    } else if (std.mem.eql(u8, ident.content, "else")) {
                        return self.makeToken(.els, 0);
                    } else return ident;
                }
                return self.makeToken(.eof, 0);
            },
        };
    }

    inline fn makeToken(self: *Self, toktype: TokenType, start: usize) Token {
        return Token{ .toktype = toktype, .content = self.src[start..self.pos] };
    }

    fn string(self: *Self) Token {
        _ = self.next();
        const start = self.pos - 1;
        while (self.peek() != '\"') {
            if (self.peek() == '\\')
                _ = self.next();
            _ = self.next();
        }

        const tok = self.makeToken(.string, start);
        _ = self.next();

        return tok;
    }

    fn rawString(self: *Self) Token {
        // Zig style raw strings
        if (self.next() == '\\') {
            const start = self.pos;
            while (self.next() != '\n') {}

            return self.makeToken(.raw_string, start);
        }
        return self.makeToken(.eof, 0);
    }

    fn number(self: *Self) Token {
        const start = self.pos - 1;
        while (std.ascii.isDigit(self.peek()))
            _ = self.next();

        if (self.peek() == '.' and std.ascii.isDigit(self.src[self.pos + 1])) {
            _ = self.next();
            while (std.ascii.isDigit(self.peek()))
                _ = self.next();
        }

        if (self.peek() == 'e' or self.peek() == 'E') {
            _ = self.next();

            if (self.peek() == '-' or self.peek() == '+')
                _ = self.next();

            while (std.ascii.isDigit(self.peek()))
                _ = self.next();
        }

        return self.makeToken(.number, start);
    }

    fn identifier(self: *Self) Token {
        const start = self.pos - 1;
        while (std.ascii.isAlNum(self.peek()) or self.peek() == '_')
            _ = self.next();

        return self.makeToken(.identifier, start);
    }
};

fn expectTokenTypes(src: []const u8, tokens: []const TokenType) !void {
    var lexer = Lexer.init(src);
    defer lexer.free();
    for (tokens) |token| {
        try std.testing.expectEqual(token, lexer.getToken().toktype);
    }
}

fn expectToken(src: []const u8, tokens: []const Token) !void {
    var lexer = Lexer.init(src);
    defer lexer.free();
    for (tokens) |token| {
        const this_tok = lexer.getToken();
        try std.testing.expectEqual(token.toktype, this_tok.toktype);
        try std.testing.expectEqualStrings(token.content, this_tok.content);
    }
}

test "operators" {
    try expectTokenTypes(
        \\ + - * /
        \\ ++ **
        \\ % //
        \\ && || .
        \\ = == > < >= <=
        \\ !
    , &[_]TokenType{
        .plus,
        .minus,
        .multiply,
        .divide,
        .concat,
        .repeat,
        .modulo,
        .floor,
        .amp,
        .orop,
        .dot,
        .assignment,
        .equality,
        .greater,
        .less,
        .greateql,
        .lesseql,
        .bang,
    });
}

test "symbols" {
    try expectTokenTypes(
        \\ ; 
        \\ ( ) 
        \\ { } 
        \\ [ ] 
        \\ ,
    , &[_]TokenType{
        .semicolon,
        .lpar,
        .rpar,
        .lbra,
        .rbra,
        .lsqr,
        .rsqr,
        .comma,
    });
}

test "keywords" {
    try expectTokenTypes(
        \\ true false if else
    , &[_]TokenType{
        .tru,
        .fals,
        .iff,
        .els,
    });
}

test "numbers" {
    try expectToken(
        \\ 11
        \\ 20.04
        \\ 4.0E12
        \\ 5.1e-11
    , &[_]Token{
        .{ .toktype = .number, .content = "11" },
        .{ .toktype = .number, .content = "20.04" },
        .{ .toktype = .number, .content = "4.0E12" },
        .{ .toktype = .number, .content = "5.1e-11" },
    });
}

test "identifiers" {
    try expectToken(
        \\ test
        \\ __complex__
        \\ mix_2130
    , &[_]Token{
        .{ .toktype = .identifier, .content = "test" },
        .{ .toktype = .identifier, .content = "__complex__" },
        .{ .toktype = .identifier, .content = "mix_2130" },
    });
}

test "strings" {
    try expectToken(
        \\ "hello world"
        \\ "\tescape\tworld\"\n"
        \\ \\long long
    , &[_]Token{
        .{ .toktype = .string, .content = "hello world" },
        .{ .toktype = .string, .content = "\\tescape\\tworld\\\"\\n" },
        .{ .toktype = .raw_string, .content = "long long" },
    });
}
